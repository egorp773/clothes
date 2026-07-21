import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_errors.dart';

enum ChatRealtimeConnectionStatus { disconnected, connecting, connected, error }

typedef ChatRealtimeRowCallback =
    FutureOr<void> Function(
      PostgresChangeEvent event,
      Map<String, dynamic> row,
    );

typedef ChatRealtimeSubscriptionCallback =
    void Function(RealtimeSubscribeStatus status, Object? error);

@visibleForTesting
abstract interface class ChatRealtimeChannelAdapter {
  ChatRealtimeChannelAdapter onPostgresChanges({
    required PostgresChangeEvent event,
    required String schema,
    required String table,
    required ChatRealtimeRowCallback callback,
  });

  void subscribe(ChatRealtimeSubscriptionCallback callback);

  Future<void> remove();
}

typedef ChatRealtimeChannelFactory =
    ChatRealtimeChannelAdapter Function(String channelName);

class _SupabaseChatRealtimeChannel implements ChatRealtimeChannelAdapter {
  _SupabaseChatRealtimeChannel(this._client, this._channel);

  final SupabaseClient _client;
  final RealtimeChannel _channel;

  @override
  ChatRealtimeChannelAdapter onPostgresChanges({
    required PostgresChangeEvent event,
    required String schema,
    required String table,
    required ChatRealtimeRowCallback callback,
  }) {
    _channel.onPostgresChanges(
      event: event,
      schema: schema,
      table: table,
      callback: (payload) {
        final row = payload.eventType == PostgresChangeEvent.delete
            ? payload.oldRecord
            : payload.newRecord;
        if (row.isNotEmpty) {
          callback(payload.eventType, Map<String, dynamic>.from(row));
        }
      },
    );
    return this;
  }

  @override
  void subscribe(ChatRealtimeSubscriptionCallback callback) {
    _channel.subscribe(callback);
  }

  @override
  Future<void> remove() async {
    await _client.removeChannel(_channel);
  }
}

class ChatRealtimeService extends ChangeNotifier {
  ChatRealtimeService(SupabaseClient client)
    : _channelFactory = ((channelName) =>
          _SupabaseChatRealtimeChannel(client, client.channel(channelName)));

  @visibleForTesting
  ChatRealtimeService.testing({
    required ChatRealtimeChannelFactory channelFactory,
  }) : _channelFactory = channelFactory;

  final ChatRealtimeChannelFactory _channelFactory;
  ChatRealtimeChannelAdapter? _channel;
  Timer? _retryTimer;
  int _generation = 0;
  String _userId = '';
  ChatRealtimeRowCallback? _onMessage;
  VoidCallback? _onThreadInvalidated;
  FutureOr<void> Function()? _onConnected;

  ChatRealtimeConnectionStatus _status =
      ChatRealtimeConnectionStatus.disconnected;
  ChatFailure? _lastError;
  DateTime? _lastConnectedAt;
  String? _activeChannel;
  Future<void> _messageQueue = Future<void>.value();
  bool _isDisposed = false;

  ChatRealtimeConnectionStatus get status => _status;
  ChatFailure? get lastError => _lastError;
  DateTime? get lastConnectedAt => _lastConnectedAt;
  String? get activeChannel => _activeChannel;

  Future<void> start({
    required String userId,
    required ChatRealtimeRowCallback onMessage,
    required VoidCallback onThreadInvalidated,
    required FutureOr<void> Function() onConnected,
  }) async {
    final generation = ++_generation;
    _clearActiveCallbacks();
    await _detachChannel();
    if (generation != _generation) return;
    final identity = userId.trim();
    if (identity.isEmpty) {
      _setStatus(ChatRealtimeConnectionStatus.disconnected);
      return;
    }
    _userId = identity;
    _onMessage = onMessage;
    _onThreadInvalidated = onThreadInvalidated;
    _onConnected = onConnected;
    _messageQueue = Future<void>.value();
    final channelName = 'chat:$identity';
    _activeChannel = channelName;
    _setStatus(ChatRealtimeConnectionStatus.connecting);

    final channel = _channelFactory(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_messages',
          callback: (event, row) {
            if (!_isCurrent(generation, identity)) return;
            _enqueueMessage(generation, identity, event, row);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_threads',
          callback: (_, _) {
            if (_isCurrent(generation, identity)) _onThreadInvalidated?.call();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_thread_member_state',
          callback: (_, _) {
            if (_isCurrent(generation, identity)) _onThreadInvalidated?.call();
          },
        );
    _channel = channel;
    channel.subscribe((status, error) {
      if (!_isCurrent(generation, identity)) return;
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          _retryTimer?.cancel();
          _retryTimer = null;
          _lastConnectedAt = DateTime.now().toUtc();
          _lastError = null;
          _setStatus(ChatRealtimeConnectionStatus.connected);
          unawaited(Future<void>.sync(() => _onConnected?.call()));
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
          _lastError = ChatFailure(
            code: ChatFailureCode.realtimeDisconnected,
            operation: 'realtime_subscribe',
            message: error?.toString() ?? status.name,
          );
          logChatFailure(_lastError!, userId: identity);
          _setStatus(ChatRealtimeConnectionStatus.error);
          _scheduleReconnect(generation, identity);
        case RealtimeSubscribeStatus.closed:
          _setStatus(ChatRealtimeConnectionStatus.disconnected);
          _scheduleReconnect(generation, identity);
      }
    });
  }

  Future<void> reconnect() async {
    final identity = _userId;
    final onMessage = _onMessage;
    final onInvalidated = _onThreadInvalidated;
    final onConnected = _onConnected;
    if (identity.isEmpty ||
        onMessage == null ||
        onInvalidated == null ||
        onConnected == null) {
      return;
    }
    await start(
      userId: identity,
      onMessage: onMessage,
      onThreadInvalidated: onInvalidated,
      onConnected: onConnected,
    );
  }

  Future<void> stop() async {
    final generation = ++_generation;
    _clearActiveCallbacks();
    await _detachChannel();
    if (generation != _generation) return;
    _setStatus(ChatRealtimeConnectionStatus.disconnected);
  }

  void _clearActiveCallbacks() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _userId = '';
    _onMessage = null;
    _onThreadInvalidated = null;
    _onConnected = null;
  }

  Future<void> _detachChannel() async {
    final channel = _channel;
    _channel = null;
    _activeChannel = null;
    if (channel != null) {
      try {
        await channel.remove();
      } catch (error, stackTrace) {
        logChatFailure(
          ChatFailure.from(
            error,
            stackTrace,
            operation: 'realtime_remove_channel',
          ),
          userId: _userId,
        );
      }
    }
  }

  void _enqueueMessage(
    int generation,
    String identity,
    PostgresChangeEvent event,
    Map<String, dynamic> row,
  ) {
    if (!_isCurrent(generation, identity)) return;
    final immutableRow = Map<String, dynamic>.unmodifiable(row);
    _messageQueue = _messageQueue.then((_) async {
      if (!_isCurrent(generation, identity)) return;
      try {
        await _onMessage?.call(event, immutableRow);
      } catch (error, stackTrace) {
        logChatFailure(
          ChatFailure.from(
            error,
            stackTrace,
            operation: 'realtime_message_callback',
            threadId: immutableRow['thread_id']?.toString() ?? '',
            clientMessageId:
                immutableRow['client_message_id']?.toString() ?? '',
          ),
          userId: identity,
        );
      }
    });
  }

  @visibleForTesting
  Future<void> get pendingMessageCallbacks => _messageQueue;

  bool _isCurrent(int generation, String userId) =>
      generation == _generation && userId == _userId;

  void _scheduleReconnect(int generation, String identity) {
    if (!_isCurrent(generation, identity) || _retryTimer?.isActive == true) {
      return;
    }
    _retryTimer = Timer(const Duration(seconds: 2), () {
      _retryTimer = null;
      if (_isCurrent(generation, identity)) unawaited(reconnect());
    });
  }

  void _setStatus(ChatRealtimeConnectionStatus value) {
    if (_status == value) return;
    _status = value;
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    unawaited(stop());
    super.dispose();
  }
}
