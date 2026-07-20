import 'package:clothes/models/profile_feature.dart';
import 'package:clothes/screens/profile_feature_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shows buyer order, hides foreign cache and omits empty tracking',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime.utc(2026, 7, 17, 10, 30);
      final buyerOrder = _order(
        id: 'buyer-order',
        title: 'Пальто покупателя',
        buyerId: 'current-user',
        sellerId: 'seller-user',
        trackingNumber: '',
        createdAt: now,
      );
      final foreignOrder = _order(
        id: 'foreign-order',
        title: 'Чужой сохранённый заказ',
        buyerId: 'another-buyer',
        sellerId: 'another-seller',
        trackingNumber: 'FOREIGN-TRACK',
        createdAt: now.add(const Duration(hours: 1)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileOrdersScreen(
            orders: [foreignOrder, buyerOrder],
            recommendedProducts: const [],
            currentUserId: 'current-user',
            onProductTap: (_) {},
            onShareProduct: (_) {},
            onToggleProductLike: (_) async {},
            onOpenCatalog: () {},
          ),
        ),
      );

      expect(find.text('Пальто покупателя'), findsOneWidget);
      expect(find.text('Покупка'), findsOneWidget);
      expect(find.text('Чужой сохранённый заказ'), findsNothing);
      expect(
        find.byKey(const Key('order-tracking-copy-buyer-order')),
        findsNothing,
      );
      expect(find.byIcon(Icons.copy_rounded), findsNothing);
    },
  );
}

AppOrder _order({
  required String id,
  required String title,
  required String buyerId,
  required String sellerId,
  required String trackingNumber,
  required DateTime createdAt,
}) {
  return AppOrder(
    id: id,
    productId: 'product-$id',
    productTitle: title,
    productImage: '',
    productPrice: '2 000 ₽',
    productPriceValue: 2000,
    sellerId: sellerId,
    buyerId: buyerId,
    trackingNumber: trackingNumber,
    deliveryService: 'Почта России',
    deliveryAddress: 'Москва',
    recipientName: 'Покупатель',
    recipientPhone: '',
    recipientEmail: '',
    deliveryPrice: 200,
    status: AppOrderStatus.shipped,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}
