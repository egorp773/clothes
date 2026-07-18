import 'package:clothes/features/chat/chat_remote_write_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const coordinator = ChatRemoteWriteCoordinator();

  test('existing conversation appends without rewriting thread row', () async {
    final calls = <String>[];

    final result = await coordinator.persist(
      hasMessages: true,
      threadKnownRemote: true,
      ensureThreadFirst: false,
      ensureThread: () async => calls.add('thread'),
      persistMessages: () async => calls.add('message'),
    );

    expect(result.succeeded, isTrue);
    expect(result.threadConfirmed, isTrue);
    expect(calls, ['message']);
  });

  test('new conversation is created before its first message', () async {
    final calls = <String>[];

    final result = await coordinator.persist(
      hasMessages: true,
      threadKnownRemote: false,
      ensureThreadFirst: true,
      ensureThread: () async => calls.add('thread'),
      persistMessages: () async => calls.add('message'),
    );

    expect(result.succeeded, isTrue);
    expect(result.threadConfirmed, isTrue);
    expect(calls, ['thread', 'message']);
  });

  test(
    'cache-only conversation inserts directly when server row exists',
    () async {
      final calls = <String>[];

      final result = await coordinator.persist(
        hasMessages: true,
        threadKnownRemote: false,
        ensureThreadFirst: false,
        ensureThread: () async => calls.add('thread'),
        persistMessages: () async => calls.add('message'),
      );

      expect(result.succeeded, isTrue);
      expect(calls, ['message']);
    },
  );

  test(
    'cache-only missing conversation is repaired and retried once',
    () async {
      final calls = <String>[];
      var attempts = 0;

      final result = await coordinator.persist(
        hasMessages: true,
        threadKnownRemote: false,
        ensureThreadFirst: false,
        ensureThread: () async => calls.add('thread'),
        persistMessages: () async {
          calls.add('message');
          if (attempts++ == 0) throw StateError('missing thread');
        },
      );

      expect(result.succeeded, isTrue);
      expect(result.threadConfirmed, isTrue);
      expect(calls, ['message', 'thread', 'message']);
    },
  );

  test(
    'known conversation failure is not hidden by a thread rewrite',
    () async {
      final calls = <String>[];

      final result = await coordinator.persist(
        hasMessages: true,
        threadKnownRemote: true,
        ensureThreadFirst: false,
        ensureThread: () async => calls.add('thread'),
        persistMessages: () async {
          calls.add('message');
          throw StateError('RLS rejected message');
        },
      );

      expect(result.succeeded, isFalse);
      expect(result.threadConfirmed, isTrue);
      expect(result.failure?.stage, ChatRemoteWriteStage.persistMessages);
      expect(calls, ['message']);
    },
  );

  test('thread creation failure prevents orphan message attempt', () async {
    final calls = <String>[];

    final result = await coordinator.persist(
      hasMessages: true,
      threadKnownRemote: false,
      ensureThreadFirst: true,
      ensureThread: () async {
        calls.add('thread');
        throw StateError('thread rejected');
      },
      persistMessages: () async => calls.add('message'),
    );

    expect(result.succeeded, isFalse);
    expect(result.threadConfirmed, isFalse);
    expect(result.failure?.stage, ChatRemoteWriteStage.ensureThread);
    expect(calls, ['thread']);
  });
}
