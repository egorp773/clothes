import 'dart:async';

import 'package:clothes/features/chat/chat_media_url_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reuses a signed URL until the refresh margin', () async {
    var now = DateTime.utc(2026, 7, 17, 12);
    var loads = 0;
    final cache = ChatMediaUrlCache(
      timeToLive: const Duration(hours: 1),
      refreshMargin: const Duration(minutes: 5),
      now: () => now,
    );

    Future<String> load() async => 'signed-${++loads}';

    expect(await cache.resolve(key: 'bucket/path', load: load), 'signed-1');
    now = now.add(const Duration(minutes: 54));
    expect(await cache.resolve(key: 'bucket/path', load: load), 'signed-1');
    now = now.add(const Duration(minutes: 2));
    expect(await cache.resolve(key: 'bucket/path', load: load), 'signed-2');
    expect(loads, 2);
  });

  test('coalesces concurrent requests for the same storage object', () async {
    final cache = ChatMediaUrlCache(timeToLive: const Duration(hours: 1));
    final release = Completer<String>();
    var loads = 0;

    Future<String> load() {
      loads++;
      return release.future;
    }

    final first = cache.resolve(key: 'bucket/path', load: load);
    final second = cache.resolve(key: 'bucket/path', load: load);
    expect(loads, 1);
    release.complete('signed-url');

    expect(await Future.wait([first, second]), ['signed-url', 'signed-url']);
    expect(loads, 1);
  });

  test('does not cache empty or failed URL loads', () async {
    final cache = ChatMediaUrlCache(timeToLive: const Duration(hours: 1));
    var loads = 0;

    expect(
      await cache.resolve(
        key: 'bucket/path',
        load: () async {
          loads++;
          return '';
        },
      ),
      isNull,
    );
    await expectLater(
      cache.resolve(
        key: 'bucket/path',
        load: () async {
          loads++;
          throw StateError('offline');
        },
      ),
      throwsStateError,
    );
    expect(
      await cache.resolve(
        key: 'bucket/path',
        load: () async {
          loads++;
          return 'recovered';
        },
      ),
      'recovered',
    );
    expect(loads, 3);
  });
}
