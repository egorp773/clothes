import 'package:clothes/features/listing_publish/data/listing_publish_repository.dart';
import 'package:clothes/features/listing_publish/data/listing_catalogs.dart';
import 'package:clothes/features/listing_publish/listing_publish_controller.dart';
import 'package:clothes/features/listing_publish/models/listing_draft.dart';
import 'package:clothes/features/listing_publish/services/product_image_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('category schemas stay compact and relevant', () {
    final tShirtFields = ListingCatalogs.attributesFor(
      't_shirt',
    ).map((field) => field.id).toList();
    final jeansFields = ListingCatalogs.attributesFor(
      'jeans',
    ).map((field) => field.id).toList();

    expect(tShirtFields.length, inInclusiveRange(3, 6));
    expect(tShirtFields, contains('sleeve_length'));
    expect(tShirtFields, isNot(contains('rise')));
    expect(jeansFields, contains('rise'));
    expect(jeansFields, isNot(contains('sleeve_length')));
  });

  group('ListingDraft', () {
    test('first step requires only seller-entered essentials', () {
      final draft = ListingDraft.empty(sellerId: 'seller')
        ..title = 'Худи'
        ..price = 4500
        ..brand = 'no_brand'
        ..size = 'm'
        ..condition = 'excellent'
        ..gender = 'unisex';

      expect(draft.description, isEmpty);
      expect(draft.normalizedCategory, isEmpty);
      expect(draft.primaryColor, isEmpty);
      expect(draft.validateBasics(), isNull);
      expect(draft.validateAttributes(), contains('категорию'));
    });

    test('round-trips all publication data', () {
      final draft = _validDraft();
      draft.predictions['primary_color'] = ListingFieldPrediction(
        fieldName: 'primary_color',
        predictedValue: 'blue',
        confirmedValue: 'black',
        confidence: 0.61,
        source: 'local_heuristic_v1',
        wasEdited: true,
      );

      final restored = ListingDraft.fromJson(draft.toJson());

      expect(restored.id, draft.id);
      expect(restored.photos.single.remoteUrl, 'https://example.com/photo.jpg');
      expect(restored.deliveryMethods, ['cdek']);
      expect(restored.predictions['primary_color']?.predictedValue, 'blue');
      expect(restored.predictions['primary_color']?.confirmedValue, 'black');
      expect(restored.predictions['primary_color']?.wasEdited, isTrue);
      expect(restored.normalizedCategory, 'hoodie');
      expect(restored.hasDefects, isTrue);
      expect(restored.defectDescription, 'Небольшая затяжка на рукаве');
      expect(restored.validateForPublish(), isNull);
    });

    test('requires uploaded photos and positive basics', () {
      final draft = ListingDraft.empty(sellerId: 'seller');
      expect(draft.validateForPublish(), contains('фотограф'));
      draft.photos.add(ListingPhoto(id: 'photo', localPath: '/tmp/photo.jpg'));
      expect(draft.validateForPublish(), contains('загрузки'));
    });
  });

  group('ListingPublishController', () {
    test('never overwrites a manually edited analyzed field', () {
      final controller = _controller();
      controller.draft = ListingDraft.empty(sellerId: 'seller');
      controller.setAttribute('primary_color', 'black');

      controller.applyAnalysisResult(_analysis(primaryColor: 'blue'));

      expect(controller.draft.primaryColor, 'black');
      final entry = controller.draft.predictions['primary_color'];
      expect(entry?.predictedValue, 'blue');
      expect(entry?.confirmedValue, 'black');
      expect(entry?.wasEdited, isTrue);
      controller.dispose();
    });

    test('never overwrites a confirmed ML suggestion on a later pass', () {
      final controller = _controller();
      controller.draft = ListingDraft.empty(sellerId: 'seller')
        ..normalizedCategory = 'hoodie'
        ..material = 'cotton'
        ..categoryAttributes['material'] = 'cotton'
        ..predictions['material'] = ListingFieldPrediction(
          fieldName: 'material',
          predictedValue: 'cotton',
          confidence: 0.8,
          source: 'visual',
        );

      controller.confirmRelevantAttributes();
      controller.applyAnalysisResult(
        _analysis(primaryColor: 'blue', material: 'polyester'),
      );

      expect(controller.draft.material, 'cotton');
      expect(controller.draft.predictions['material']?.userConfirmed, isTrue);
      controller.dispose();
    });

    test(
      'publishing is allowed while enrichment analysis is unavailable',
      () async {
        final repository = _FakeRepository();
        final controller = ListingPublishController(
          repository: repository,
          analyzer: _FakeAnalyzer(),
          sellerName: 'Seller',
          sellerHandle: '@seller',
        );
        controller.draft = _validDraft()
          ..analysisStatus = ListingAnalysisStatus.failed;

        final product = await controller.publish();

        expect(product.id, controller.draft.id);
        expect(repository.publishCalls, 1);
        controller.dispose();
      },
    );

    test('selecting gender keeps the internal section in sync', () {
      final controller = _controller();
      controller.draft = ListingDraft.empty(sellerId: 'seller');

      controller.setAttribute('gender', 'female');

      expect(controller.draft.gender, 'female');
      expect(controller.draft.section, 'women');
      controller.dispose();
    });

    test('coalesces repeated publish taps into one repository call', () async {
      final repository = _FakeRepository();
      final controller = ListingPublishController(
        repository: repository,
        analyzer: _FakeAnalyzer(),
        sellerName: 'Seller',
        sellerHandle: '@seller',
      );
      controller.draft = _validDraft();

      final results = await Future.wait([
        controller.publish(),
        controller.publish(),
      ]);

      expect(repository.publishCalls, 1);
      expect(results[0].id, results[1].id);
      controller.dispose();
    });
  });
}

ListingPublishController _controller() => ListingPublishController(
  repository: _FakeRepository(),
  analyzer: _FakeAnalyzer(),
  sellerName: 'Seller',
  sellerHandle: '@seller',
);

ListingDraft _validDraft() {
  final draft = ListingDraft.empty(sellerId: 'seller')
    ..title = 'Худи'
    ..price = 4500
    ..description = 'Чёрное хлопковое худи в отличном состоянии'
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
    ..hasDefects = true
    ..defectDescription = 'Небольшая затяжка на рукаве'
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

ProductAnalysisResult _analysis({
  required String primaryColor,
  String? material,
}) {
  const empty = AnalyzedField<String>(
    value: null,
    confidence: 0,
    source: 'test',
  );
  return ProductAnalysisResult(
    section: empty,
    category: empty,
    subcategory: empty,
    itemType: empty,
    gender: empty,
    primaryColor: AnalyzedField<String>(
      value: primaryColor,
      confidence: 0.9,
      source: 'test',
    ),
    secondaryColors: const [],
    brand: empty,
    material: AnalyzedField<String>(
      value: material,
      confidence: material == null ? 0 : 0.9,
      source: 'test',
    ),
    pattern: empty,
    season: empty,
    style: empty,
    suggestedTitle: empty,
    suggestedDescription: empty,
  );
}

class _FakeAnalyzer implements ProductImageAnalyzer {
  @override
  Future<ProductAnalysisResult> analyze({
    required List<String> imageUrls,
    String? listingId,
  }) async => _analysis(primaryColor: 'blue');

  @override
  Future<ProductAnalysisResult?> getAnalysis(String analysisId) async => null;
}

class _FakeRepository extends ListingPublishRepository {
  _FakeRepository()
    : super(sellerName: 'Seller', sellerHandle: '@seller', fallbackCity: '');

  int publishCalls = 0;

  @override
  String get sellerId => 'seller';

  @override
  Future<void> saveLocalDraft(ListingDraft draft) async {}

  @override
  Future<void> syncRemoteDraft(ListingDraft draft) async {}

  @override
  Future<void> publish(ListingDraft draft) async {
    publishCalls += 1;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    draft.status = ListingStatus.published;
  }
}
