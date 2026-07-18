import 'dart:async';

import 'package:clothes/models/message_thread.dart';
import 'package:clothes/models/product.dart';
import 'package:clothes/models/profile_feature.dart';
import 'package:clothes/screens/catalog_screen.dart';
import 'package:clothes/screens/product_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('catalog records a product view only after detail opens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final product = Product(
      id: 'product-1',
      title: 'Тестовый свитер',
      detailTitle: 'Тестовый свитер',
      description: 'Описание товара',
      price: '1 000 ₽',
      detailPrice: '1 000 ₽',
      priceValue: 1000,
      image: '',
      category: 'Свитеры',
      brand: 'Brand',
      size: 'M',
      color: 'Белый',
      condition: 'Отличное',
      dotsOnDark: false,
      publishedAt: DateTime(2026, 7, 16, 12, 34),
      viewsCount: 10,
      likesCount: 3,
    );
    var viewCalls = 0;
    var contactCalls = 0;
    var authenticationRequests = 0;
    final threads = ValueNotifier<int>(0);
    addTearDown(threads.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: CatalogScreen(
          scale: 1,
          sidePadding: 12,
          products: [product],
          onToggleLike: (_) async {},
          onHideProduct: (_) async {},
          onSubmitContentReport:
              ({
                required targetType,
                required targetId,
                required reason,
                details = '',
              }) async => true,
          onBlockUser: (_) async => true,
          onShareProduct: (_) {},
          onContactSeller: (_) async {
            contactCalls++;
            return null;
          },
          onLoadSellerProfile: (_) async => null,
          onLoadSellerProducts: (_) async => const [],
          onStartDirectChat: (_) async => null,
          onSendMessage: (_, _) async {},
          onProductViewed: (viewedProduct) {
            viewCalls += 1;
            viewedProduct.viewsCount += 1;
          },
          deliveryProfile: const DeliveryProfile(),
          onSaveDeliveryProfile: (_) async {},
          onCreateDeliveryOrder:
              (_, {required deliveryService, required deliveryPrice}) async =>
                  null,
          onLoadReviews: (_) async => const [],
          onCreateReview:
              ({
                required sellerId,
                required productId,
                required productTitle,
                required productImage,
                required rating,
                required text,
                hasPhoto = false,
              }) async {},
          currentUserId: 'viewer-1',
          threadsListenable: threads,
          resolveThread: (_) => null,
          lastSeenForUser: (_) => null,
          onChatAuthenticationRequired:
              (requestedProduct, {Route<dynamic>? sourceRoute}) {
                expect(requestedProduct.id, product.id);
                expect(sourceRoute, isA<ProductPageRoute<void>>());
                authenticationRequests++;
              },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(viewCalls, 0);
    await tester.ensureVisible(find.byType(ProductCard));
    await tester.pumpAndSettle();
    expect(viewCalls, 0);
    final catalogScrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    final catalogOffsetBeforeOpen = catalogScrollable.position.pixels;

    await tester.tap(find.byType(ProductCard));
    await tester.pumpAndSettle();

    expect(viewCalls, 1);
    expect(product.viewsCount, 11);
    final productScrollView = find.descendant(
      of: find.byType(ProductScreen),
      matching: find.byType(CustomScrollView),
    );
    await tester.drag(productScrollView, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('11 просмотров'), findsOneWidget);

    await tester.tap(find.byKey(productScreenMessageButtonKey));
    await tester.pump();
    expect(authenticationRequests, 1);
    expect(contactCalls, 0);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ProductScreen), findsNothing);
    expect(
      catalogScrollable.position.pixels,
      closeTo(catalogOffsetBeforeOpen, 0.01),
    );
  });

  testWidgets('product contact is single-flight while thread creation waits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final product = _testProduct('product-single-flight');
    final delivery = Completer<MessageThread?>();
    final threads = ValueNotifier<int>(0);
    addTearDown(threads.dispose);
    var contactCalls = 0;

    await tester.pumpWidget(
      _catalogHarness(
        product: product,
        threads: threads,
        onContactSeller: (_) {
          contactCalls++;
          return delivery.future;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byType(ProductCard),
      find.byType(CustomScrollView).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ProductCard));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(productScreenMessageButtonKey));
    await tester.pump();
    await tester.tap(find.byKey(productScreenMessageButtonKey));
    await tester.pump();
    expect(contactCalls, 1);

    delivery.complete(null);
    await tester.pumpAndSettle();
    expect(contactCalls, 1);
  });
}

Product _testProduct(String id) => Product(
  id: id,
  title: 'Тестовый свитер',
  detailTitle: 'Тестовый свитер',
  description: 'Описание товара',
  price: '1 000 ₽',
  detailPrice: '1 000 ₽',
  priceValue: 1000,
  image: '',
  category: 'Свитеры',
  brand: 'Brand',
  size: 'M',
  color: 'Белый',
  condition: 'Отличное',
  dotsOnDark: false,
);

Widget _catalogHarness({
  required Product product,
  required Listenable threads,
  required Future<MessageThread?> Function(Product) onContactSeller,
}) {
  return MaterialApp(
    home: CatalogScreen(
      scale: 1,
      sidePadding: 12,
      products: [product],
      onToggleLike: (_) async {},
      onHideProduct: (_) async {},
      onSubmitContentReport:
          ({
            required targetType,
            required targetId,
            required reason,
            details = '',
          }) async => true,
      onBlockUser: (_) async => true,
      onShareProduct: (_) {},
      onContactSeller: onContactSeller,
      onLoadSellerProfile: (_) async => null,
      onLoadSellerProducts: (_) async => const [],
      onStartDirectChat: (_) async => null,
      onSendMessage: (_, _) async {},
      onProductViewed: (_) {},
      deliveryProfile: const DeliveryProfile(),
      onSaveDeliveryProfile: (_) async {},
      onCreateDeliveryOrder:
          (_, {required deliveryService, required deliveryPrice}) async => null,
      onLoadReviews: (_) async => const [],
      onCreateReview:
          ({
            required sellerId,
            required productId,
            required productTitle,
            required productImage,
            required rating,
            required text,
            hasPhoto = false,
          }) async {},
      currentUserId: 'viewer-1',
      threadsListenable: threads,
      resolveThread: (_) => null,
      lastSeenForUser: (_) => null,
    ),
  );
}
