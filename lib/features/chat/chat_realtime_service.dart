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

class ChatRealtimeService extends ChangeNotifier {
  ChatRealtimeService(this._client);

  final SupabaseClient _client;
  RealtimeChannel? _channel;
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
    await stop();
    final identity = userId.trim();
    if (identity.isEmpty) return;
    _userId = identity;
    _onMessage = onMessage;
    _onThreadInvalidated = onThreadInvalidated;
    _onConnected = onConnected;
    final generation = ++_generation;
    final channelName = 'chat:$identity';
    _activeChannel = channelName;
    _setStatus(ChatRealtimeConnectionStatus.connecting);

    final channel = _client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_messages',
          callback: (payload) {
            if (!_isCurrent(generation, identity)) return;
            final row = payload.eventType == PostgresChangeEvent.delete
                ? payload.oldRecord
                : payload.newRecord;
            if (row.isNotEmpty) {
              unawaited(
                Future<void>.sync(
                  () => _onMessage?.call(payload.eventType, row),
                ),
              );
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_threads',
          callback: (_) {
            if (_isCurrent(generation, identity)) _onThreadInvalidated?.call();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_thread_member_state',
          callback: (_) {
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
    _generation++;
    _retryTimer?.cancel();
    _retryTimer = null;
    final channel = _channel;
    _channel = null;
    _activeChannel = null;
    if (channel != null) {
      try {
        await _client.removeChannel(channel);
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
    _setStatus(ChatRealtimeConnectionStatus.disconnected);
  }

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
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
