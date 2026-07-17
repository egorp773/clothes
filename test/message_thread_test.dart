import 'package:clothes/models/message_thread.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('marks remote messages as mine by sender id', () {
    final thread = MessageThread.fromSupabase({
      'id': 'thread-1',
      'buyer_id': 'buyer-1',
      'seller_id': 'seller-1',
      'buyer_name': 'Buyer',
      'seller_name': 'Seller',
      'product_id': 'product-1',
      'product_title': 'Jacket',
      'product_image': '',
      'last_message': 'Second',
      'updated_at': '2026-05-18T12:00:00.000Z',
      'messages': [
        {
          'id': 'message-1',
          'text': 'First',
          'created_at': '2026-05-18T11:59:00.000Z',
          'sender_id': 'buyer-1',
          'sender_name': 'Buyer',
        },
        {
          'id': 'message-2',
          'text': 'Second',
          'created_at': '2026-05-18T12:00:00.000Z',
          'sender_id': 'seller-1',
          'sender_name': 'Seller',
        },
      ],
    }, currentUserId: 'seller-1');

    expect(thread.otherPartyName('seller-1'), 'Buyer');
    expect(thread.messages.first.isMine, isFalse);
    expect(thread.messages.last.isMine, isTrue);
  });

  test('round-trips group members and structured product shares', () {
    final thread = MessageThread(
      id: 'group-1',
      sellerName: 'Alice',
      buyerName: 'Me',
      productTitle: '',
      lastMessage: 'Объявление: Куртка',
      updatedAt: DateTime.utc(2026, 7, 12),
      buyerId: 'me',
      sellerId: 'alice',
      isGroup: true,
      title: 'Стильный чат',
      createdBy: 'me',
      members: const [
        ConversationMember(id: 'me', name: 'Me', handle: '@me'),
        ConversationMember(id: 'alice', name: 'Alice', handle: '@alice'),
        ConversationMember(id: 'bob', name: 'Bob', handle: '@bob'),
      ],
      messages: [
        ChatMessage(
          id: 'share-1',
          text: 'Объявление: Куртка',
          createdAt: DateTime.utc(2026, 7, 12),
          isMine: true,
          senderId: 'me',
          type: 'product',
          sharedProduct: const SharedProductPreview(
            id: 'product-1',
            title: 'Куртка',
            image: 'https://example.com/jacket.jpg',
            price: '12 000 ₽',
          ),
        ),
      ],
    );

    final restored = MessageThread.fromJson(thread.toJson());

    expect(restored.isGroup, isTrue);
    expect(restored.displayTitle('me'), 'Стильный чат');
    expect(restored.memberIds, containsAll(['me', 'alice', 'bob']));
    expect(restored.messages.single.isProductShare, isTrue);
    expect(restored.messages.single.sharedProduct?.price, '12 000 ₽');
    expect(restored.toSupabaseJson()['member_ids'], hasLength(3));
  });

  test('does not consume participant state from shared thread columns', () {
    final thread = MessageThread.fromSupabase({
      'id': 'thread-private-state',
      'buyer_id': 'buyer-1',
      'seller_id': 'seller-1',
      'updated_at': '2026-07-17T12:00:00Z',
      'is_pinned': true,
      'is_muted': true,
      'is_archived': true,
      'draft': 'another participant draft',
      'last_read_at': '2026-07-17T11:00:00Z',
    }, currentUserId: 'buyer-1');

    expect(thread.isPinned, isFalse);
    expect(thread.isMuted, isFalse);
    expect(thread.isArchived, isFalse);
    expect(thread.draft, isEmpty);
    expect(thread.lastReadAt, isNull);
    expect(thread.toSupabaseJson().containsKey('draft'), isFalse);
    expect(thread.toSupabaseJson().containsKey('is_pinned'), isFalse);
  });

  test('serializes chat timestamps as UTC and preserves remote instants', () {
    final localCreatedAt = DateTime(2026, 7, 16, 12, 30);
    final message = ChatMessage(
      id: 'message-local',
      text: 'Привет',
      createdAt: localCreatedAt,
      isMine: true,
      senderId: 'buyer-1',
    );

    expect(
      message.toSupabaseJson()['created_at'],
      localCreatedAt.toUtc().toIso8601String(),
    );
    expect(message.toSupabaseJson()['created_at'] as String, endsWith('Z'));

    final thread = MessageThread.fromSupabase({
      'id': 'thread-timezone',
      'buyer_id': 'buyer-1',
      'seller_id': 'seller-1',
      'updated_at': '2026-07-16T17:00:00+05:00',
      'messages': [
        {
          'id': 'message-offset',
          'text': 'Полдень по Москве',
          'created_at': '2026-07-16T15:00:00+03:00',
          'sender_id': 'seller-1',
        },
      ],
    }, currentUserId: 'buyer-1');

    expect(thread.updatedAt.toUtc(), DateTime.utc(2026, 7, 16, 12));
    expect(
      thread.messages.single.createdAt.toUtc(),
      DateTime.utc(2026, 7, 16, 12),
    );
  });

  test('resolves an avatar from profile, member, then recent messages', () {
    final fromMember = MessageThread(
      id: 'avatar-member',
      sellerName: 'Seller',
      buyerName: 'Buyer',
      productTitle: '',
      lastMessage: 'Hello',
      updatedAt: DateTime.utc(2026, 7, 17),
      buyerId: 'buyer',
      sellerId: 'seller',
      members: const [
        ConversationMember(id: 'buyer', name: 'Buyer', handle: '@buyer'),
        ConversationMember(
          id: 'seller',
          name: 'Seller',
          handle: '@seller',
          avatarUrl: 'https://example.com/member.jpg',
        ),
      ],
    );
    expect(fromMember.displayAvatar('buyer'), 'https://example.com/member.jpg');

    final fromMessage = fromMember.copyWith(
      members: const [
        ConversationMember(id: 'buyer', name: 'Buyer', handle: '@buyer'),
        ConversationMember(id: 'seller', name: 'Seller', handle: '@seller'),
      ],
      messages: [
        ChatMessage(
          id: 'message-avatar',
          text: 'Hello',
          createdAt: DateTime.utc(2026, 7, 17),
          isMine: false,
          senderId: 'seller',
          senderAvatar: 'https://example.com/message.jpg',
        ),
      ],
    );
    expect(
      fromMessage.displayAvatar('buyer'),
      'https://example.com/message.jpg',
    );

    final fromProfile = fromMessage.copyWith(
      sellerAvatar: 'https://example.com/profile.jpg',
    );
    expect(
      fromProfile.displayAvatar('buyer'),
      'https://example.com/profile.jpg',
    );
  });
}
