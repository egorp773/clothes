import 'dart:async';

import 'package:clothes/features/chat/chat_realtime_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('message callbacks are processed in WAL arrival order', () async {
    final channels = <_FakeRealtimeChannel>[];
    final service = ChatRealtimeService.testing(
      channelFactory: (name) {
        final channel = _FakeRealtimeChannel(name);
        channels.add(channel);
        return channel;
      },
    );
    addTearDown(() async {
      await service.stop();
      service.dispose();
    });

    final firstCallbackGate = Completer<void>();
    final calls = <String>[];
    await service.start(
      userId: 'user-a',
      onMessage: (_, row) async {
        final id = row['id'] as String;
        calls.add('start:$id');
        if (id == 'message-1') await firstCallbackGate.future;
        calls.add('end:$id');
      },
      onThreadInvalidated: () {},
      onConnected: () {},
    );

    channels.single.emitMessage({'id': 'message-1'});
    channels.single.emitMessage({'id': 'message-2'});
    await Future<void>.delayed(Duration.zero);

    expect(calls, ['start:message-1']);

    firstCallbackGate.complete();
    await service.pendingMessageCallbacks;

    expect(calls, [
      'start:message-1',
      'end:message-1',
      'start:message-2',
      'end:message-2',
    ]);
  });

  test('a callback error does not break the message queue', () async {
    final channel = _FakeRealtimeChannel('chat:user-a');
    final service = ChatRealtimeService.testing(channelFactory: (_) => channel);
    addTearDown(() async {
      await service.stop();
      service.dispose();
    });

    final calls = <String>[];
    await service.start(
      userId: 'user-a',
      onMessage: (_, row) {
        final id = row['id'] as String;
        calls.add(id);
        if (id == 'message-1') throw StateError('callback failed');
      },
      onThreadInvalidated: () {},
      onConnected: () {},
    );

    channel.emitMessage({'id': 'message-1'});
    channel.emitMessage({'id': 'message-2'});
    await service.pendingMessageCallbacks;

    expect(calls, ['message-1', 'message-2']);
  });

  test('stop drops callbacks queued by a stale generation', () async {
    final channel = _FakeRealtimeChannel('chat:user-a');
    final service = ChatRealtimeService.testing(channelFactory: (_) => channel);
    addTearDown(service.dispose);

    final firstCallbackGate = Completer<void>();
    final calls = <String>[];
    await service.start(
      userId: 'user-a',
      onMessage: (_, row) async {
        final id = row['id'] as String;
        calls.add('start:$id');
        if (id == 'message-1') await firstCallbackGate.future;
        calls.add('end:$id');
      },
      onThreadInvalidated: () {},
      onConnected: () {},
    );

    channel.emitMessage({'id': 'message-1'});
    channel.emitMessage({'id': 'message-2'});
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['start:message-1']);

    await service.stop();
    channel.emitMessage({'id': 'message-3'});
    firstCallbackGate.complete();
    await service.pendingMessageCallbacks;

    expect(calls, ['start:message-1', 'end:message-1']);
  });

  test(
    'a superseded start cannot install its channel after stop awaits',
    () async {
      final channels = <_FakeRealtimeChannel>[];
      final service = ChatRealtimeService.testing(
        channelFactory: (name) {
          final channel = _FakeRealtimeChannel(name);
          channels.add(channel);
          return channel;
        },
      );
      addTearDown(() async {
        await service.stop();
        service.dispose();
      });

      await service.start(
        userId: 'initial-user',
        onMessage: (_, _) {},
        onThreadInvalidated: () {},
        onConnected: () {},
      );
      final removalGate = Completer<void>();
      channels.single.removalGate = removalGate;

      final staleStart = service.start(
        userId: 'stale-user',
        onMessage: (_, _) {},
        onThreadInvalidated: () {},
        onConnected: () {},
      );
      await Future<void>.delayed(Duration.zero);
      expect(channels.single.removeCalls, 1);

      await service.start(
        userId: 'current-user',
        onMessage: (_, _) {},
        onThreadInvalidated: () {},
        onConnected: () {},
      );
      expect(service.activeChannel, 'chat:current-user');
      expect(channels.map((channel) => channel.name), [
        'chat:initial-user',
        'chat:current-user',
      ]);

      removalGate.complete();
      await staleStart;

      expect(service.activeChannel, 'chat:current-user');
      expect(channels.map((channel) => channel.name), [
        'chat:initial-user',
        'chat:current-user',
      ]);
    },
  );
}

class _FakeRealtimeChannel implements ChatRealtimeChannelAdapter {
  _FakeRealtimeChannel(this.name);

  final String name;
  final Map<String, ChatRealtimeRowCallback> _callbacks = {};
  Completer<void>? removalGate;
  int removeCalls = 0;

  @override
  ChatRealtimeChannelAdapter onPostgresChanges({
    required PostgresChangeEvent event,
    required String schema,
    required String table,
    required ChatRealtimeRowCallback callback,
  }) {
    _callbacks[table] = callback;
    return this;
  }

  @override
  void subscribe(ChatRealtimeSubscriptionCallback callback) {}

  @override
  Future<void> remove() async {
    removeCalls++;
    final gate = removalGate;
    if (gate != null) await gate.future;
  }

  void emitMessage(Map<String, dynamic> row) {
    _callbacks['chat_messages']?.call(PostgresChangeEvent.insert, row);
  }
}
