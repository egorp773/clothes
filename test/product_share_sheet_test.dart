import 'package:clothes/features/chat/product_share_sheet.dart';
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
