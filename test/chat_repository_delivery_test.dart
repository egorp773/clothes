import 'dart:convert';

import 'package:clothes/data/app_repository.dart';
import 'package:clothes/models/message_thread.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('delivered chat history is not restored from preferences', () async {
    final thread = _thread();
    final repository = await _repositoryWithThread(thread);
    addTearDown(repository.dispose);

    expect(repository.threads, isEmpty);
  });

  test('server row replaces the matching optimistic client message', () {
    final pending = ChatMessage(
      id: 'local-pending-1',
      text: 'pending text',
      createdAt: DateTime.utc(2026, 7, 18, 12),
      isMine: true,
      senderId: 'me',
      isPending: true,
      clientMessageId: 'client-message-1',
    );
    final delivered = ChatMessage(
      id: 'server-message-1',
      text: 'pending text',
      createdAt: DateTime.utc(2026, 7, 18, 12, 0, 1),
      isMine: true,
      senderId: 'me',
      clientMessageId: 'client-message-1',
    );
    final messages = AppRepository.mergeChatMessages([delivered], [pending]);
    expect(messages, hasLength(1));
    expect(messages.single.id, 'server-message-1');
    expect(messages.single.clientMessageId, 'client-message-1');
    expect(messages.single.isPending, isFalse);
  });

  test('client message deduplication is scoped to the sender', () {
    final fromAlice = ChatMessage(
      id: 'server-alice-1',
      text: 'Alice',
      createdAt: DateTime.utc(2026, 7, 18, 12),
      isMine: false,
      senderId: 'alice',
      clientMessageId: 'shared-client-id',
    );
    final fromBob = ChatMessage(
      id: 'server-bob-1',
      text: 'Bob',
      createdAt: DateTime.utc(2026, 7, 18, 12, 0, 1),
      isMine: false,
      senderId: 'bob',
      clientMessageId: 'shared-client-id',
    );

    expect(AppRepository.sameChatMessageIdentity(fromAlice, fromBob), isFalse);
    final messages = AppRepository.mergeChatMessages([
      fromAlice,
      fromBob,
    ], const []);

    expect(messages.map((message) => message.id), [
      'server-alice-1',
      'server-bob-1',
    ]);
  });

  test('stale server response cannot regress receipts or edited content', () {
    final edited = ChatMessage(
      id: 'server-message-2',
      text: 'edited text',
      createdAt: DateTime.utc(2026, 7, 18, 12),
      isMine: true,
      senderId: 'me',
      clientMessageId: 'client-message-2',
      editedAt: DateTime.utc(2026, 7, 18, 12, 1),
      readBy: const ['recipient'],
      deliveredTo: const ['recipient'],
    );
    final staleRpcResponse = ChatMessage(
      id: 'server-message-2',
      text: 'original text',
      createdAt: DateTime.utc(2026, 7, 18, 12),
      isMine: true,
      senderId: 'me',
      clientMessageId: 'client-message-2',
    );

    final messages = AppRepository.mergeChatMessages(
      [staleRpcResponse],
      [edited],
    );

    expect(messages, hasLength(1));
    expect(messages.single.text, 'edited text');
    expect(messages.single.editedAt, edited.editedAt);
    expect(messages.single.readBy, ['recipient']);
    expect(messages.single.deliveredTo, ['recipient']);
    expect(
      messages.single.effectiveStatus,
      ChatMessageDeliveryStatus.delivered,
    );
  });

  test('retry identity replaces failed state instead of appending a copy', () {
    final failed = ChatMessage(
      id: 'pending-client-failed',
      text: 'Повторить',
      createdAt: DateTime.utc(2026, 7, 18, 12),
      isMine: true,
      hasError: true,
      clientMessageId: 'pending-client-failed',
    );
    final retrying = failed.copyWith(isPending: true, hasError: false);
    final messages = AppRepository.mergeChatMessages(
      const [],
      [failed],
      outbox: [retrying],
    );
    expect(messages, hasLength(1));
    expect(messages.single.id, failed.id);
    expect(messages.single.hasError, isFalse);
  });

  test('media outbox keeps its local retry identity', () {
    final failed = ChatMessage(
      id: 'pending-media-failed',
      text: '',
      createdAt: DateTime.utc(2026, 7, 18, 12),
      isMine: true,
      type: 'image',
      attachment: const ChatAttachment(
        url: 'C:/temporary/retry.png',
        name: 'retry.png',
        mimeType: 'image/png',
      ),
      hasError: true,
      clientMessageId: 'pending-media-failed',
    );
    final retrying = failed.copyWith(isPending: true, hasError: false);
    final messages = AppRepository.mergeChatMessages(
      const [],
      [failed],
      outbox: [retrying],
    );
    expect(messages, hasLength(1));
    expect(messages.single.id, failed.id);
    expect(messages.single.hasError, isFalse);
    expect(messages.single.attachment?.url, 'C:/temporary/retry.png');
  });

  test('legacy sendMessage forwards its delivery result', () async {
    final thread = _thread();
    final repository = await _repositoryWithThread(thread);
    addTearDown(repository.dispose);

    final Future<bool> delivery = repository.sendMessage(thread.id, 'Текст');
    expect(await delivery, isFalse);
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

  test('stale sync response cannot erase a just-delivered message', () {
    final delivered = ChatMessage(
      id: 'client-delivered-during-sync',
      text: 'Уже доставлено',
      createdAt: DateTime.utc(2026, 7, 18, 12, 1),
      isMine: true,
      senderId: 'guest',
    );
    final liveLocal = _thread(messages: [delivered]);

    final merged = AppRepository.mergeChatOutgoingState(
      [_thread()],
      {liveLocal.id: liveLocal},
    );

    expect(merged.single.messages, hasLength(1));
    expect(merged.single.messages.single.id, delivered.id);
    expect(merged.single.messages.single.isPending, isFalse);
    expect(merged.single.messages.single.hasError, isFalse);
  });

  test('a newer local delivery state replaces an earlier pending merge', () {
    final pending = ChatMessage(
      id: 'same-client-id',
      text: 'Сообщение',
      createdAt: DateTime.utc(2026, 7, 18, 12, 2),
      isMine: true,
      senderId: 'guest',
      isPending: true,
    );
    final delivered = pending.copyWith(isPending: false);

    final merged = AppRepository.mergeChatOutgoingState(
      [
        _thread(messages: [pending]),
      ],
      {
        _thread().id: _thread(messages: [delivered]),
      },
    );

    expect(merged.single.messages, hasLength(1));
    expect(merged.single.messages.single.id, pending.id);
    expect(merged.single.messages.single.isPending, isFalse);
  });

  test('only terminal auth refresh failures require local sign-out', () {
    expect(
      AppRepository.isTerminalAuthRefreshError(AuthSessionMissingException()),
      isTrue,
    );
    expect(
      AppRepository.isTerminalAuthRefreshError(
        AuthApiException(
          'refresh token rejected',
          statusCode: '401',
          code: 'refresh_token_not_found',
        ),
      ),
      isTrue,
    );
    expect(
      AppRepository.isTerminalAuthRefreshError(
        AuthRetryableFetchException(message: 'network unavailable'),
      ),
      isFalse,
    );
  });
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
