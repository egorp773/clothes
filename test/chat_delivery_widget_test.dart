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
