import 'package:clothes/features/chat/product_share_sheet.dart';
import 'package:clothes/models/app_profile.dart';
import 'package:clothes/models/message_thread.dart';
import 'package:clothes/models/product.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selects a recent avatar and sends a product to the thread', (
    tester,
  ) async {
    final product = _product();
    String? sentThreadId;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showProductShareSheet(
                context,
                product: product,
                threads: [_thread()],
                currentUserId: 'me',
                searchUsers: (_) async => const [],
                shareToThread: (threadId, _) async {
                  sentThreadId = threadId;
                  return true;
                },
                shareToUser: (_, _) async => null,
              ),
              child: const Text('share'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('share'));
    await tester.pumpAndSettle();
    expect(find.text('Поделиться объявлением'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.text('Отправить · 1'), findsOneWidget);
    await tester.tap(find.text('Отправить · 1'));
    await tester.pumpAndSettle();

    expect(sentThreadId, 'direct-me-alice');
    expect(find.text('Отправлено: 1'), findsOneWidget);
  });
  testWidgets('keeps the share sheet usable when sending throws', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showProductShareSheet(
                context,
                product: _product(),
                threads: [_thread()],
                currentUserId: 'me',
                searchUsers: (_) async => const [],
                shareToThread: (_, _) async => throw Exception('offline'),
                shareToUser: (_, _) async => null,
              ),
              child: const Text('share with error'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('share with error'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share-send-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('share-send-bar')), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('share-send-button')),
    );
    expect(button.onPressed, isNotNull);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('searching an existing recipient reuses the direct thread', (
    tester,
  ) async {
    var threadSends = 0;
    var userSends = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showProductShareSheet(
                context,
                product: _product(),
                threads: [_thread()],
                currentUserId: 'me',
                searchUsers: (_) async => const [
                  AppUserProfile(id: 'alice', name: 'Alice', handle: '@alice'),
                ],
                shareToThread: (_, _) async {
                  threadSends++;
                  return true;
                },
                shareToUser: (_, _) async {
                  userSends++;
                  return null;
                },
              ),
              child: const Text('search share'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('search share'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Найти по @username'),
      'alice',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    await tester.tap(find.text('@alice'));
    await tester.pumpAndSettle();

    expect(find.text('Отправить · 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('share-send-button')));
    await tester.pumpAndSettle();

    expect(threadSends, 1);
    expect(userSends, 0);
  });
}

Product _product() => Product(
  id: 'product-1',
  title: 'Кожаная куртка',
  detailTitle: 'Кожаная куртка',
  description: '',
  price: '12 000 ₽',
  detailPrice: '12 000 ₽',
  priceValue: 12000,
  image: '',
  category: 'Одежда',
  brand: 'Brand',
  size: 'M',
  color: 'Чёрный',
  condition: 'Отличное',
  ownerId: 'seller',
  sellerName: 'Seller',
  sellerHandle: '@seller',
  dotsOnDark: false,
);

MessageThread _thread() => MessageThread(
  id: 'direct-me-alice',
  sellerName: 'Alice',
  buyerName: 'Me',
  sellerHandle: '@alice',
  buyerHandle: '@me',
  productTitle: '',
  lastMessage: 'Привет',
  updatedAt: DateTime(2026, 7, 12),
  buyerId: 'me',
  sellerId: 'alice',
  members: const [
    ConversationMember(id: 'me', name: 'Me', handle: '@me'),
    ConversationMember(id: 'alice', name: 'Alice', handle: '@alice'),
  ],
);
