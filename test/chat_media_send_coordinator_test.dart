import 'package:clothes/features/chat/chat_media_send_coordinator.dart';
import 'package:clothes/models/message_thread.dart';
import 'package:flutter_test/flutter_test.dart';

const _attachment = ChatAttachment(
  url: 'https://signed.example/media',
  bucket: 'chat-media',
  storagePath: 'threads/thread/user/file.jpg',
);

void main() {
  test(
    'persists media only after remote thread preflight and upload',
    () async {
      final calls = <String>[];
      const coordinator = ChatMediaSendCoordinator();

      final sent = await coordinator.send(
        ensureRemoteThread: () async {
          calls.add('preflight');
          return true;
        },
        upload: () async {
          calls.add('upload');
          return _attachment;
        },
        persist: (attachment) async {
          calls.add('persist');
          expect(attachment, same(_attachment));
          return true;
        },
        markFailed: (_) async => calls.add('mark-failed'),
        cleanup: (_) async => calls.add('cleanup'),
      );

      expect(sent, isTrue);
      expect(calls, ['preflight', 'upload', 'persist']);
    },
  );

  test('does not upload when remote thread preflight fails', () async {
    final calls = <String>[];
    const coordinator = ChatMediaSendCoordinator();

    final sent = await coordinator.send(
      ensureRemoteThread: () async {
        calls.add('preflight');
        return false;
      },
      upload: () async {
        calls.add('upload');
        return _attachment;
      },
      persist: (_) async {
        calls.add('persist');
        return true;
      },
      markFailed: (_) async => calls.add('mark-failed'),
      cleanup: (_) async => calls.add('cleanup'),
    );

    expect(sent, isFalse);
    expect(calls, ['preflight']);
  });

  test(
    'marks failed and cleans upload after message persistence fails',
    () async {
      final calls = <String>[];
      const coordinator = ChatMediaSendCoordinator();

      final sent = await coordinator.send(
        ensureRemoteThread: () async {
          calls.add('preflight');
          return true;
        },
        upload: () async {
          calls.add('upload');
          return _attachment;
        },
        persist: (_) async {
          calls.add('persist');
          return false;
        },
        markFailed: (_) async => calls.add('mark-failed'),
        cleanup: (_) async => calls.add('cleanup'),
      );

      expect(sent, isFalse);
      expect(calls, [
        'preflight',
        'upload',
        'persist',
        'mark-failed',
        'cleanup',
      ]);
    },
  );

  test('cleanup still runs when marking the local failure throws', () async {
    final calls = <String>[];
    const coordinator = ChatMediaSendCoordinator();

    final sent = await coordinator.send(
      ensureRemoteThread: () async => true,
      upload: () async => _attachment,
      persist: (_) async => throw StateError('insert failed'),
      markFailed: (_) async {
        calls.add('mark-failed');
        throw StateError('local cache unavailable');
      },
      cleanup: (_) async => calls.add('cleanup'),
    );

    expect(sent, isFalse);
    expect(calls, ['mark-failed', 'cleanup']);
  });

  test('cleans an upload that cannot produce a usable URL', () async {
    final calls = <String>[];
    const coordinator = ChatMediaSendCoordinator();
    const unusable = ChatAttachment(
      url: '',
      bucket: 'chat-media',
      storagePath: 'threads/thread/user/file.jpg',
    );

    final sent = await coordinator.send(
      ensureRemoteThread: () async => true,
      upload: () async => unusable,
      persist: (_) async {
        calls.add('persist');
        return true;
      },
      markFailed: (_) async => calls.add('mark-failed'),
      cleanup: (attachment) async {
        calls.add('cleanup');
        expect(attachment, same(unusable));
      },
    );

    expect(sent, isFalse);
    expect(calls, ['cleanup']);
  });

  test('failed local attachment cannot masquerade as a remote object', () {
    const coordinator = ChatMediaSendCoordinator();

    final failed = coordinator.localFailureAttachment(
      _attachment,
      localUrl: ' C:/picker/photo.jpg ',
    );

    expect(failed.url, 'C:/picker/photo.jpg');
    expect(failed.hasRemoteObject, isFalse);
    expect(failed.bucket, isEmpty);
    expect(failed.storagePath, isEmpty);
  });
}
