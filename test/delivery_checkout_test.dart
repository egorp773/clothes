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
      DeliveryProfile? savedProfile;
      final product = _product();

      await _pumpCheckoutHost(
        tester,
        product: product,
        deliveryProfile: _pickupProfile,
        onSaveProfile: (profile) async {
          savedProfile = profile;
        },
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
      await tester.tap(find.byKey(const Key('checkout-submit')));
      await tester.pumpAndSettle();

      expect(submittedService, 'pickup_point:unassigned');
      expect(submittedPrice, 0);
      expect(savedProfile?.city, 'Москва');
      expect(savedProfile?.address, isEmpty);
      expect(savedProfile?.pickupPointAddress, 'ул. Тверская, 10');
      expect(savedProfile?.pickupPointId, startsWith('manual_'));
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
    await tester.tap(find.byKey(const Key('checkout-submit')));
    await tester.pumpAndSettle();

    expect(submittedService, 'pickup_point:unassigned');
    expect(submittedPrice, 0);
    expect(find.byKey(const Key('checkout-submit')), findsOneWidget);
    expect(
      find.text('Не удалось оформить заказ. Попробуйте ещё раз.'),
      findsOneWidget,
    );
  });

  testWidgets('pickup requires a selected point but not a street address', (
    tester,
  ) async {
    var submitCalls = 0;
    await _pumpCheckoutHost(
      tester,
      product: _product(),
      deliveryProfile: _pickupProfile,
      onCreateDeliveryOrder:
          ({required deliveryService, required deliveryPrice}) async {
            submitCalls += 1;
            return null;
          },
    );

    await tester.tap(find.byKey(const Key('delivery-method-pickup')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('checkout-submit')));
    await tester.pumpAndSettle();

    expect(submitCalls, 0);
    expect(find.text('Выбор пункта выдачи'), findsOneWidget);
    expect(find.text('Укажите город и адрес доставки'), findsNothing);
  });

  testWidgets('post delivery still requires a street address', (tester) async {
    var submitCalls = 0;
    await _pumpCheckoutHost(
      tester,
      product: _product(),
      deliveryProfile: _pickupProfile,
      onCreateDeliveryOrder:
          ({required deliveryService, required deliveryPrice}) async {
            submitCalls += 1;
            return null;
          },
    );

    await tester.tap(find.byKey(const Key('checkout-submit')));
    await tester.pump();

    expect(submitCalls, 0);
    expect(find.text('Укажите город и адрес доставки'), findsOneWidget);
    expect(find.text('Улица, дом, квартира'), findsOneWidget);
  });

  testWidgets('shows a typed server checkout error', (tester) async {
    await _pumpCheckoutHost(
      tester,
      product: _product(),
      onCreateDeliveryOrder:
          ({required deliveryService, required deliveryPrice}) async {
            throw const CheckoutException(
              code: 'authentication_required',
              message: 'Войдите в профиль, чтобы оформить заказ',
            );
          },
    );

    await tester.tap(find.byKey(const Key('checkout-submit')));
    await tester.pumpAndSettle();

    expect(
      find.text('Войдите в профиль, чтобы оформить заказ'),
      findsOneWidget,
    );
    expect(find.text('Оформление заказа'), findsOneWidget);
  });

  testWidgets('recipient save failure is explained without closing checkout', (
    tester,
  ) async {
    await _pumpCheckoutHost(
      tester,
      product: _product(),
      onSaveProfile: (_) async => throw StateError('network unavailable'),
      onCreateDeliveryOrder:
          ({required deliveryService, required deliveryPrice}) async => null,
    );

    await tester.scrollUntilVisible(find.text('Изменить данные'), 300);
    await tester.tap(find.text('Изменить данные'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить данные'));
    await tester.pumpAndSettle();

    expect(
      find.text('Не удалось сохранить данные получателя. Попробуйте ещё раз.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('checkout-submit')), findsOneWidget);
  });

  testWidgets('submits only a carrier offered by the listing', (tester) async {
    String? submittedService;
    final product = _product(deliveryMethods: const ['russian_post']);
    await _pumpCheckoutHost(
      tester,
      product: product,
      onCreateDeliveryOrder:
          ({required deliveryService, required deliveryPrice}) async {
            submittedService = deliveryService;
            return AppOrder.fromProduct(
              product: product,
              buyerId: 'buyer-id',
              status: AppOrderStatus.pendingConfirmation,
              deliveryProfile: _completeProfile,
              deliveryService: deliveryService,
              deliveryPrice: deliveryPrice,
            );
          },
    );

    await tester.tap(find.byKey(const Key('checkout-submit')));
    await tester.pumpAndSettle();

    expect(submittedService, 'address:russian_post');
  });

  testWidgets('unsupported listing delivery cannot reach order creation', (
    tester,
  ) async {
    var submitCalls = 0;
    await _pumpCheckoutHost(
      tester,
      product: _product(deliveryMethods: const ['personal_meeting']),
      onCreateDeliveryOrder:
          ({required deliveryService, required deliveryPrice}) async {
            submitCalls += 1;
            return null;
          },
    );

    await tester.tap(find.byKey(const Key('checkout-submit')));
    await tester.pumpAndSettle();

    expect(submitCalls, 0);
    expect(
      find.text('Продавец не подключил доставку для этого объявления'),
      findsWidgets,
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

const _pickupProfile = DeliveryProfile(
  fullName: 'Иван Иванов',
  phone: '+7 999 123-45-67',
  email: 'ivan@example.test',
  city: 'Москва',
);

Product _product({List<String> deliveryMethods = const []}) => Product(
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
  deliveryMethods: deliveryMethods,
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
  DeliveryProfile deliveryProfile = _completeProfile,
  Future<void> Function(DeliveryProfile profile)? onSaveProfile,
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
                      deliveryMethods: product.deliveryMethods,
                    ),
                    deliveryProfile: deliveryProfile,
                    onSaveProfile: onSaveProfile ?? (_) async {},
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
  await tester.tap(find.byKey(const Key('delivery-method-pickup')));
  await tester.pump();
  expect(find.text('Пункт ещё не выбран'), findsOneWidget);
  await tester.tap(find.byKey(const Key('pickup-point-selector')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('pickup-point-field')),
    'ул. Тверская, 10',
  );
  await tester.tap(find.byKey(const Key('pickup-point-save')));
  await tester.pumpAndSettle();
  expect(find.text('ул. Тверская, 10'), findsWidgets);
}
