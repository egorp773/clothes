import 'package:clothes/features/listing_publish/data/listing_publish_repository.dart';
import 'package:clothes/features/listing_publish/listing_publish_controller.dart';
import 'package:clothes/features/listing_publish/models/listing_draft.dart';
import 'package:clothes/features/listing_publish/screens/listing_publish_flow_screen.dart';
import 'package:clothes/features/listing_publish/screens/listing_attributes_step.dart';
import 'package:clothes/features/listing_publish/screens/listing_basics_step.dart';
import 'package:clothes/features/listing_publish/screens/listing_preview_step.dart';
import 'package:clothes/features/listing_publish/services/product_image_analyzer.dart';
import 'package:clothes/features/listing_publish/widgets/listing_publish_widgets.dart';
import 'package:clothes/screens/product_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('basic step is stable and contains only first required fields', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ListingBasicsStep(controller: controller)),
      ),
    );

    expect(find.text('Название *', findRichText: true), findsOneWidget);
    expect(find.text('Цена *', findRichText: true), findsOneWidget);
    expect(find.text('Описание (необязательно)'), findsOneWidget);
    expect(find.byKey(const ValueKey('basic_description')), findsOneWidget);
    expect(find.byKey(const ValueKey('basic_brand')), findsOneWidget);
    expect(find.byKey(const ValueKey('basic_size')), findsOneWidget);
    expect(find.byKey(const ValueKey('basic_condition')), findsOneWidget);
    expect(find.byKey(const ValueKey('basic_audience')), findsOneWidget);
    expect(find.text('Категория', findRichText: true), findsNothing);
    expect(find.text('Основной цвет', findRichText: true), findsNothing);
    expect(find.text('Есть дефекты'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('photo step disables continue until a photo exists', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    expect(tester.takeException(), isNull);

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
      ..secondaryColors.addAll(['blue', 'white'])
      ..gender = 'unisex'
      ..material = 'cotton'
      ..pattern = 'solid'
      ..fit = 'regular'
      ..categoryAttributes.addAll({
        'material': 'cotton',
        'pattern': 'solid',
        'fit': 'regular',
      });
    controller.draft
      ..hasDefects = true
      ..defectsReviewed = true
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
    expect(
      find.textContaining('Категория:', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Аудитория:', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Дополнительные цвета:', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('Крой:', findRichText: true), findsOneWidget);
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

    expect(find.byKey(const ValueKey('detail_category')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail_primary_color')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('detail_secondary_colors')),
      findsOneWidget,
    );
    expect(find.text('Есть дефекты'), findsOneWidget);
    expect(find.byKey(const ValueKey('defects_none')), findsOneWidget);
    expect(find.byKey(const ValueKey('defects_yes')), findsOneWidget);
    expect(find.text('Материал'), findsOneWidget);
    expect(find.text('Рисунок'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Крой'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Крой'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Тип застёжки'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Тип застёжки'), findsOneWidget);
    expect(find.text('Длина рукава'), findsNothing);
    expect(find.text('Посадка'), findsNothing);
    expect(find.text('Пол'), findsNothing);

    expect(find.byKey(const ValueKey('detail_description')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('review has no per-field confirm buttons and supports skip', (
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
      ..normalizedCategory = 'hoodie'
      ..material = 'cotton'
      ..categoryAttributes['material'] = 'cotton'
      ..predictions['material'] = ListingFieldPrediction(
        fieldName: 'material',
        predictedValue: 'cotton',
        confidence: 0.8,
        source: 'visual',
      );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ListingAttributesStep(controller: controller)),
      ),
    );

    expect(find.byKey(const ValueKey('confirm_material')), findsNothing);
    expect(find.text('Предложено'), findsOneWidget);

    controller.confirmRequiredDetails();
    await tester.pump();
    expect(controller.draft.predictions['material']?.userConfirmed, isTrue);

    await tester.tap(find.byKey(const ValueKey('attribute_material')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Не указывать'));
    await tester.pumpAndSettle();
    expect(controller.draft.material, isEmpty);
    expect(controller.buildProduct(preview: true).material, isEmpty);
    expect(controller.draft.predictions['material']?.predictedValue, 'cotton');

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('published listing handoff can retry without republishing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repository = _FlowRepository();
    final controller = ListingPublishController(
      repository: repository,
      analyzer: _UnusedAnalyzer(),
      sellerName: 'Seller',
      sellerHandle: '@seller',
    );
    var completionCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ListingPublishFlowScreen(
          sidePadding: 18,
          sellerName: 'Seller',
          sellerHandle: '@seller',
          initialCity: 'Москва',
          onClose: () {},
          onPublished: (_) async {
            completionCalls += 1;
            if (completionCalls == 1) throw StateError('handoff failed');
          },
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.draft = _readyToPublishDraft()
      ..currentStep = ListingPublishStep.preview;
    controller.goToStep(ListingPublishStep.preview);
    await tester.pump();

    await tester.tap(find.text('Опубликовать'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(repository.publishCalls, 1);
    expect(completionCalls, 1);
    expect(
      find.text('Объявление уже опубликовано, но карточку не удалось открыть.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('listing-completion-retry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('listing-completion-retry')));
    await tester.pumpAndSettle();

    expect(repository.publishCalls, 1);
    expect(completionCalls, 2);
    expect(find.text('Готово'), findsOneWidget);

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

ListingDraft _readyToPublishDraft() {
  final draft = ListingDraft.empty(sellerId: 'seller')
    ..title = 'Худи'
    ..price = 4500
    ..size = 'm'
    ..condition = 'excellent'
    ..section = 'unisex'
    ..category = 'clothing'
    ..subcategory = 'tops'
    ..itemType = 'hoodie'
    ..normalizedCategory = 'hoodie'
    ..gender = 'unisex'
    ..primaryColor = 'black'
    ..brand = 'no_brand'
    ..defectsReviewed = true
    ..city = 'Москва'
    ..shippingAddress = 'Тверская, 1';
  draft.deliveryMethods.add('cdek');
  draft.photos.add(
    ListingPhoto(
      id: 'photo',
      localPath: '/tmp/photo.jpg',
      remoteUrl: 'https://example.com/photo.jpg',
      storagePath: 'users/seller/listings/id/photo.jpg',
      uploadStatus: ListingPhotoUploadStatus.uploaded,
    ),
  );
  draft.mainPhotoId = 'photo';
  return draft;
}

class _FlowRepository extends ListingPublishRepository {
  _FlowRepository()
    : super(sellerName: 'Seller', sellerHandle: '@seller', fallbackCity: '');

  int publishCalls = 0;

  @override
  String get sellerId => 'seller';

  @override
  Future<ListingDeliveryDefaults> loadDeliveryDefaults() async =>
      const ListingDeliveryDefaults();

  @override
  Future<List<ListingDraft>> loadLocalDrafts() async => const [];

  @override
  Future<void> saveLocalDraft(ListingDraft draft) async {}

  @override
  Future<void> syncRemoteDraft(ListingDraft draft) async {}

  @override
  Future<void> publish(ListingDraft draft) async {
    publishCalls += 1;
    draft.status = ListingStatus.published;
  }
}
