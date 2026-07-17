import 'dart:async';

import 'package:clothes/models/created_outfit.dart';
import 'package:clothes/models/product.dart';
import 'package:clothes/models/profile_feature.dart';
import 'package:clothes/screens/outfits_screen.dart';
import 'package:clothes/widgets/app_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('outfit list records a view only after opening the detail', (
    tester,
  ) async {
    var recordCalls = 0;
    await _pumpOutfit(
      tester,
      openDetail: false,
      onOutfitViewed: (_) async {
        recordCalls += 1;
        return 138;
      },
    );

    expect(recordCalls, 0);

    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -80),
    );
    await tester.pump();
    expect(recordCalls, 0);

    await tester.tap(find.byKey(const ValueKey('outfit-card-outfit-id')));
    await tester.pumpAndSettle();
    expect(recordCalls, 1);
  });

  testWidgets('missing outfit product does not record a product view', (
    tester,
  ) async {
    var productViewCalls = 0;
    const outfit = CreatedOutfit(
      id: 'outfit-with-missing-product',
      photos: [],
      items: [
        OutfitItem(
          id: 'deleted-product',
          name: 'Удалённая вещь',
          price: '1 000 ₽',
          image: '',
        ),
      ],
    );

    await _pumpOutfit(
      tester,
      outfit: outfit,
      openDetail: false,
      onProductViewed: (_) async {
        productViewCalls += 1;
        return 1;
      },
      onOutfitViewed: (_) async => 1,
    );

    await tester.ensureVisible(find.text('Удалённая вещь'));
    await tester.tap(find.text('Удалённая вещь'));
    await tester.pumpAndSettle();

    expect(productViewCalls, 0);
    expect(find.text('Упс, этот товар не продается'), findsOneWidget);
    expect(
      find.text('Объявление удалено или больше недоступно.'),
      findsOneWidget,
    );
  });

  testWidgets('outfit detail opens before the view count future completes', (
    tester,
  ) async {
    final completer = Completer<int>();
    var recordCalls = 0;
    await _pumpOutfit(
      tester,
      onOutfitViewed: (_) {
        recordCalls += 1;
        return completer.future;
      },
    );

    expect(recordCalls, 1);
    expect(completer.isCompleted, isFalse);
    expect(find.byIcon(Icons.arrow_back), findsWidgets);
    expect(find.text('137'), findsOneWidget);

    completer.complete(142);
    await tester.pumpAndSettle();

    expect(find.text('142'), findsOneWidget);
    expect(find.text('137'), findsNothing);
  });

  testWidgets('authoritative view count corrects a stale optimistic count', (
    tester,
  ) async {
    await _pumpOutfit(tester, onOutfitViewed: (_) => Future<int>.value(2));

    expect(find.text('2'), findsOneWidget);
    expect(find.text('137'), findsNothing);
  });

  testWidgets('failed view recording keeps outfit detail usable', (
    tester,
  ) async {
    await _pumpOutfit(
      tester,
      onOutfitViewed: (_) => Future<int>.error(StateError('offline')),
    );

    expect(find.byIcon(Icons.arrow_back), findsWidgets);
    expect(find.text('137'), findsOneWidget);
  });

  testWidgets('outfit detail shows author avatar, date, views and likes', (
    tester,
  ) async {
    final publishedAt = DateTime(2026, 7, 16, 12, 34);
    final outfit = CreatedOutfit(
      id: 'outfit-with-avatar',
      photos: const [],
      items: const [
        OutfitItem(id: 'item-id', name: 'Тестовая вещь', price: '', image: ''),
      ],
      authorName: 'Тестовый автор',
      authorHandle: '@author',
      authorAvatarUrl: 'assets/mock/avatar_eva.jpg',
      likesCount: 9,
      viewsCount: 137,
      publishedAt: publishedAt,
    );

    await _pumpOutfit(tester, outfit: outfit, onOutfitViewed: (_) async => 138);

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppImage &&
            widget.imageUrl == 'assets/mock/avatar_eva.jpg',
        description: 'outfit author avatar',
      ),
      findsOneWidget,
    );
    expect(find.text('Опубликовано: 16.07.2026, 12:34'), findsOneWidget);
    expect(find.bySemanticsLabel('138 просмотров'), findsOneWidget);
    expect(find.bySemanticsLabel('9 лайков'), findsOneWidget);

    final dateLeft = tester.getTopLeft(
      find.text('Опубликовано: 16.07.2026, 12:34'),
    );
    final viewsLeft = tester.getTopLeft(
      find.bySemanticsLabel('138 просмотров'),
    );
    expect(dateLeft.dx, lessThan(viewsLeft.dx));
  });

  testWidgets('empty outfit does not inject editorial author or products', (
    tester,
  ) async {
    const outfit = CreatedOutfit(
      id: 'empty-outfit',
      photos: [],
      items: [],
      authorName: '',
      authorHandle: '',
      likesCount: -4,
      viewsCount: -8,
    );

    await _pumpOutfit(tester, outfit: outfit, onOutfitViewed: (_) async => -2);

    expect(find.text('Автор'), findsOneWidget);
    expect(find.text('Lil Yachty'), findsNothing);
    expect(find.text('Endless Denim'), findsNothing);
    expect(find.bySemanticsLabel('0 просмотров'), findsOneWidget);
    expect(find.bySemanticsLabel('0 лайков'), findsOneWidget);
  });
}

Future<void> _pumpOutfit(
  WidgetTester tester, {
  required Future<int> Function(String outfitId) onOutfitViewed,
  bool openDetail = true,
  CreatedOutfit? outfit,
  Future<int> Function(String productId)? onProductViewed,
}) async {
  outfit ??= const CreatedOutfit(
    id: 'outfit-id',
    photos: [],
    items: [
      OutfitItem(id: 'item-id', name: 'Тестовая вещь', price: '', image: ''),
    ],
    authorName: 'Тестовый автор',
    authorHandle: '@author',
    viewsCount: 137,
  );

  await tester.pumpWidget(
    MaterialApp(
      home: OutfitsScreen(
        scale: 1,
        sidePadding: 12,
        createdOutfits: [outfit],
        onCreateTap: () {},
        onToggleProductLike: (_) async {},
        onToggleOutfitLike: (_) async {},
        onProductViewed: onProductViewed ?? (_) async => 0,
        onOutfitViewed: onOutfitViewed,
        onContactSeller: (Product product, {bool imageOnly = false}) async {},
        onOpenSellerProfile: (_) {},
        deliveryProfile: const DeliveryProfile(),
        onSaveDeliveryProfile: (_) async {},
        onCreateDeliveryOrder:
            (
              Product product, {
              required String deliveryService,
              required int deliveryPrice,
            }) async => null,
      ),
    ),
  );

  if (openDetail) {
    await tester.tap(find.byKey(ValueKey<String>('outfit-card-${outfit.id}')));
    await tester.pumpAndSettle();
  }
}
