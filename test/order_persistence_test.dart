import 'package:clothes/data/app_repository.dart';
import 'package:clothes/models/product.dart';
import 'package:clothes/models/profile_feature.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppOrder Supabase payload', () {
    test('serializes missing or non-UUID seller as null', () {
      final missingSeller = _order(id: 'missing', sellerId: '');
      final localSeller = _order(id: 'local', sellerId: 'local-showroom');

      expect(missingSeller.toSupabaseJson()['seller_id'], isNull);
      expect(localSeller.toSupabaseJson()['seller_id'], isNull);
      expect(
        localSeller.toSupabaseJson()['buyer_id'],
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      );
    });

    test('preserves a valid seller UUID and selected delivery values', () {
      const sellerId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
      final order = AppOrder.fromProduct(
        product: _product(ownerId: '  $sellerId  '),
        buyerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        status: AppOrderStatus.pendingConfirmation,
        deliveryService: 'Пункт выдачи',
        deliveryPrice: 0,
      );
      final payload = order.toSupabaseJson();

      expect(payload['seller_id'], sellerId);
      expect(payload['delivery_service'], 'Пункт выдачи');
      expect(payload['delivery_price'], 0);
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

Product _product({String ownerId = ''}) {
  return Product(
    id: 'product-1',
    title: 'Тестовый товар',
    detailTitle: 'Тестовый товар',
    price: '1 500 ₽',
    detailPrice: '1 500 ₽',
    priceValue: 1500,
    image: 'image.jpg',
    category: 'Одежда',
    brand: 'Test',
    size: 'M',
    color: 'Чёрный',
    condition: 'Новое',
    ownerId: ownerId,
    dotsOnDark: false,
  );
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
    status: AppOrderStatus.pendingConfirmation,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}
