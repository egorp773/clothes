import 'package:clothes/features/chat/chat_avatar.dart';
import 'package:clothes/models/message_thread.dart';
import 'package:clothes/screens/messages_screen.dart';
import 'package:clothes/widgets/app_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('product chat keeps the person avatar as the primary image', (
    tester,
  ) async {
    final thread = MessageThread(
      id: 'product-chat',
      sellerName: 'Seller',
      buyerName: 'Buyer',
      sellerAvatar: 'https://example.com/seller.jpg',
      productTitle: 'Sweater',
      productId: 'product-1',
      productImage: 'https://example.com/product.jpg',
      lastMessage: 'Hello',
      updatedAt: DateTime.utc(2026, 7, 17),
      buyerId: 'buyer',
      sellerId: 'seller',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatAvatar.thread(thread: thread, currentUserId: 'buyer'),
        ),
      ),
    );

    final images = tester
        .widgetList<AppImage>(find.byType(AppImage))
        .map((image) => image.imageUrl)
        .toList();
    expect(images.first, 'https://example.com/seller.jpg');
    expect(images.last, 'https://example.com/product.jpg');
  });

  testWidgets('group messages render the current sender avatar', (
    tester,
  ) async {
    final listenable = ValueNotifier<int>(0);
    addTearDown(listenable.dispose);
    final thread = MessageThread(
      id: 'group-chat',
      sellerName: 'Alice',
      buyerName: 'Me',
      productTitle: '',
      lastMessage: 'Привет',
      updatedAt: DateTime.utc(2026, 7, 17),
      buyerId: 'me',
      sellerId: 'alice',
      isGroup: true,
      title: 'Беседа',
      members: const [
        ConversationMember(id: 'me', name: 'Me', handle: '@me'),
        ConversationMember(
          id: 'alice',
          name: 'Alice',
          handle: '@alice',
          avatarUrl: 'https://example.com/alice.jpg',
        ),
        ConversationMember(id: 'bob', name: 'Bob', handle: '@bob'),
      ],
      messages: [
        ChatMessage(
          id: 'message-1',
          text: 'Привет',
          createdAt: DateTime.utc(2026, 7, 17),
          isMine: false,
          senderId: 'alice',
          senderName: 'Alice',
        ),
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
        ),
      ),
    );
    await tester.pump();

    final imageUrls = tester
        .widgetList<AppImage>(find.byType(AppImage))
        .map((image) => image.imageUrl);
    expect(imageUrls, contains('https://example.com/alice.jpg'));
    expect(find.text('Привет'), findsOneWidget);
  });
}
