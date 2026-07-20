import 'package:clothes/data/app_repository.dart';
import 'package:clothes/models/profile_feature.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppOrder server-authoritative projection', () {
    test('parses server wire status and delivery values', () {
      final order = AppOrder.fromJson({
        'id': 'server-order',
        'seller_id': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'buyer_id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        'status': 'seller_confirmed',
        'delivery_service': 'Пункт выдачи',
        'delivery_price': 0,
      });

      expect(order.status, AppOrderStatus.sellerConfirmed);
      expect(order.deliveryService, 'Пункт выдачи');
      expect(order.deliveryPrice, 0);
    });

    test('local cache serialization is not a remote write payload', () {
      final payload = _order(id: 'local').toJson();

      expect(payload['statusName'], AppOrderStatus.created.name);
      expect(payload, isNot(contains('seller_id')));
      expect(payload, isNot(contains('buyer_id')));
    });
  });

  group('AppRepository order sync merge', () {
    test(
      'keeps local participant rows, uses remote matching row and sorts',
      () {
        const currentUserId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
        final localOnly = _order(
          id: 'local-only',
          title: 'Local pending order',
          updatedAt: DateTime.utc(2026, 7, 17, 12),
        );
        final localDuplicate = _order(
          id: 'shared',
          title: 'Local copy',
          updatedAt: DateTime.utc(2026, 7, 17, 13),
        );
        final remoteAuthoritative = _order(
          id: 'shared',
          title: 'Remote copy',
          updatedAt: DateTime.utc(2026, 7, 17, 11),
        );
        final foreign = _order(
          id: 'foreign',
          buyerId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
          sellerId: 'dddddddd-dddd-dddd-dddd-dddddddddddd',
          updatedAt: DateTime.utc(2026, 7, 17, 14),
        );

        final merged = AppRepository.mergeOrdersForParticipant(
          localOrders: <AppOrder>[localDuplicate, localOnly, foreign],
          remoteOrders: <AppOrder>[remoteAuthoritative],
          participantId: currentUserId,
        );

        expect(merged.map((order) => order.id), <String>[
          'local-only',
          'shared',
        ]);
        expect(
          merged.singleWhere((order) => order.id == 'shared').productTitle,
          'Remote copy',
        );
      },
    );
  });
}

AppOrder _order({
  required String id,
  String title = 'Order',
  String buyerId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  String sellerId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  DateTime? updatedAt,
}) {
  final timestamp = updatedAt ?? DateTime.utc(2026, 7, 17, 10);
  return AppOrder(
    id: id,
    productId: 'product-$id',
    productTitle: title,
    productImage: '',
    productPrice: '1 500 ₽',
    productPriceValue: 1500,
    sellerId: sellerId,
    buyerId: buyerId,
    trackingNumber: '',
    deliveryService: 'Почта России',
    deliveryAddress: 'Москва',
    recipientName: 'Покупатель',
    recipientPhone: '',
    recipientEmail: '',
    deliveryPrice: 122,
    status: AppOrderStatus.created,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}
