import 'package:clothes/models/product.dart';
import 'package:clothes/models/profile_feature.dart';
import 'package:clothes/screens/catalog_screen.dart';
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
          onContactSeller: (_) async => null,
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
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(viewCalls, 0);
    await tester.ensureVisible(find.byType(ProductCard));
    await tester.pumpAndSettle();
    expect(viewCalls, 0);

    await tester.tap(find.byType(ProductCard));
    await tester.pumpAndSettle();

    expect(viewCalls, 1);
    expect(product.viewsCount, 11);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('11 просмотров'), findsOneWidget);
  });
}
