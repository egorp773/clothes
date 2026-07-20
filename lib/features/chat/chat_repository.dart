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
    _userId = identity;
    _onMessage = onMessage;
    await outbox.activate(identity);
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
    notifyListeners();
  }

  Future<void> deactivate() async {
    _userId = '';
    _onMessage = null;
    outbox.deactivate();
    await realtime.stop();
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
    required String clientThreadId,
  }) => _record(
    remote.createGroupThread(
      memberIds: memberIds,
      title: title,
      clientThreadId: clientThreadId,
    ),
  );

  Future<ChatResult<Map<String, dynamic>>> sendMessage({
    required String threadId,
    required ChatMessage message,
  }) async {
    await outbox.put(threadId, message);
    var result = await _record(
      remote.sendMessage(threadId: threadId, message: message),
    );
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
  }) {
    return _record(
      remote.sendProductChatMessage(
        productId: productId,
        clientMessageId: message.clientMessageId,
        text: message.text,
      ),
    );
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
    final records = outbox.records.toList(growable: false);
    for (final record in records) {
      if (_userId.isEmpty) return;
      final result = await remote.getMessageByClientId(
        threadId: record.threadId,
        clientMessageId: record.message.clientMessageId,
      );
      final row = result.valueOrNull;
      if (row != null) {
        await outbox.remove(record.message.clientMessageId);
        await _onMessage?.call(row);
      }
    }
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
    realtime.removeListener(notifyListeners);
    realtime.dispose();
    super.dispose();
  }
}
