import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/message_thread.dart';
import 'chat_errors.dart';
import 'chat_local_cache.dart';
import 'chat_message_outbox.dart';
import 'chat_realtime_service.dart';
import 'chat_remote_data_source.dart';

class ChatDiagnostics {
  const ChatDiagnostics({
    required this.userId,
    required this.realtimeStatus,
    required this.activeChannel,
    required this.lastSync,
    required this.lastError,
    required this.pendingOutboxCount,
  });

  final String userId;
  final ChatRealtimeConnectionStatus realtimeStatus;
  final String? activeChannel;
  final DateTime? lastSync;
  final ChatFailure? lastError;
  final int pendingOutboxCount;
}

class ChatRepository extends ChangeNotifier {
  ChatRepository({
    required SupabaseClient client,
    required SharedPreferences preferences,
  }) : remote = ChatRemoteDataSource(client),
       outbox = ChatMessageOutbox(ChatLocalCache(preferences)),
       realtime = ChatRealtimeService(client) {
    realtime.addListener(notifyListeners);
  }

  final ChatRemoteDataSource remote;
  final ChatMessageOutbox outbox;
  final ChatRealtimeService realtime;

  String _userId = '';
  int _activationGeneration = 0;
  DateTime? _lastSync;
  ChatFailure? _lastError;
  FutureOr<void> Function(Map<String, dynamic> row)? _onMessage;

  String get userId => _userId;
  ChatFailure? get lastError => _lastError ?? realtime.lastError;
  ChatDiagnostics get diagnostics => ChatDiagnostics(
    userId: _userId,
    realtimeStatus: realtime.status,
    activeChannel: realtime.activeChannel,
    lastSync: _lastSync,
    lastError: lastError,
    pendingOutboxCount: outbox.pendingCount,
  );

  Future<void> activate({
    required String userId,
    required FutureOr<void> Function(Map<String, dynamic> row) onMessage,
    required VoidCallback onThreadInvalidated,
    required FutureOr<void> Function() onGapSync,
  }) async {
    final identity = userId.trim();
    if (identity.isEmpty) return;
    final generation = ++_activationGeneration;
    _userId = identity;
    _onMessage = onMessage;
    await outbox.activate(identity);
    if (generation != _activationGeneration || _userId != identity) return;
    await realtime.start(
      userId: identity,
      onMessage: (_, row) => onMessage(row),
      onThreadInvalidated: onThreadInvalidated,
      onConnected: () async {
        await onGapSync();
        _lastSync = DateTime.now().toUtc();
        notifyListeners();
      },
    );
    if (generation != _activationGeneration || _userId != identity) return;
    notifyListeners();
  }

  Future<void> deactivate() async {
    final generation = ++_activationGeneration;
    _userId = '';
    _onMessage = null;
    outbox.deactivate();
    await realtime.stop();
    if (generation != _activationGeneration) return;
    notifyListeners();
  }

  Future<void> onForeground() async {
    if (_userId.isEmpty) return;
    await realtime.reconnect();
  }

  Future<ChatResult<RemoteThreadCreation>> createDirectThread(
    String otherUserId,
  ) => _record(remote.createDirectThread(otherUserId));

  Future<ChatResult<RemoteThreadCreation>> createProductThread(
    String productId,
  ) => _record(remote.createProductThread(productId));

  Future<ChatResult<RemoteThreadCreation>> createGroupThread({
    required List<String> memberIds,
    required String title,
    required String requestId,
  }) async {
    final requestUserId = _userId;
    if (requestUserId.isEmpty) {
      return const ChatFailureResult(
        ChatFailure(
          code: ChatFailureCode.unauthenticated,
          operation: 'create_group_thread',
        ),
      );
    }
    var result = await _record(
      remote.createGroupThread(
        memberIds: memberIds,
        title: title,
        requestId: requestId,
      ),
    );
    if (_userId != requestUserId) return result;
    if (result case ChatFailureResult<RemoteThreadCreation>(
      :final failure,
    ) when failure.isAmbiguous) {
      // The request id is only an idempotency input. The caller still
      // materializes the canonical thread exclusively from the RPC row.
      result = await _record(
        remote.createGroupThread(
          memberIds: memberIds,
          title: title,
          requestId: requestId,
        ),
      );
    }
    return result;
  }

  Future<ChatResult<Map<String, dynamic>>> sendMessage({
    required String threadId,
    required ChatMessage message,
  }) async {
    final requestUserId = _userId;
    if (requestUserId.isEmpty) {
      return const ChatFailureResult(
        ChatFailure(
          code: ChatFailureCode.unauthenticated,
          operation: 'send_message',
        ),
      );
    }
    await outbox.put(threadId, message);
    if (_userId != requestUserId) {
      return const ChatFailureResult(
        ChatFailure(
          code: ChatFailureCode.unauthenticated,
          operation: 'send_message_session_changed',
        ),
      );
    }
    var result = await _record(
      remote.sendMessage(threadId: threadId, message: message),
    );
    if (_userId != requestUserId) return result;
    if (result is ChatFailureResult<Map<String, dynamic>>) {
      // A transport error may arrive after Postgres committed. Resolve the
      // idempotency key before marking the user's text as failed.
      final reconciliation = await remote.getMessageByClientId(
        threadId: threadId,
        clientMessageId: message.clientMessageId,
      );
      final existing = reconciliation.valueOrNull;
      if (existing != null) result = ChatSuccess(existing);
    }
    if (_userId != requestUserId) return result;
    if (result is ChatSuccess<Map<String, dynamic>>) {
      await outbox.remove(message.clientMessageId);
    } else {
      await outbox.markFailed(message.clientMessageId);
    }
    notifyListeners();
    return result;
  }

  Future<ChatResult<RemoteProductMessageResult>> sendProductChatMessage({
    required String productId,
    required ChatMessage message,
  }) async {
    final requestUserId = _userId;
    if (requestUserId.isEmpty) {
      return const ChatFailureResult(
        ChatFailure(
          code: ChatFailureCode.unauthenticated,
          operation: 'send_product_chat_message',
        ),
      );
    }
    var result = await _record(
      remote.sendProductChatMessage(
        productId: productId,
        clientMessageId: message.clientMessageId,
        text: message.text,
      ),
    );
    if (_userId != requestUserId) return result;
    if (result case ChatFailureResult<RemoteProductMessageResult>(
      :final failure,
    ) when failure.isAmbiguous) {
      // The first transaction may have committed before the response was
      // lost. The product RPC is idempotent, so retry the exact same client id
      // and let the server return the already-created thread/message.
      result = await _record(
        remote.sendProductChatMessage(
          productId: productId,
          clientMessageId: message.clientMessageId,
          text: message.text,
        ),
      );
    }
    return result;
  }

  Future<ChatResult<Map<String, dynamic>?>> findMessage({
    required String threadId,
    required String clientMessageId,
  }) => _record(
    remote.getMessageByClientId(
      threadId: threadId,
      clientMessageId: clientMessageId,
    ),
  );

  Future<ChatResult<ChatMessagePage>> loadLatest(
    String threadId, {
    int limit = 50,
  }) => _record(remote.fetchLatestMessages(threadId, limit: limit));

  Future<ChatResult<ChatMessagePage>> loadOlder(
    String threadId, {
    required ChatCursor before,
    int limit = 50,
  }) => _record(
    remote.fetchOlderMessages(threadId, before: before, limit: limit),
  );

  Future<ChatResult<List<Map<String, dynamic>>>> loadAfter(
    String threadId, {
    required ChatCursor after,
  }) => _record(remote.fetchMessagesAfter(threadId, after: after));

  Future<ChatResult<void>> acknowledgeDelivered({
    required String threadId,
    required List<String> messageIds,
  }) => _record(
    remote.acknowledgeDelivered(threadId: threadId, messageIds: messageIds),
  );

  Future<void> reconcileOutbox() async {
    if (_userId.isEmpty || outbox.records.isEmpty) return;
    final reconcileUserId = _userId;
    final records = outbox.records.toList(growable: false);
    for (final record in records) {
      if (_userId != reconcileUserId) return;
      final result = await remote.getMessageByClientId(
        threadId: record.threadId,
        clientMessageId: record.message.clientMessageId,
      );
      if (_userId != reconcileUserId) return;
      final row = result.valueOrNull;
      if (row != null) {
        await outbox.remove(record.message.clientMessageId);
        if (_userId != reconcileUserId) return;
        await _onMessage?.call(row);
      } else if (result is ChatSuccess<Map<String, dynamic>?>) {
        // A process death can happen after the local outbox write but before
        // the RPC starts. A successful lookup proving there is no server row
        // turns that stale "sending" entry into an explicit retryable failure.
        await outbox.markFailed(record.message.clientMessageId);
      }
    }
    if (_userId != reconcileUserId) return;
    notifyListeners();
  }

  Future<ChatResult<T>> _record<T>(Future<ChatResult<T>> request) async {
    final result = await request;
    if (result case ChatFailureResult<T>(:final failure)) {
      _lastError = failure;
      logChatFailure(failure, userId: _userId);
    } else {
      _lastError = null;
      _lastSync = DateTime.now().toUtc();
    }
    notifyListeners();
    return result;
  }

  @override
  void dispose() {
    _activationGeneration++;
    _userId = '';
    _onMessage = null;
    outbox.deactivate();
    realtime.removeListener(notifyListeners);
    realtime.dispose();
    super.dispose();
  }
}
