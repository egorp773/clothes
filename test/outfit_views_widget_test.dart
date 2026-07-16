import 'dart:async';

import 'package:clothes/models/created_outfit.dart';
import 'package:clothes/models/product.dart';
import 'package:clothes/models/profile_feature.dart';
import 'package:clothes/screens/outfits_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  testWidgets('resolved view count never decreases the initial count', (
    tester,
  ) async {
    await _pumpOutfit(tester, onOutfitViewed: (_) => Future<int>.value(2));

    expect(find.text('137'), findsOneWidget);
    expect(find.text('2'), findsNothing);
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
}

Future<void> _pumpOutfit(
  WidgetTester tester, {
  required Future<int> Function(String outfitId) onOutfitViewed,
}) async {
  const outfit = CreatedOutfit(
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
        createdOutfits: const [outfit],
        onCreateTap: () {},
        onToggleProductLike: (_) async {},
        onToggleOutfitLike: (_) async {},
        onProductViewed: (_) async => 0,
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

  await tester.tap(find.byKey(const ValueKey('outfit-card-outfit-id')));
  await tester.pumpAndSettle();
}
