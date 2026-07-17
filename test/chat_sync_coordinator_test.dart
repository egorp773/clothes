import 'dart:async';

import 'package:clothes/features/chat/chat_sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coalesces a burst of idle realtime events', () async {
    final coordinator = ChatSyncCoordinator(
      debounce: const Duration(milliseconds: 5),
    );
    addTearDown(coordinator.dispose);
    var calls = 0;

    Future<void> synchronize() async {
      calls++;
    }

    for (var index = 0; index < 30; index++) {
      coordinator.schedule(synchronize);
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(calls, 1);
  });

  test('serializes requests and keeps one trailing synchronization', () async {
    final coordinator = ChatSyncCoordinator(
      debounce: const Duration(milliseconds: 5),
    );
    addTearDown(coordinator.dispose);
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    var calls = 0;
    var active = 0;
    var maxActive = 0;

    Future<void> synchronize() async {
      calls++;
      active++;
      if (active > maxActive) maxActive = active;
      if (calls == 1) {
        firstStarted.complete();
        await releaseFirst.future;
      }
      active--;
    }

    final firstRun = coordinator.runNow(synchronize);
    await firstStarted.future;
    for (var index = 0; index < 30; index++) {
      coordinator.schedule(synchronize);
    }
    releaseFirst.complete();
    await firstRun;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(maxActive, 1);
    expect(calls, 2);
  });
}
