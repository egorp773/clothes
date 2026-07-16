import 'package:clothes/models/product.dart';
import 'package:clothes/models/profile_feature.dart';
import 'package:clothes/screens/product_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'pickup submits free delivery and closes checkout for a created order',
    (tester) async {
      String? submittedService;
      int? submittedPrice;
      final product = _product();

      await _pumpCheckoutHost(
        tester,
        product: product,
        onCreateDeliveryOrder:
            ({required deliveryService, required deliveryPrice}) async {
              submittedService = deliveryService;
              submittedPrice = deliveryPrice;
              return AppOrder.fromProduct(
                product: product,
                buyerId: 'buyer-id',
                status: AppOrderStatus.awaitingPayment,
                deliveryProfile: _completeProfile,
                deliveryService: deliveryService,
                deliveryPrice: deliveryPrice,
              );
            },
      );

      await _openCheckoutAndSelectPickup(tester);
      await tester.tap(find.textContaining('ОФОРМИТЬ ЗАКАЗ'));
      await tester.pumpAndSettle();

      expect(submittedService, 'Пункт выдачи');
      expect(submittedPrice, 0);
      expect(find.text('Оформление заказа'), findsNothing);
      expect(find.byKey(const Key('open-checkout')), findsOneWidget);
    },
  );

  testWidgets('null order keeps checkout open and shows an error', (
    tester,
  ) async {
    String? submittedService;
    int? submittedPrice;

    await _pumpCheckoutHost(
      tester,
      product: _product(),
      onCreateDeliveryOrder:
          ({required deliveryService, required deliveryPrice}) async {
            submittedService = deliveryService;
            submittedPrice = deliveryPrice;
            return null;
          },
    );

    await _openCheckoutAndSelectPickup(tester);
    await tester.tap(find.textContaining('ОФОРМИТЬ ЗАКАЗ'));
    await tester.pumpAndSettle();

    expect(submittedService, 'Пункт выдачи');
    expect(submittedPrice, 0);
    expect(find.text('Оформление заказа'), findsOneWidget);
    expect(
      find.text(
        'Не удалось оформить заказ. Проверьте вход и попробуйте ещё раз.',
      ),
      findsOneWidget,
    );
  });
}

const _completeProfile = DeliveryProfile(
  fullName: 'Иван Иванов',
  phone: '+7 999 123-45-67',
  email: 'ivan@example.test',
  city: 'Москва',
  address: 'ул. Тестовая, 1',
);

Product _product() => Product(
  id: 'product-id',
  title: 'Тестовая куртка',
  detailTitle: 'Тестовая куртка',
  description: 'Описание',
  price: '3 500 ₽',
  detailPrice: '3500',
  priceValue: 3500,
  image: '',
  category: 'Куртка',
  brand: 'Test',
  size: 'M',
  color: 'Чёрный',
  condition: 'Новое',
  location: 'Москва',
  ownerId: 'seller-id',
  sellerName: 'Продавец',
  sellerHandle: '@seller',
  dotsOnDark: false,
);

Future<void> _pumpCheckoutHost(
  WidgetTester tester, {
  required Product product,
  required Future<AppOrder?> Function({
    required String deliveryService,
    required int deliveryPrice,
  })
  onCreateDeliveryOrder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('open-checkout'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DeliveryCheckoutScreen(
                    product: ProductDetailData(
                      id: product.id,
                      title: product.title,
                      description: product.description,
                      price: product.price,
                      priceValue: product.priceValue,
                      image: product.image,
                      images: product.images,
                      category: product.category,
                      brand: product.brand,
                      color: product.color,
                      sellerName: product.sellerName,
                      sellerHandle: product.sellerHandle,
                      size: product.size,
                      condition: product.condition,
                      location: product.location,
                      isLiked: product.isLiked,
                    ),
                    deliveryProfile: _completeProfile,
                    onSaveProfile: (_) async {},
                    onSubmitOrder: onCreateDeliveryOrder,
                  ),
                ),
              ),
              child: const Text('Открыть оформление'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open-checkout')));
  await tester.pumpAndSettle();
}

Future<void> _openCheckoutAndSelectPickup(WidgetTester tester) async {
  expect(find.text('Оформление заказа'), findsOneWidget);
  await tester.tap(find.text('Пункт выдачи'));
  await tester.pump();
}
