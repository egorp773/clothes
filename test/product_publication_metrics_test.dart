import 'package:clothes/models/app_profile.dart';
import 'package:clothes/models/product.dart';
import 'package:clothes/models/profile_feature.dart';
import 'package:clothes/screens/product_screen.dart';
import 'package:clothes/widgets/app_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Product _product({
  String id = 'product-1',
  DateTime? publishedAt,
  int viewsCount = 0,
  int likesCount = 0,
}) {
  return Product(
    id: id,
    title: 'Свитер',
    detailTitle: 'Свитер',
    description: 'Описание товара',
    price: '1 000 ₽',
    detailPrice: '1 000',
    priceValue: 1000,
    image: '',
    category: 'Свитеры',
    brand: 'Brand',
    size: 'M',
    color: 'Белый',
    condition: 'Отличное',
    dotsOnDark: false,
    publishedAt: publishedAt,
    viewsCount: viewsCount,
    likesCount: likesCount,
  );
}

void main() {
  test('Product metrics are backward compatible and serialize to Supabase', () {
    final legacy = Product.fromJson(_product().toJson()..remove('viewsCount'));
    expect(legacy.viewsCount, 0);
    expect(legacy.likesCount, 0);

    final product = Product.fromSupabase({
      ..._product().toSupabaseJson(sellerId: 'seller'),
      'views_count': 12,
      'likes_count': 5,
      'published_at': '2026-07-16T12:34:00Z',
    });
    expect(product.viewsCount, 12);
    expect(product.likesCount, 5);
    expect(product.publishedAt?.isUtc, isTrue);
    expect(product.toJson()['viewsCount'], 12);
    expect(product.toSupabaseJson(sellerId: 'seller')['likes_count'], 5);
  });

  testWidgets('product detail shows publication time, views and likes', (
    tester,
  ) async {
    final publishedAt = DateTime(2026, 7, 16, 12, 34);
    final product = _product(
      publishedAt: publishedAt,
      viewsCount: 12,
      likesCount: 5,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProductScreen(
          isPreview: true,
          sourceProduct: product,
          product: ProductDetailData(
            id: product.id,
            title: product.title,
            description: product.description,
            price: product.price,
            priceValue: product.priceValue,
            image: product.image,
            images: const [],
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
          onLike: () {},
          onContactSeller: () {},
          onOpenSeller: () {},
          onOpenReviews: () {},
          relatedProducts: const [],
          onRelatedProductTap: (_) {},
          deliveryProfile: const DeliveryProfile(),
          onSaveDeliveryProfile: (_) async {},
          onCreateDeliveryOrder:
              ({required deliveryService, required deliveryPrice}) async =>
                  null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(find.text('Опубликовано: 16.07.2026, 12:34'), findsOneWidget);
    expect(find.bySemanticsLabel('12 просмотров'), findsOneWidget);
    expect(find.bySemanticsLabel('5 лайков'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.clock), findsNothing);

    final publicationLeft = tester.getTopLeft(
      find.text('Опубликовано: 16.07.2026, 12:34'),
    );
    final viewsLeft = tester.getTopLeft(find.bySemanticsLabel('12 просмотров'));
    final likesLeft = tester.getTopLeft(find.bySemanticsLabel('5 лайков'));
    expect(publicationLeft.dx, lessThan(viewsLeft.dx));
    expect(viewsLeft.dx, lessThan(likesLeft.dx));
  });

  testWidgets('seller avatar renders and related products follow compactly', (
    tester,
  ) async {
    final product = _product();
    const avatar = 'assets/mock/avatar_eva.jpg';

    await tester.pumpWidget(
      MaterialApp(
        home: ProductScreen(
          isPreview: true,
          sourceProduct: product,
          product: ProductDetailData(
            id: product.id,
            title: product.title,
            description: product.description,
            price: product.price,
            priceValue: product.priceValue,
            image: product.image,
            images: const [],
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
          onLike: () {},
          onContactSeller: () {},
          onOpenSeller: () {},
          onOpenReviews: () {},
          loadSellerProfile: (_) async => const SellerProfile(
            id: 'seller',
            name: 'Продавец',
            handle: '@seller',
            avatarUrl: avatar,
          ),
          relatedProducts: [_product(id: 'related-product')],
          onRelatedProductTap: (_) {},
          deliveryProfile: const DeliveryProfile(),
          onSaveDeliveryProfile: (_) async {},
          onCreateDeliveryOrder:
              ({required deliveryService, required deliveryPrice}) async =>
                  null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppImage && widget.imageUrl == avatar,
        description: 'seller profile avatar',
      ),
      findsOneWidget,
    );

    final avatarRect = tester.getRect(
      find.byWidgetPredicate(
        (widget) => widget is AppImage && widget.imageUrl == avatar,
        description: 'seller profile avatar',
      ),
    );
    final relatedTop = tester.getTopLeft(find.text('Похожие объявления')).dy;
    expect(relatedTop - avatarRect.bottom, inInclusiveRange(10, 24));
  });
}
