import 'dart:async';

import 'package:clothes/features/chat/chat_actions.dart';
import 'package:clothes/models/message_thread.dart';
import 'package:clothes/screens/messages_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('failed server delivery is visible and restores the draft', (
    tester,
  ) async {
    final listenable = ValueNotifier<int>(0);
    addTearDown(listenable.dispose);
    final thread = MessageThread(
      id: 'direct-me-user',
      sellerName: 'User',
      buyerName: 'Me',
      productTitle: '',
      lastMessage: '',
      updatedAt: DateTime.utc(2026, 7, 17),
      buyerId: 'me',
      sellerId: 'user',
      members: const [
        ConversationMember(id: 'me', name: 'Me', handle: '@me'),
        ConversationMember(id: 'user', name: 'User', handle: '@user'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          thread: thread,
          onSendMessage: (_, _) async {},
          currentUserId: 'me',
          threadsListenable: listenable,
          resolveThread: (_) => thread,
          lastSeenForUser: (_) => null,
          actions: ChatActions(sendText: (_, _) async => false),
        ),
      ),
    );

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, 'Проверка доставки');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(
      find.text('Сообщение не доставлено. Проверьте подключение.'),
      findsOneWidget,
    );
    final field = tester.widget<TextField>(composer);
    expect(field.controller?.text, 'Проверка доставки');
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
  });

  testWidgets(
    'composer enables send only for valid text and invokes callback',
    (tester) async {
      final listenable = ValueNotifier<int>(0);
      addTearDown(listenable.dispose);
      final thread = _threadWithMessages(const []);
      final sentTexts = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            thread: thread,
            onSendMessage: (_, _) async {},
            currentUserId: 'me',
            threadsListenable: listenable,
            resolveThread: (_) => thread,
            lastSeenForUser: (_) => null,
            actions: ChatActions(
              sendText: (threadId, text) async {
                expect(threadId, thread.id);
                sentTexts.add(text);
                return true;
              },
            ),
          ),
        ),
      );

      final sendButton = find.byKey(const Key('message-send-button'));
      final composer = find.byKey(const Key('message-composer-field'));
      expect(tester.widget<TextField>(composer).decoration?.filled, isFalse);
      expect(tester.widget<GestureDetector>(sendButton).onTap, isNull);

      await tester.enterText(composer, '   ');
      await tester.pump();
      expect(tester.widget<GestureDetector>(sendButton).onTap, isNull);

      await tester.enterText(composer, 'Две\nстроки');
      await tester.pump();
      expect(tester.widget<GestureDetector>(sendButton).onTap, isNotNull);
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      expect(sentTexts, ['Две\nстроки']);
      expect(
        tester.widget<TextField>(composer).textInputAction,
        TextInputAction.newline,
      );
    },
  );

  testWidgets('optimistic text is visible while server send is pending', (
    tester,
  ) async {
    final listenable = ValueNotifier<int>(0);
    addTearDown(listenable.dispose);
    final thread = _threadWithMessages(const []);
    final delivery = Completer<bool>();

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          thread: thread,
          onSendMessage: (_, _) async {},
          currentUserId: 'me',
          threadsListenable: listenable,
          resolveThread: (_) => thread,
          lastSeenForUser: (_) => null,
          actions: ChatActions(sendText: (_, _) => delivery.future),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('message-composer-field')),
      'Сообщение в пути',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('message-send-button')));
    await tester.pump();

    expect(find.text('Сообщение в пути'), findsOneWidget);
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);

    delivery.complete(true);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.schedule_rounded), findsNothing);
    expect(find.byIcon(Icons.done_rounded), findsOneWidget);
  });

  testWidgets('a late failure does not overwrite the next composer draft', (
    tester,
  ) async {
    final listenable = ValueNotifier<int>(0);
    addTearDown(listenable.dispose);
    final thread = _threadWithMessages(const []);
    final delivery = Completer<bool>();

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          thread: thread,
          onSendMessage: (_, _) async {},
          currentUserId: 'me',
          threadsListenable: listenable,
          resolveThread: (_) => thread,
          lastSeenForUser: (_) => null,
          actions: ChatActions(
            sendPendingText: (_, _) => delivery.future,
            retryText: (_, _) async => true,
          ),
        ),
      ),
    );

    final composer = find.byKey(const Key('message-composer-field'));
    await tester.enterText(composer, 'Первое сообщение');
    await tester.pump();
    await tester.tap(find.byKey(const Key('message-send-button')));
    await tester.pump();
    await tester.enterText(composer, 'Новый черновик');
    await tester.pump();

    delivery.complete(false);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(composer).controller?.text,
      'Новый черновик',
    );
    expect(find.text('Повторить'), findsOneWidget);
  });

  testWidgets('keyboard focus stays active during a pending text send', (
    tester,
  ) async {
    final listenable = ValueNotifier<int>(0);
    addTearDown(listenable.dispose);
    final thread = _threadWithMessages(const []);
    final delivery = Completer<bool>();

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          thread: thread,
          onSendMessage: (_, _) async {},
          currentUserId: 'me',
          threadsListenable: listenable,
          resolveThread: (_) => thread,
          lastSeenForUser: (_) => null,
          actions: ChatActions(sendPendingText: (_, _) => delivery.future),
        ),
      ),
    );

    final composer = find.byKey(const Key('message-composer-field'));
    await tester.showKeyboard(composer);
    await tester.enterText(composer, 'Не закрывай клавиатуру');
    await tester.pump();
    await tester.tap(find.byKey(const Key('message-send-button')));
    await tester.pump();

    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.widget<TextField>(composer).enabled, isTrue);

    delivery.complete(true);
    await tester.pumpAndSettle();
  });

  testWidgets('composer stays above the keyboard on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final listenable = ValueNotifier<int>(0);
    addTearDown(listenable.dispose);
    final thread = _threadWithMessages(const []);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          thread: thread,
          onSendMessage: (_, _) async {},
          currentUserId: 'me',
          threadsListenable: listenable,
          resolveThread: (_) => thread,
          lastSeenForUser: (_) => null,
        ),
      ),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    final composer = find.byKey(const Key('message-composer-field'));
    expect(composer, findsOneWidget);
    expect(tester.getBottomLeft(composer).dy, lessThanOrEqualTo(288));
  });

  testWidgets(
    'repository listener keeps a client-id optimistic message singular',
    (tester) async {
      final listenable = ValueNotifier<int>(0);
      addTearDown(listenable.dispose);
      var thread = _threadWithMessages(const []);
      final delivery = Completer<bool>();
      String? clientMessageId;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            thread: thread,
            onSendMessage: (_, _) async {},
            currentUserId: 'me',
            threadsListenable: listenable,
            resolveThread: (_) => thread,
            lastSeenForUser: (_) => null,
            actions: ChatActions(
              sendPendingText: (threadId, pendingMessage) {
                expect(threadId, thread.id);
                clientMessageId = pendingMessage.id;
                thread = thread.copyWith(
                  lastMessage: pendingMessage.previewText,
                  updatedAt: pendingMessage.createdAt,
                  messages: [pendingMessage],
                );
                listenable.value++;
                return delivery.future;
              },
            ),
          ),
        ),
      );

      final composer = find.byKey(const Key('message-composer-field'));
      await tester.enterText(composer, 'Один экземпляр');
      await tester.pump();
      await tester.tap(find.byKey(const Key('message-send-button')));
      await tester.pump();

      expect(clientMessageId, startsWith('pending-'));
      expect(find.text('Один экземпляр'), findsOneWidget);

      final delivered = thread.messages.single.copyWith(isPending: false);
      thread = thread.copyWith(messages: [delivered]);
      listenable.value++;
      await tester.pump();
      expect(find.text('Один экземпляр'), findsOneWidget);

      delivery.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Один экземпляр'), findsOneWidget);
      expect(find.byIcon(Icons.done_rounded), findsOneWidget);
    },
  );

  testWidgets('reply uses the same pending-aware client id path', (
    tester,
  ) async {
    final listenable = ValueNotifier<int>(0);
    addTearDown(listenable.dispose);
    final source = ChatMessage(
      id: 'incoming-1',
      text: 'Исходное сообщение',
      createdAt: DateTime.utc(2026, 7, 18, 11),
      isMine: false,
      senderId: 'user',
      senderName: 'User',
    );
    final thread = _threadWithMessages([source]);
    ChatMessage? submitted;

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          thread: thread,
          onSendMessage: (_, _) async {},
          currentUserId: 'me',
          threadsListenable: listenable,
          resolveThread: (_) => thread,
          lastSeenForUser: (_) => null,
          actions: ChatActions(
            sendPendingText: (_, pendingMessage) async {
              submitted = pendingMessage;
              return true;
            },
            // The legacy callback must not create a second message when the
            // pending-aware transport is available.
            sendReply: (_, _, _) async => fail('legacy reply path was used'),
          ),
        ),
      ),
    );

    await tester.longPress(find.text('Исходное сообщение'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ответить'));
    await tester.pumpAndSettle();
    final composer = find.byKey(const Key('message-composer-field'));
    expect(tester.widget<TextField>(composer).focusNode?.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.enterText(composer, 'Ответ с одним id');
    await tester.pump();
    await tester.tap(find.byKey(const Key('message-send-button')));
    await tester.pumpAndSettle();

    expect(submitted?.id, startsWith('pending-'));
    expect(submitted?.replyToId, source.id);
    expect(submitted?.replyToText, source.previewText);
  });

  testWidgets('failed edit keeps composer focus and edited draft', (
    tester,
  ) async {
    final listenable = ValueNotifier<int>(0);
    addTearDown(listenable.dispose);
    final delivery = Completer<bool>();
    final source = ChatMessage(
      id: 'mine-1',
      text: 'Исходный текст',
      createdAt: DateTime.utc(2026, 7, 18, 11),
      isMine: true,
      senderId: 'me',
      senderName: 'Me',
    );
    final thread = _threadWithMessages([source]);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          thread: thread,
          onSendMessage: (_, _) async {},
          currentUserId: 'me',
          threadsListenable: listenable,
          resolveThread: (_) => thread,
          lastSeenForUser: (_) => null,
          actions: ChatActions(editMessage: (_, _, _) => delivery.future),
        ),
      ),
    );

    await tester.longPress(find.text('Исходный текст'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Редактировать'));
    await tester.pumpAndSettle();
    final composer = find.byKey(const Key('message-composer-field'));
    expect(tester.widget<TextField>(composer).focusNode?.hasFocus, isTrue);
    await tester.enterText(composer, 'Исправленный текст');
    await tester.tap(find.byKey(const Key('message-send-button')));
    await tester.pump();

    expect(tester.widget<TextField>(composer).readOnly, isTrue);
    expect(tester.widget<TextField>(composer).focusNode?.hasFocus, isTrue);
    delivery.complete(false);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(composer).readOnly, isFalse);
    expect(
      tester.widget<TextField>(composer).controller?.text,
      'Исправленный текст',
    );
    expect(
      find.textContaining('Не удалось сохранить изменения'),
      findsOneWidget,
    );
  });

  testWidgets('failed text retries with the same optimistic message id', (
    tester,
  ) async {
    final listenable = ValueNotifier<int>(0);
    addTearDown(listenable.dispose);
    final thread = _threadWithMessages(const []);
    String? retriedMessageId;
    String? initialMessageId;

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          thread: thread,
          onSendMessage: (_, _) async {},
          currentUserId: 'me',
          threadsListenable: listenable,
          resolveThread: (_) => thread,
          lastSeenForUser: (_) => null,
          actions: ChatActions(
            sendPendingText: (_, pendingMessage) async {
              initialMessageId = pendingMessage.id;
              return false;
            },
            retryText: (threadId, failedMessage) async {
              expect(threadId, thread.id);
              retriedMessageId = failedMessage.id;
              return true;
            },
          ),
        ),
      ),
    );

    final composer = find.byKey(const Key('message-composer-field'));
    await tester.enterText(composer, 'Повтори меня');
    await tester.pump();
    await tester.tap(find.byKey(const Key('message-send-button')));
    await tester.pumpAndSettle();

    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();

    expect(retriedMessageId, startsWith('pending-'));
    expect(retriedMessageId, initialMessageId);
    expect(find.text('Повторить'), findsNothing);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    expect(tester.widget<TextField>(composer).controller?.text, isEmpty);
  });

  testWidgets(
    'successful retry preserves an independently typed matching draft',
    (tester) async {
      final listenable = ValueNotifier<int>(0);
      addTearDown(listenable.dispose);
      final thread = _threadWithMessages(const []);
      final retryDelivery = Completer<bool>();
      const text = 'Одинаковый текст';

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            thread: thread,
            onSendMessage: (_, _) async {},
            currentUserId: 'me',
            threadsListenable: listenable,
            resolveThread: (_) => thread,
            lastSeenForUser: (_) => null,
            actions: ChatActions(
              sendPendingText: (_, _) async => false,
              retryText: (_, _) => retryDelivery.future,
            ),
          ),
        ),
      );

      final composer = find.byKey(const Key('message-composer-field'));
      await tester.enterText(composer, text);
      await tester.pump();
      await tester.tap(find.byKey(const Key('message-send-button')));
      await tester.pumpAndSettle();

      expect(find.text('Повторить'), findsOneWidget);
      expect(tester.widget<TextField>(composer).controller?.text, isEmpty);

      // This is a separate draft: it merely happens to have exactly the same
      // text as the failed bubble and does not belong to the retry operation.
      await tester.enterText(composer, text);
      await tester.pump();
      await tester.tap(find.text('Повторить'));
      await tester.pump();

      expect(tester.widget<TextField>(composer).controller?.text, text);

      retryDelivery.complete(true);
      await tester.pumpAndSettle();

      expect(find.text('Повторить'), findsNothing);
      expect(tester.widget<TextField>(composer).controller?.text, text);
    },
  );

  testWidgets('failed media does not expose the text-only retry action', (
    tester,
  ) async {
    final listenable = ValueNotifier<int>(0);
    addTearDown(listenable.dispose);
    final thread = _threadWithMessages([
      ChatMessage(
        id: 'failed-image',
        text: '',
        createdAt: DateTime.utc(2026, 7, 18, 12),
        isMine: true,
        senderId: 'me',
        type: 'image',
        attachment: const ChatAttachment(
          url:
              'data:image/png;base64,'
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          name: 'failed.png',
          mimeType: 'image/png',
        ),
        hasError: true,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          thread: thread,
          onSendMessage: (_, _) async {},
          currentUserId: 'me',
          threadsListenable: listenable,
          resolveThread: (_) => thread,
          lastSeenForUser: (_) => null,
          actions: ChatActions(retryText: (_, _) async => true),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.text('Повторить'), findsNothing);
  });

  testWidgets('failed media retries with its original message id', (
    tester,
  ) async {
    final listenable = ValueNotifier<int>(0);
    addTearDown(listenable.dispose);
    final failed = ChatMessage(
      id: 'failed-image-retry',
      text: '',
      createdAt: DateTime.utc(2026, 7, 18, 12),
      isMine: true,
      senderId: 'me',
      type: 'image',
      attachment: const ChatAttachment(
        url:
            'data:image/png;base64,'
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        name: 'failed.png',
        mimeType: 'image/png',
      ),
      hasError: true,
    );
    final thread = _threadWithMessages([failed]);
    String? retriedId;

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          thread: thread,
          onSendMessage: (_, _) async {},
          currentUserId: 'me',
          threadsListenable: listenable,
          resolveThread: (_) => thread,
          lastSeenForUser: (_) => null,
          actions: ChatActions(
            retryMedia: (_, message) async {
              retriedId = message.id;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(retriedId, failed.id);
    expect(find.text('Повторить'), findsNothing);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
  });

  testWidgets('failed product uses the generic retry with the same identity', (
    tester,
  ) async {
    final listenable = ValueNotifier<int>(0);
    addTearDown(listenable.dispose);
    final failed = ChatMessage(
      id: 'local-product-share-1',
      text: 'Listing: Jacket',
      createdAt: DateTime.utc(2026, 7, 18, 12),
      isMine: true,
      senderId: 'me',
      type: 'product',
      sharedProduct: const SharedProductPreview(
        id: 'product-1',
        title: 'Jacket',
        image: '',
        price: '100',
      ),
      clientMessageId: 'client-product-share-1',
      hasError: true,
    );
    final thread = _threadWithMessages([failed]);
    ChatMessage? retried;

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          thread: thread,
          onSendMessage: (_, _) async {},
          currentUserId: 'me',
          threadsListenable: listenable,
          resolveThread: (_) => thread,
          lastSeenForUser: (_) => null,
          actions: ChatActions(
            retryMessage: (threadId, message) async {
              expect(threadId, thread.id);
              retried = message;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();

    expect(retried?.id, failed.id);
    expect(retried?.clientMessageId, failed.clientMessageId);
    expect(retried?.sharedProduct?.id, failed.sharedProduct?.id);
    expect(find.text('Повторить'), findsNothing);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
  });

  testWidgets(
    'refreshes a delivery receipt without a new message or timestamp',
    (tester) async {
      final listenable = ValueNotifier<int>(0);
      addTearDown(listenable.dispose);
      final sentAt = DateTime.utc(2026, 7, 17, 12);
      var thread = _threadWithMessages([
        ChatMessage(
          id: 'message-1',
          text: 'Привет',
          createdAt: sentAt,
          isMine: true,
          senderId: 'me',
          readBy: const ['me'],
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            thread: thread,
            onSendMessage: (_, _) async {},
            currentUserId: 'me',
            threadsListenable: listenable,
            resolveThread: (_) => thread,
            lastSeenForUser: (_) => null,
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.done_rounded), findsOneWidget);
      expect(find.byIcon(Icons.done_all_rounded), findsNothing);

      thread = thread.copyWith(
        messages: [
          thread.messages.single.copyWith(readBy: ['me', 'user']),
        ],
      );
      listenable.value++;
      await tester.pump();

      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
    },
  );

  testWidgets('delivered-to-only update rebuilds the matching message', (
    tester,
  ) async {
    final listenable = ValueNotifier<int>(0);
    addTearDown(listenable.dispose);
    var thread = _threadWithMessages([
      ChatMessage(
        id: 'server-delivery-1',
        text: 'Delivery probe',
        createdAt: DateTime.utc(2026, 7, 17, 12),
        isMine: true,
        senderId: 'me',
        clientMessageId: 'client-delivery-1',
        deliveredTo: const ['me'],
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          thread: thread,
          onSendMessage: (_, _) async {},
          currentUserId: 'me',
          threadsListenable: listenable,
          resolveThread: (_) => thread,
          lastSeenForUser: (_) => null,
        ),
      ),
    );
    await tester.pump();

    final before = tester.widget<Text>(find.text('Delivery probe'));
    expect(
      thread.messages.single.effectiveStatus,
      ChatMessageDeliveryStatus.sent,
    );

    thread = thread.copyWith(
      messages: [
        thread.messages.single.copyWith(deliveredTo: ['me', 'user']),
      ],
    );
    expect(
      thread.messages.single.effectiveStatus,
      ChatMessageDeliveryStatus.delivered,
    );
    listenable.value++;
    await tester.pump();

    final after = tester.widget<Text>(find.text('Delivery probe'));
    expect(identical(before, after), isFalse);
  });

  testWidgets('marks messages arriving in an open chat as read', (
    tester,
  ) async {
    final listenable = ValueNotifier<int>(0);
    addTearDown(listenable.dispose);
    var thread = _threadWithMessages(const []);
    var markReadCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          thread: thread,
          onSendMessage: (_, _) async {},
          currentUserId: 'me',
          threadsListenable: listenable,
          resolveThread: (_) => thread,
          lastSeenForUser: (_) => null,
          actions: ChatActions(
            markRead: (_) async {
              markReadCalls++;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(markReadCalls, 1);

    thread = thread.copyWith(
      unreadCount: 1,
      messages: [
        ChatMessage(
          id: 'incoming-1',
          text: 'Новое сообщение',
          createdAt: DateTime.utc(2026, 7, 17, 12, 1),
          isMine: false,
          senderId: 'user',
        ),
      ],
    );
    listenable.value++;
    await tester.pump();
    await tester.pump();

    expect(markReadCalls, 2);
    expect(find.text('Новое сообщение'), findsOneWidget);
  });
}

MessageThread _threadWithMessages(List<ChatMessage> messages) => MessageThread(
  id: 'direct-me-user',
  sellerName: 'User',
  buyerName: 'Me',
  productTitle: '',
  lastMessage: messages.isEmpty ? '' : messages.last.previewText,
  // Keep this timestamp stable in the read-receipt regression test.
  updatedAt: DateTime.utc(2026, 7, 17, 12),
  buyerId: 'me',
  sellerId: 'user',
  members: const [
    ConversationMember(id: 'me', name: 'Me', handle: '@me'),
    ConversationMember(id: 'user', name: 'User', handle: '@user'),
  ],
  messages: messages,
);
