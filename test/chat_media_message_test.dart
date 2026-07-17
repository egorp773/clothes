import 'package:clothes/models/message_thread.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('private video attachment round-trips locally', () {
    const attachment = ChatAttachment(
      url: 'https://signed.example/video.mp4?token=temporary',
      name: 'look.mp4',
      mimeType: 'video/mp4',
      size: 42,
      durationMs: 3200,
      bucket: 'chat-media',
      storagePath: 'threads/thread-1/user-1/object.mp4',
    );

    final parsed = ChatAttachment.fromJson(attachment.toJson());

    expect(parsed.isVideo, isTrue);
    expect(parsed.isImage, isFalse);
    expect(parsed.hasRemoteObject, isTrue);
    expect(parsed.storagePath, attachment.storagePath);
    expect(parsed.durationMs, 3200);
  });

  test('database payload stores private path but never a signed URL', () {
    final message = ChatMessage(
      id: 'message-1',
      text: '',
      createdAt: DateTime.utc(2026, 7, 17),
      isMine: true,
      senderId: '00000000-0000-4000-8000-000000000001',
      type: 'video',
      attachment: const ChatAttachment(
        url: 'https://signed.example/video.mp4?token=temporary',
        name: 'look.mp4',
        mimeType: 'video/mp4',
        size: 42,
        bucket: 'chat-media',
        storagePath: 'threads/thread-1/user-1/object.mp4',
      ),
    );

    final payload = message.toSupabaseJson();
    final attachment = payload['attachment'] as Map<String, dynamic>;

    expect(message.isVideo, isTrue);
    expect(message.previewText, 'Видео');
    expect(attachment['bucket'], 'chat-media');
    expect(attachment['storage_path'], contains('object.mp4'));
    expect(attachment, isNot(contains('url')));
    // Server triggers own delivery state and reactions. A sender must not be
    // able to forge either field during insert.
    expect(payload, isNot(contains('read_by')));
    expect(payload, isNot(contains('reactions')));
  });

  test('image and video messages expose a shared media contract', () {
    final image = ChatMessage(
      id: 'image-1',
      text: 'Фото вещи',
      createdAt: DateTime.utc(2026, 7, 17),
      isMine: false,
      type: 'image',
      attachment: const ChatAttachment(
        url: 'https://example.com/image.webp',
        mimeType: 'image/webp',
      ),
    );
    final video = ChatMessage(
      id: 'video-1',
      text: '',
      createdAt: DateTime.utc(2026, 7, 17),
      isMine: false,
      type: 'video',
      attachment: const ChatAttachment(
        url: 'https://example.com/video.mov',
        mimeType: 'video/quicktime',
      ),
    );

    expect(image.isMedia, isTrue);
    expect(image.previewText, 'Фото вещи');
    expect(video.isMedia, isTrue);
    expect(video.previewText, 'Видео');
  });
}
