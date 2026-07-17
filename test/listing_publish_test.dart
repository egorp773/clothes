import 'dart:async';

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

  test('publication taxonomy is grouped, complete and uses unique IDs', () {
    final grouped = ListingCatalogs.finalCategoryGroups
        .expand((group) => group.options)
        .map((option) => option.id)
        .toList();
    final flat = ListingCatalogs.finalCategories
        .map((option) => option.id)
        .toList();

    expect(grouped, flat);
    expect(flat.toSet(), hasLength(flat.length));
    for (final category in flat) {
      final attributes = ListingCatalogs.attributesFor(category);
      expect(attributes, isNotEmpty, reason: '$category has no schema');
      for (final attribute in attributes) {
        expect(
          attribute.options,
          isNotEmpty,
          reason: '$category.${attribute.id} has no options',
        );
      }
      final path = ListingCatalogs.legacyPathFor(category);
      expect(path.category, isNotEmpty, reason: '$category has no legacy path');
      expect(path.itemType, isNotEmpty, reason: '$category has no item type');
    }
  });

  test('knitwear and frequent garment aliases stay distinct', () {
    expect(ListingCatalogs.normalizeCategory('свитер'), 'sweater');
    expect(ListingCatalogs.normalizeCategory('sweater'), 'sweater');
    expect(ListingCatalogs.normalizeCategory('худи'), 'hoodie');
    expect(ListingCatalogs.normalizeCategory('блузка'), 'blouse');
    expect(ListingCatalogs.normalizeCategory('пуховик'), 'puffer');
    expect(ListingCatalogs.legacyPathFor('sweater').itemType, 'sweater');
  });

  test('jewelry receives relevant materials without clothing-only choices', () {
    final bracelet = ListingCatalogs.attributesFor('bracelet');
    final fields = bracelet.map((attribute) => attribute.id).toList();
    final materialIds = bracelet
        .singleWhere((attribute) => attribute.id == 'material')
        .options
        .map((option) => option.id)
        .toSet();

    expect(fields, ['material', 'style']);
    expect(materialIds, containsAll(['metal', 'steel', 'silver', 'gold']));
    expect(materialIds, isNot(contains('denim')));
    expect(materialIds, isNot(contains('cotton')));
  });

  test('all footwear categories use shoe sizes', () {
    for (final category in ['sneakers', 'boots', 'shoes', 'sandals', 'heels']) {
      expect(ListingCatalogs.isShoeCategory(category), isTrue);
      expect(
        ListingCatalogs.sizeOptionsFor(category),
        ListingCatalogs.shoeSizes,
      );
      expect(
        ListingCatalogs.sizeOptionsFor(category).map((option) => option.id),
        isNot(contains('m')),
      );
    }
    expect(
      ListingCatalogs.sizeOptionsFor('bracelet'),
      containsAll(ListingCatalogs.oneSizeOptions),
    );
  });

  test('typed display names do not collide across catalogs', () {
    expect(ListingCatalogs.categoryName('shoes'), 'Туфли');
    expect(ListingCatalogs.genderName('kids'), 'Детский');
    expect(
      ListingCatalogs.attributeValueName('collar', 'none'),
      'Без воротника',
    );
    expect(ListingCatalogs.attributeValueName('collar', 'shirt'), 'Рубашечный');
  });

  test(
    'catalog top and bottom helpers follow the expanded legacy hierarchy',
    () {
      expect(ListingCatalogs.isTopCategory('blouse'), isTrue);
      expect(ListingCatalogs.isTopCategory('sweater'), isTrue);
      expect(ListingCatalogs.isTopCategory('cardigan'), isTrue);
      expect(ListingCatalogs.isBottomCategory('joggers'), isTrue);
      expect(ListingCatalogs.isBottomCategory('leggings'), isTrue);
      expect(ListingCatalogs.isBottomCategory('shorts'), isTrue);
    },
  );

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
      expect(restored.defectsReviewed, isTrue);
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
    test('keeps analyzer white as the canonical publication color', () {
      final controller = _controller();
      controller.draft = ListingDraft.empty(sellerId: 'seller');

      controller.applyAnalysisResult(
        _analysis(
          primaryColor: 'white',
          secondaryColors: const ['gray', 'white'],
        ),
      );

      expect(controller.draft.primaryColor, 'white');
      expect(controller.draft.secondaryColors, ['gray']);
      expect(
        controller.draft.predictions['primary_color']?.predictedValue,
        'white',
      );
      controller.dispose();
    });

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

      controller.confirmSuggestion('material');
      controller.applyAnalysisResult(
        _analysis(primaryColor: 'blue', material: 'polyester'),
      );

      expect(controller.draft.material, 'cotton');
      expect(controller.draft.predictions['material']?.userConfirmed, isTrue);
      controller.dispose();
    });

    test('continuing review confirms visible relevant ML suggestions', () {
      final controller = _controller();
      controller.draft = ListingDraft.empty(sellerId: 'seller')
        ..normalizedCategory = 'hoodie';
      controller.applyAnalysisResult(
        _analysis(primaryColor: 'black', material: 'cotton'),
      );

      controller.confirmRequiredDetails();

      expect(
        controller.draft.predictions['normalized_category']?.userConfirmed,
        isTrue,
      );
      expect(
        controller.draft.predictions['primary_color']?.userConfirmed,
        isTrue,
      );
      expect(controller.draft.predictions['material']?.userConfirmed, isTrue);
      expect(controller.buildProduct(preview: true).material, 'cotton');
      controller.dispose();
    });

    test('buyer projection contains only explicitly reviewed ML values', () {
      final controller = _controller();
      controller.draft = ListingDraft.empty(sellerId: 'seller')
        ..normalizedCategory = 'hoodie';
      controller.applyAnalysisResult(
        _analysis(
          primaryColor: 'black',
          material: 'cotton',
          secondaryColors: const ['white'],
          description: 'Черновик описания',
        ),
      );

      var product = controller.buildProduct(preview: true);
      expect(product.material, isEmpty);
      expect(product.secondaryColors, isEmpty);
      expect(product.description, isEmpty);

      controller.confirmRequiredDetails();
      product = controller.buildProduct(preview: true);
      expect(product.material, 'cotton');
      expect(product.secondaryColors, ['white']);
      expect(product.description, isEmpty);

      controller.confirmBasicDetails();
      product = controller.buildProduct(preview: true);
      expect(product.material, 'cotton');
      expect(product.secondaryColors, ['white']);
      expect(product.description, 'Черновик описания');

      controller.skipSuggestion('material');
      controller.applyAnalysisResult(
        _analysis(primaryColor: 'blue', material: 'polyester'),
      );
      product = controller.buildProduct(preview: true);
      expect(product.material, isEmpty);
      expect(
        controller.draft.predictions['material']?.predictedValue,
        'polyester',
      );
      controller.dispose();
    });

    test('analysis suggests title but does not overwrite seller input', () {
      final controller = _controller();
      controller.draft = ListingDraft.empty(sellerId: 'seller');

      controller.applyAnalysisResult(
        _analysis(
          primaryColor: 'black',
          brand: 'nike',
          gender: 'male',
          suggestedSize: 'm',
          suggestedTitle: 'Футболка Nike',
        ),
      );

      expect(controller.draft.title, 'Футболка Nike');
      expect(controller.draft.brand, isEmpty);
      expect(controller.draft.size, isEmpty);
      expect(controller.draft.gender, isEmpty);

      controller.setTitle('Моя футболка');
      controller.applyAnalysisResult(
        _analysis(primaryColor: 'blue', suggestedTitle: 'Другое название'),
      );
      expect(controller.draft.title, 'Моя футболка');
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

    test('changing category clears or normalizes incompatible sizes', () {
      final controller = _controller();
      controller.draft = ListingDraft.empty(sellerId: 'seller')
        ..normalizedCategory = 't_shirt'
        ..size = 'm';

      controller.setAttribute('normalized_category', 'bracelet');
      expect(controller.draft.size, 'one_size');
      expect(controller.draft.category, 'jewelry');
      expect(controller.draft.itemType, 'bracelet');

      controller.setAttribute('normalized_category', 'sandals');
      expect(controller.draft.size, isEmpty);
      expect(controller.draft.category, 'shoes');

      controller.draft.size = '40';
      controller.setAttribute('normalized_category', 'sweater');
      expect(controller.draft.size, isEmpty);
      expect(controller.draft.itemType, 'sweater');

      controller.draft.size = '17 см';
      controller.setAttribute('normalized_category', 'bracelet');
      expect(controller.draft.size, '17 см');
      controller.dispose();
    });

    test(
      'protected canonical category keeps legacy path and title coherent',
      () {
        final controller = _controller();
        controller.draft = ListingDraft.empty(sellerId: 'seller');
        controller.setAttribute('normalized_category', 'sweater');

        controller.applyAnalysisResult(
          _analysis(
            primaryColor: 'black',
            itemType: 'hoodie',
            normalizedCategory: 'hoodie',
            suggestedTitle: 'Худи',
          ),
        );

        expect(controller.draft.normalizedCategory, 'sweater');
        expect(controller.draft.itemType, 'sweater');
        expect(controller.draft.subcategory, 'tops');
        expect(controller.draft.title, isEmpty);
        expect(
          controller.buildProduct(preview: true).category,
          contains('Свитер'),
        );
        controller.dispose();
      },
    );

    test('specific item type repairs a legacy collapsed category', () {
      final controller = _controller();
      controller.draft = ListingDraft.empty(sellerId: 'seller');

      controller.applyAnalysisResult(
        _analysis(
          primaryColor: 'white',
          itemType: 'sweater',
          normalizedCategory: 'hoodie',
          suggestedTitle: 'Свитер',
        ),
      );

      expect(controller.draft.normalizedCategory, 'sweater');
      expect(controller.draft.itemType, 'sweater');
      expect(controller.draft.title, 'Свитер');
      controller.dispose();
    });

    test('defect disclosure requires an explicit seller choice', () {
      final draft = _validDraft()
        ..defectsReviewed = false
        ..hasDefects = false
        ..defectDescription = '';
      expect(draft.validateAttributes(), contains('есть ли'));

      final controller = _controller()..draft = draft;
      controller.setHasDefects(false);
      expect(draft.validateAttributes(), isNull);
      controller.setHasDefects(true);
      expect(draft.validateAttributes(), contains('Опишите'));
      controller.setDefectDescription('Пятно на рукаве');
      expect(draft.validateAttributes(), isNull);
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

    test(
      'unexpected publish failure is explained and can be retried',
      () async {
        final repository = _RetryingPublishRepository();
        final controller = ListingPublishController(
          repository: repository,
          analyzer: _FakeAnalyzer(),
          sellerName: 'Seller',
          sellerHandle: '@seller',
        )..draft = _validDraft();

        await expectLater(
          controller.publish(),
          throwsA(
            isA<ListingPublishException>().having(
              (error) => error.userMessage,
              'userMessage',
              'Не удалось опубликовать объявление. Черновик сохранён',
            ),
          ),
        );
        expect(controller.isPublishing, isFalse);
        expect(controller.transientError, contains('Черновик сохранён'));

        final product = await controller.publish();
        expect(product.id, controller.draft.id);
        expect(repository.publishCalls, 2);
        controller.dispose();
      },
    );

    test(
      'removing an uploading photo cleans up a late remote upload',
      () async {
        final repository = _DelayedUploadRepository();
        final controller = ListingPublishController(
          repository: repository,
          analyzer: _FakeAnalyzer(),
          sellerName: 'Seller',
          sellerHandle: '@seller',
        );
        final photo = ListingPhoto(id: 'photo', localPath: '/tmp/photo.jpg');
        controller.draft = ListingDraft.empty(sellerId: 'seller')
          ..photos.add(photo);

        final upload = controller.retryPhotoUpload(photo);
        await repository.uploadStarted.future;
        await controller.removePhoto(photo);
        repository.finishUpload.complete();
        await upload;

        expect(controller.draft.photos, isEmpty);
        expect(repository.remoteDeletionCalls, 1);
        controller.dispose();
      },
    );

    test('offline photo upload becomes retryable and succeeds later', () async {
      final repository = _RetryUploadRepository();
      final controller = ListingPublishController(
        repository: repository,
        analyzer: _FakeAnalyzer(),
        sellerName: 'Seller',
        sellerHandle: '@seller',
      );
      final photo = ListingPhoto(id: 'photo', localPath: '/tmp/photo.jpg');
      controller.draft = ListingDraft.empty(sellerId: 'seller')
        ..photos.add(photo);

      await controller.retryPhotoUpload(photo);
      expect(photo.uploadStatus, ListingPhotoUploadStatus.failed);
      expect(controller.transientError, contains('восстановлении сети'));

      await controller.retryPhotoUpload(photo);
      expect(photo.uploadStatus, ListingPhotoUploadStatus.uploaded);
      expect(photo.remoteUrl, 'https://example.com/photo.jpg');
      expect(repository.uploadCalls, 2);
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
    ..defectsReviewed = true
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
  List<String> secondaryColors = const [],
  String? description,
  String? brand,
  String? gender,
  String? suggestedSize,
  String? suggestedTitle,
  String? itemType,
  String? normalizedCategory,
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
    itemType: AnalyzedField<String>(
      value: itemType,
      confidence: itemType == null ? 0 : 0.9,
      source: 'test',
    ),
    gender: AnalyzedField<String>(
      value: gender,
      confidence: gender == null ? 0 : 0.9,
      source: 'test',
    ),
    primaryColor: AnalyzedField<String>(
      value: primaryColor,
      confidence: 0.9,
      source: 'test',
    ),
    secondaryColors: secondaryColors
        .map(
          (value) => AnalyzedField<String>(
            value: value,
            confidence: 0.9,
            source: 'test',
          ),
        )
        .toList(),
    brand: AnalyzedField<String>(
      value: brand,
      confidence: brand == null ? 0 : 0.9,
      source: 'test',
    ),
    material: AnalyzedField<String>(
      value: material,
      confidence: material == null ? 0 : 0.9,
      source: 'test',
    ),
    pattern: empty,
    season: empty,
    style: empty,
    suggestedTitle: AnalyzedField<String>(
      value: suggestedTitle,
      confidence: suggestedTitle == null ? 0 : 0.9,
      source: 'test',
    ),
    suggestedDescription: AnalyzedField<String>(
      value: description,
      confidence: description == null ? 0 : 0.9,
      source: 'test',
    ),
    suggestedSize: AnalyzedField<String>(
      value: suggestedSize,
      confidence: suggestedSize == null ? 0 : 0.9,
      source: 'test',
    ),
    normalizedCategory: AnalyzedField<String>(
      value: normalizedCategory,
      confidence: normalizedCategory == null ? 0 : 0.9,
      source: 'test',
    ),
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

class _RetryingPublishRepository extends _FakeRepository {
  var _shouldFail = true;

  @override
  Future<void> publish(ListingDraft draft) async {
    publishCalls += 1;
    if (_shouldFail) {
      _shouldFail = false;
      throw StateError('network disconnected');
    }
    draft.status = ListingStatus.published;
  }
}

class _DelayedUploadRepository extends _FakeRepository {
  final uploadStarted = Completer<void>();
  final finishUpload = Completer<void>();
  int remoteDeletionCalls = 0;

  @override
  Future<void> ensureRemoteDraft(ListingDraft draft) async {}

  @override
  Future<bool> uploadPhoto(ListingDraft draft, ListingPhoto photo) async {
    if (!uploadStarted.isCompleted) uploadStarted.complete();
    await finishUpload.future;
    photo
      ..remoteUrl = 'https://example.com/${photo.id}.jpg'
      ..storagePath = 'users/seller/listings/${draft.id}/${photo.id}.jpg'
      ..uploadStatus = ListingPhotoUploadStatus.uploaded;
    return true;
  }

  @override
  Future<void> deletePhoto(ListingDraft draft, ListingPhoto photo) async {
    if (photo.remoteUrl.isNotEmpty) remoteDeletionCalls += 1;
  }
}

class _RetryUploadRepository extends _FakeRepository {
  int uploadCalls = 0;

  @override
  Future<void> ensureRemoteDraft(ListingDraft draft) async {}

  @override
  Future<bool> uploadPhoto(ListingDraft draft, ListingPhoto photo) async {
    uploadCalls += 1;
    if (uploadCalls == 1) return false;
    photo
      ..remoteUrl = 'https://example.com/photo.jpg'
      ..storagePath = 'users/seller/listings/${draft.id}/photo.jpg'
      ..uploadStatus = ListingPhotoUploadStatus.uploaded;
    return true;
  }
}
