import 'dart:async';

import 'package:clothes/features/chat/chat_actions.dart';
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
    await tester.enterText(find.byType(TextField).last, 'target');
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump();
    expect(find.text('Target User'), findsOneWidget);

    await tester.tap(find.text('Target User'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('direct-chat-opening-target-user')),
      findsOneWidget,
    );
    await tester.tap(find.text('Target User'));
    await tester.pump();
    expect(openCalls, 1);

    opening.complete(null);
    await tester.pumpAndSettle();
    expect(openCalls, 1);
  });

  testWidgets('search failure is visible and can be retried', (tester) async {
    final listenable = ChangeNotifier();
    addTearDown(listenable.dispose);
    var calls = 0;
    const target = AppUserProfile(
      id: 'target-user',
      name: 'Target User',
      handle: '@target',
    );

    await tester.pumpWidget(
      _messagesApp(
        threadsListenable: listenable,
        onSearchUsers: (_) async {
          calls++;
          if (calls == 1) throw StateError('network unavailable');
          return const [target];
        },
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'target');
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump();

    expect(find.text('Не удалось найти пользователя'), findsOneWidget);
    expect(find.textContaining('Проверьте подключение'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump();

    expect(calls, 2);
    expect(find.text('Target User'), findsOneWidget);
  });

  testWidgets('existing thread opens a tappable composer and sends text', (
    tester,
  ) async {
    final listenable = ChangeNotifier();
    addTearDown(listenable.dispose);
    final thread = _emptyDirectThread();
    final sent = <String>[];

    await tester.pumpWidget(
      _messagesApp(
        threads: [thread],
        threadsListenable: listenable,
        onSendMessage: (_, text) async => sent.add(text),
      ),
    );
    await tester.tap(find.text('User'));
    await tester.pumpAndSettle();

    final composer = find.byKey(const Key('message-composer-field'));
    expect(composer, findsOneWidget);
    await tester.showKeyboard(composer);
    await tester.enterText(composer, 'Реальное сообщение');
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.widget<TextField>(composer).focusNode?.hasFocus, isTrue);

    await tester.tap(find.byKey(const Key('message-send-button')));
    await tester.pumpAndSettle();
    expect(sent, ['Реальное сообщение']);
    expect(find.text('Реальное сообщение'), findsOneWidget);
  });

  testWidgets('conversation creation failure stays visible inside the sheet', (
    tester,
  ) async {
    final listenable = ChangeNotifier();
    addTearDown(listenable.dispose);
    const target = AppUserProfile(
      id: 'target-user',
      name: 'Target User',
      handle: '@target',
    );

    await tester.pumpWidget(
      _messagesApp(
        threadsListenable: listenable,
        onSearchUsers: (_) async => const [target],
        onCreateConversation: (_, {title = ''}) async => null,
      ),
    );
    await tester.tap(find.byKey(const Key('messages-compose-button')));
    await tester.pumpAndSettle();
    // The inbox search field remains mounted below the modal route; target
    // the sheet field, which is the last one in paint order.
    await tester.enterText(find.byType(TextField).last, 'target');
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pump();
    await tester.ensureVisible(find.text('Target User'));
    await tester.pump();
    await tester.tap(find.text('Target User'));
    await tester.pump();
    await tester.tap(find.text('Начать диалог'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Не удалось создать беседу'), findsOneWidget);
    expect(find.byKey(const Key('new-chat-create-error')), findsOneWidget);
    expect(find.text('Новая беседа'), findsOneWidget);
  });

  testWidgets('new conversation sheet remains usable above a small keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final listenable = ChangeNotifier();
    addTearDown(listenable.dispose);

    await tester.pumpWidget(_messagesApp(threadsListenable: listenable));
    await tester.tap(find.byKey(const Key('messages-compose-button')));
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    final keyboardPadding = tester.widget<AnimatedPadding>(
      find.byType(AnimatedPadding).last,
    );
    expect(
      keyboardPadding.padding.resolve(TextDirection.ltr).bottom,
      closeTo(280, 0.01),
    );
    final action = find.widgetWithText(FilledButton, 'Начать диалог');
    expect(action, findsOneWidget);
    expect(tester.getBottomLeft(action).dy, lessThanOrEqualTo(289));
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
  Future<MessageThread?> Function(List<AppUserProfile> users, {String title})?
  onCreateConversation,
  Future<void> Function(String threadId, String text)? onSendMessage,
  ChatActions? actions,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MessagesScreen(
        threads: threads,
        onSendMessage: onSendMessage ?? (_, _) async {},
        onSearchUsers: onSearchUsers ?? (_) async => const <AppUserProfile>[],
        onStartDirectChat: onStartDirectChat ?? (_) async => null,
        onCreateConversation:
            onCreateConversation ?? (_, {title = ''}) async => null,
        currentUserId: 'me',
        threadsListenable: threadsListenable,
        resolveThread: (threadId) {
          for (final thread in threads) {
            if (thread.id == threadId) return thread;
          }
          return null;
        },
        lastSeenForUser: (_) => null,
        actions: actions,
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
