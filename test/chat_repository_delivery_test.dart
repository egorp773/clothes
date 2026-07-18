import 'dart:convert';
import 'dart:io';

import 'package:clothes/data/app_repository.dart';
import 'package:clothes/models/message_thread.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('repository keeps an empty direct thread visible', () async {
    final thread = _thread();
    final repository = await _repositoryWithThread(thread);
    addTearDown(repository.dispose);

    expect(repository.threads, hasLength(1));
    expect(repository.threads.single.id, thread.id);
  });

  test('client optimistic id is persisted once and duplicate-safe', () async {
    final thread = _thread();
    final repository = await _repositoryWithThread(thread);
    addTearDown(repository.dispose);
    final pending = ChatMessage(
      id: 'pending-client-1',
      text: 'Привет',
      createdAt: DateTime.utc(2026, 7, 18, 12),
      isMine: true,
      isPending: true,
    );

    expect(await repository.sendPendingChatText(thread.id, pending), isTrue);
    expect(
      repository.threadById(thread.id)!.messages.map((message) => message.id),
      ['pending-client-1'],
    );

    expect(await repository.sendPendingChatText(thread.id, pending), isFalse);
    expect(repository.threadById(thread.id)!.messages, hasLength(1));
  });

  test(
    'retry reuses the failed message id instead of appending a copy',
    () async {
      final failed = ChatMessage(
        id: 'pending-client-failed',
        text: 'Повторить',
        createdAt: DateTime.utc(2026, 7, 18, 12),
        isMine: true,
        hasError: true,
      );
      final thread = _thread(messages: [failed]);
      final repository = await _repositoryWithThread(thread);
      addTearDown(repository.dispose);

      expect(await repository.retryChatText(thread.id, failed), isTrue);
      final messages = repository.threadById(thread.id)!.messages;
      expect(messages, hasLength(1));
      expect(messages.single.id, failed.id);
      expect(messages.single.hasError, isFalse);
    },
  );

  test('media retry reuses the failed id and local attachment', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'clothes-chat-media-retry-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final file = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}retry.png',
    );
    await file.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    final failed = ChatMessage(
      id: 'pending-media-failed',
      text: '',
      createdAt: DateTime.utc(2026, 7, 18, 12),
      isMine: true,
      type: 'image',
      attachment: ChatAttachment(
        url: file.path,
        name: 'retry.png',
        mimeType: 'image/png',
      ),
      hasError: true,
    );
    final thread = _thread(messages: [failed]);
    final repository = await _repositoryWithThread(thread);
    addTearDown(repository.dispose);

    expect(await repository.retryChatMedia(thread.id, failed), isTrue);
    final messages = repository.threadById(thread.id)!.messages;
    expect(messages, hasLength(1));
    expect(messages.single.id, failed.id);
    expect(messages.single.hasError, isFalse);
    expect(messages.single.attachment?.url, startsWith('data:image/'));
  });

  test('legacy sendMessage forwards its delivery result', () async {
    final thread = _thread();
    final repository = await _repositoryWithThread(thread);
    addTearDown(repository.dispose);

    final Future<bool> delivery = repository.sendMessage(thread.id, 'Текст');
    expect(await delivery, isTrue);
    expect(repository.threadById(thread.id)!.messages, hasLength(1));
  });

  test(
    'sync merge preserves unsent messages without duplicating remote ids',
    () {
      final failed = ChatMessage(
        id: 'pending-failed',
        text: 'Не потеряй меня',
        createdAt: DateTime.utc(2026, 7, 18, 12),
        isMine: true,
        hasError: true,
      );
      final local = _thread(messages: [failed]);

      final mergedIntoRemote = AppRepository.mergeChatOutgoingState(
        [_thread()],
        {local.id: local},
      );
      expect(mergedIntoRemote.single.messages.single.id, failed.id);

      final missingRemoteThread = AppRepository.mergeChatOutgoingState(
        const [],
        {local.id: local},
      );
      expect(missingRemoteThread.single.id, local.id);
      expect(missingRemoteThread.single.messages.single.id, failed.id);

      final delivered = failed.copyWith(isPending: false, hasError: false);
      final remoteWithSameId = _thread(messages: [delivered]);
      final remoteWins = AppRepository.mergeChatOutgoingState(
        [remoteWithSameId],
        {local.id: local},
      );
      expect(remoteWins.single.messages, hasLength(1));
      expect(remoteWins.single.messages.single.hasError, isFalse);
    },
  );
}

Future<AppRepository> _repositoryWithThread(MessageThread thread) async {
  SharedPreferences.setMockInitialValues({
    'user_storage_scoped_v1': true,
    AppRepository.userScopedStorageKey('threads_v2', ''): jsonEncode([
      thread.toJson(),
    ]),
  });
  final repository = AppRepository();
  await repository.load();
  return repository;
}

MessageThread _thread({List<ChatMessage> messages = const []}) => MessageThread(
  id: 'direct-guest-user',
  sellerName: 'User',
  buyerName: 'Guest',
  productTitle: '',
  lastMessage: messages.isEmpty ? '' : messages.last.previewText,
  updatedAt: DateTime.utc(2026, 7, 18),
  sellerId: 'user',
  members: const [
    ConversationMember(id: 'user', name: 'User', handle: '@user'),
  ],
  messages: messages,
);
