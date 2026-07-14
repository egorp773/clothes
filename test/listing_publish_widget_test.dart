import 'package:clothes/features/listing_publish/data/listing_publish_repository.dart';
import 'package:clothes/features/listing_publish/listing_publish_controller.dart';
import 'package:clothes/features/listing_publish/models/listing_draft.dart';
import 'package:clothes/features/listing_publish/screens/listing_publish_flow_screen.dart';
import 'package:clothes/features/listing_publish/screens/listing_attributes_step.dart';
import 'package:clothes/features/listing_publish/screens/listing_preview_step.dart';
import 'package:clothes/features/listing_publish/services/product_image_analyzer.dart';
import 'package:clothes/features/listing_publish/widgets/listing_publish_widgets.dart';
import 'package:clothes/screens/product_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('photo step disables continue until a photo exists', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = ListingPublishController(
      repository: ListingPublishRepository(
        sellerName: 'Seller',
        sellerHandle: '@seller',
        fallbackCity: 'Москва',
      ),
      analyzer: _UnusedAnalyzer(),
      sellerName: 'Seller',
      sellerHandle: '@seller',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ListingPublishFlowScreen(
          sidePadding: 18,
          sellerName: 'Seller',
          sellerHandle: '@seller',
          initialCity: 'Москва',
          onClose: () {},
          onPublished: (_) async {},
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    var button = tester.widget<ListingPrimaryBottomButton>(
      find.byType(ListingPrimaryBottomButton),
    );
    expect(button.onPressed, isNull);

    controller.draft.photos.add(
      ListingPhoto(id: 'photo', localPath: '/tmp/photo.jpg'),
    );
    controller.goToStep(ListingPublishStep.photos);
    await tester.pump();

    button = tester.widget<ListingPrimaryBottomButton>(
      find.byType(ListingPrimaryBottomButton),
    );
    expect(button.onPressed, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('preview is the buyer card without technical characteristics', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = ListingPublishController(
      repository: ListingPublishRepository(
        sellerName: 'Seller',
        sellerHandle: '@seller',
        fallbackCity: 'Москва',
      ),
      analyzer: _UnusedAnalyzer(),
      sellerName: 'Seller',
      sellerHandle: '@seller',
    );
    await controller.initialize();
    controller.draft
      ..title = 'Куртка'
      ..description = 'Лёгкая куртка'
      ..price = 5000
      ..category = 'outerwear'
      ..normalizedCategory = 'jacket'
      ..condition = 'new'
      ..size = 'm'
      ..brand = 'no_brand'
      ..primaryColor = 'black'
      ..material = 'cotton'
      ..categoryAttributes['material'] = 'cotton';
    controller.draft
      ..hasDefects = true
      ..defectDescription = 'Небольшая царапина у кармана'
      ..city = 'Москва';
    controller.draft.photos.add(ListingPhoto(id: 'photo', localPath: ''));

    await tester.pumpWidget(
      MaterialApp(home: ListingPreviewStep(controller: controller)),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final materialFinder = find.textContaining('Материал', findRichText: true);
    expect(find.byType(ProductScreen), findsOneWidget);
    expect(find.text('Похожие объявления'), findsNothing);
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -1200),
      1800,
    );
    await tester.pumpAndSettle();
    expect(materialFinder, findsOneWidget);
    expect(find.text('Раздел'), findsNothing);
    expect(find.text('Подкатегория'), findsNothing);
    expect(find.text('Тип вещи'), findsNothing);
    expect(find.text('Пол'), findsNothing);
    expect(find.text('Город'), findsNothing);
    expect(find.text('Дефекты'), findsOneWidget);
    expect(find.text('Небольшая царапина у кармана'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('characteristic review only shows fields for final category', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = ListingPublishController(
      repository: ListingPublishRepository(
        sellerName: 'Seller',
        sellerHandle: '@seller',
        fallbackCity: 'Москва',
      ),
      analyzer: _UnusedAnalyzer(),
      sellerName: 'Seller',
      sellerHandle: '@seller',
    );
    await controller.initialize();
    controller.draft.normalizedCategory = 'hoodie';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ListingAttributesStep(controller: controller)),
      ),
    );

    expect(find.text('Материал'), findsOneWidget);
    expect(find.text('Рисунок'), findsOneWidget);
    expect(find.text('Крой'), findsOneWidget);
    expect(find.text('Тип застёжки'), findsOneWidget);
    expect(find.text('Длина рукава'), findsNothing);
    expect(find.text('Посадка'), findsNothing);
    expect(find.text('Категория'), findsNothing);
    expect(find.text('Пол'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

class _UnusedAnalyzer implements ProductImageAnalyzer {
  @override
  Future<ProductAnalysisResult> analyze({
    required List<String> imageUrls,
    String? listingId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ProductAnalysisResult?> getAnalysis(String analysisId) async => null;
}
