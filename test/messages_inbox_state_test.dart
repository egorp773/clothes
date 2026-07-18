import 'dart:async';

import 'package:clothes/models/app_profile.dart';
import 'package:clothes/models/message_thread.dart';
import 'package:clothes/screens/messages_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an empty direct conversation stays visible in the inbox', (
    tester,
  ) async {
    final listenable = ChangeNotifier();
    addTearDown(listenable.dispose);
    final thread = _emptyDirectThread();

    await tester.pumpWidget(
      _messagesApp(threads: [thread], threadsListenable: listenable),
    );

    expect(find.text('User'), findsOneWidget);
    expect(find.text('Напишите сообщение'), findsOneWidget);
  });

  testWidgets('inbox exposes authentication, loading and retry states', (
    tester,
  ) async {
    final listenable = ChangeNotifier();
    addTearDown(listenable.dispose);
    var signInCalls = 0;
    var retryCalls = 0;

    await tester.pumpWidget(
      _messagesApp(
        threadsListenable: listenable,
        isAuthenticated: false,
        onSignIn: () => signInCalls++,
      ),
    );
    expect(find.text('Войдите, чтобы открыть сообщения'), findsOneWidget);
    await tester.tap(find.text('Войти'));
    expect(signInCalls, 1);

    await tester.pumpWidget(
      _messagesApp(threadsListenable: listenable, isLoading: true),
    );
    expect(find.text('Загружаем диалоги'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      _messagesApp(
        threadsListenable: listenable,
        errorMessage: 'Сервер не отвечает',
        onRetryLoad: () => retryCalls++,
      ),
    );
    expect(find.text('Не удалось загрузить сообщения'), findsOneWidget);
    expect(find.text('Сервер не отвечает'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    expect(retryCalls, 1);

    final cached = _emptyDirectThread();
    await tester.pumpWidget(
      _messagesApp(
        threads: [cached],
        threadsListenable: listenable,
        errorMessage: 'Не удалось обновить',
        onRetryLoad: () => retryCalls++,
      ),
    );
    expect(find.byKey(const Key('inbox-sync-error-banner')), findsOneWidget);
    expect(find.text('User'), findsOneWidget);
    expect(find.text('Не удалось загрузить сообщения'), findsNothing);
    await tester.tap(find.byKey(const Key('inbox-sync-retry')));
    expect(retryCalls, 2);
  });

  testWidgets('opening a searched user is single-flight', (tester) async {
    final listenable = ChangeNotifier();
    addTearDown(listenable.dispose);
    final opening = Completer<MessageThread?>();
    var openCalls = 0;
    const target = AppUserProfile(
      id: 'target-user',
      name: 'Target User',
      handle: '@target',
    );

    await tester.pumpWidget(
      _messagesApp(
        threadsListenable: listenable,
        onSearchUsers: (_) async => const [target],
        onStartDirectChat: (_) {
          openCalls++;
          return opening.future;
        },
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'target');
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump();
    expect(find.text('Target User'), findsOneWidget);

    await tester.tap(find.text('Target User'));
    await tester.pump();
    await tester.tap(find.text('Target User'));
    await tester.pump();
    expect(openCalls, 1);

    opening.complete(null);
    await tester.pumpAndSettle();
    expect(openCalls, 1);
  });
}

Widget _messagesApp({
  List<MessageThread> threads = const [],
  required Listenable threadsListenable,
  bool isLoading = false,
  String? errorMessage,
  bool isAuthenticated = true,
  VoidCallback? onRetryLoad,
  VoidCallback? onSignIn,
  Future<List<AppUserProfile>> Function(String query)? onSearchUsers,
  Future<MessageThread?> Function(AppUserProfile user)? onStartDirectChat,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MessagesScreen(
        threads: threads,
        onSendMessage: (_, _) async {},
        onSearchUsers: onSearchUsers ?? (_) async => const <AppUserProfile>[],
        onStartDirectChat: onStartDirectChat ?? (_) async => null,
        onCreateConversation: (_, {title = ''}) async => null,
        currentUserId: 'me',
        threadsListenable: threadsListenable,
        resolveThread: (threadId) {
          for (final thread in threads) {
            if (thread.id == threadId) return thread;
          }
          return null;
        },
        lastSeenForUser: (_) => null,
        isLoading: isLoading,
        errorMessage: errorMessage,
        isAuthenticated: isAuthenticated,
        onRetryLoad: onRetryLoad,
        onSignIn: onSignIn,
      ),
    ),
  );
}

MessageThread _emptyDirectThread() => MessageThread(
  id: 'direct-me-user',
  sellerName: 'User',
  buyerName: 'Me',
  productTitle: '',
  lastMessage: '',
  updatedAt: DateTime.utc(2026, 7, 18),
  buyerId: 'me',
  sellerId: 'user',
  members: const [
    ConversationMember(id: 'me', name: 'Me', handle: '@me'),
    ConversationMember(id: 'user', name: 'User', handle: '@user'),
  ],
);
