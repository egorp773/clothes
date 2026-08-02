import 'package:clothes/models/message_thread.dart';
import 'package:clothes/screens/messages_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders and opens a shared product inside chat', (tester) async {
    final listenable = ValueNotifier(0);
    addTearDown(listenable.dispose);
    final thread = MessageThread(
      id: 'direct-me-alice',
      sellerName: 'Alice',
      buyerName: 'Me',
      productTitle: '',
      lastMessage: 'Объявление: Кожаная куртка',
      updatedAt: DateTime(2026, 7, 12),
      buyerId: 'me',
      sellerId: 'alice',
      members: const [
        ConversationMember(id: 'me', name: 'Me', handle: '@me'),
        ConversationMember(id: 'alice', name: 'Alice', handle: '@alice'),
      ],
      messages: [
        ChatMessage(
          id: 'share-1',
          text: 'Объявление: Кожаная куртка',
          createdAt: DateTime(2026, 7, 12),
          isMine: false,
          senderId: 'alice',
          senderName: 'Alice',
          type: 'product',
          sharedProduct: const SharedProductPreview(
            id: 'product-1',
            title: 'Кожаная куртка',
            image: '',
            price: '12 000 ₽',
          ),
        ),
      ],
    );
    String? openedProduct;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          thread: thread,
          onSendMessage: (_, _) async {},
          onOpenProduct: (id) => openedProduct = id,
          currentUserId: 'me',
          threadsListenable: listenable,
          resolveThread: (_) => thread,
          lastSeenForUser: (_) => null,
        ),
      ),
    );

    expect(find.text('Кожаная куртка'), findsOneWidget);
    expect(find.text('12 000 ₽'), findsOneWidget);
    await tester.tap(find.text('Кожаная куртка'));
    expect(openedProduct, 'product-1');
  });

  testWidgets('hides Buy in a chat about the current seller own listing', (
    tester,
  ) async {
    final listenable = ValueNotifier(0);
    addTearDown(listenable.dispose);
    final thread = _productThread();

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          thread: thread,
          onSendMessage: (_, _) async {},
          currentUserId: 'seller',
          threadsListenable: listenable,
          resolveThread: (_) => thread,
          lastSeenForUser: (_) => null,
          onBuyProduct: () => fail('seller must not see a purchase action'),
        ),
      ),
    );

    expect(find.byKey(const Key('chat-buy-product')), findsNothing);
    expect(find.text('Купить'), findsNothing);
  });

  testWidgets('shows Buy only to the explicit buyer in a product chat', (
    tester,
  ) async {
    final listenable = ValueNotifier(0);
    addTearDown(listenable.dispose);
    final thread = _productThread();
    var buyCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          thread: thread,
          onSendMessage: (_, _) async {},
          currentUserId: 'buyer',
          threadsListenable: listenable,
          resolveThread: (_) => thread,
          lastSeenForUser: (_) => null,
          onBuyProduct: () => buyCalls++,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('chat-buy-product')));
    expect(buyCalls, 1);
  });
}

MessageThread _productThread() => MessageThread(
  id: 'product-thread',
  sellerName: 'Seller',
  buyerName: 'Buyer',
  productTitle: 'Кожаная куртка',
  productId: 'product-1',
  productImage: '',
  lastMessage: '',
  updatedAt: DateTime(2026, 7, 12),
  buyerId: 'buyer',
  sellerId: 'seller',
  members: const [
    ConversationMember(id: 'buyer', name: 'Buyer', handle: '@buyer'),
    ConversationMember(id: 'seller', name: 'Seller', handle: '@seller'),
  ],
);
