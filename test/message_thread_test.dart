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
}
