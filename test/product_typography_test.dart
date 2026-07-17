import 'package:clothes/core/app_typography.dart';
import 'package:clothes/models/profile_feature.dart';
import 'package:clothes/screens/product_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'description keeps product typography with tighter line spacing',
    (tester) async {
      tester.view.physicalSize = const Size(480, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: AppTypography.fontFamily),
          home: ProductScreen(
            product: const ProductDetailData(
              id: 'product-1',
              title: 'Куртка',
              description: 'Описание товара',
              price: '12 000 ₽',
              priceValue: 12000,
              image: 'assets/products/open_shoulder_top.jpg',
              images: ['assets/products/open_shoulder_top.jpg'],
              category: 'Куртки',
              brand: 'Brand',
              color: 'Чёрный',
              sellerName: 'Продавец',
              sellerHandle: '@seller',
              size: 'M',
              condition: 'Отличное',
              location: 'Москва',
              isLiked: false,
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
            isPreview: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final descriptionFinder = find.text('Описание товара');
      await tester.scrollUntilVisible(
        descriptionFinder,
        300,
        scrollable: find.byType(Scrollable).first,
      );

      final characteristicFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.textSpan?.toPlainText() == 'Категория: Куртки',
        description: 'characteristic body text',
      );
      final characteristic = tester
          .renderObject<RenderParagraph>(characteristicFinder)
          .text
          .style;
      final characteristicSpan =
          tester.renderObject<RenderParagraph>(characteristicFinder).text
              as TextSpan;
      final valueSpan = characteristicSpan.children!.last as TextSpan;

      final description = tester
          .renderObject<RenderParagraph>(descriptionFinder)
          .text
          .style;
      expect(characteristic?.fontSize, description?.fontSize);
      expect(characteristic?.fontFamily, description?.fontFamily);
      expect(characteristic?.fontWeight, AppTypography.semiBold);
      expect(description?.fontWeight, AppTypography.semiBold);
      expect(description?.height, 1.16);
      expect(description!.height!, lessThan(characteristic!.height!));
      expect(valueSpan.style, isNull);
    },
  );
}
