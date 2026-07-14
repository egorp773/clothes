import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/product.dart';
import 'data/listing_catalogs.dart';
import 'data/listing_publish_repository.dart';
import 'models/listing_draft.dart';
import 'services/product_image_analyzer.dart';

class ListingPublishController extends ChangeNotifier {
  ListingPublishController({
    required this.repository,
    required this.analyzer,
    required this.sellerName,
    required this.sellerHandle,
    ImagePicker? imagePicker,
  }) : imagePicker = imagePicker ?? ImagePicker();

  final ListingPublishRepository repository;
  final ProductImageAnalyzer analyzer;
  final String sellerName;
  final String sellerHandle;
  final ImagePicker imagePicker;

  late ListingDraft draft;
  List<ListingAddress> savedAddresses = const [];
  bool isInitialized = false;
  bool hasRecoverableDraft = false;
  bool isPickingPhotos = false;
  bool isPublishing = false;
  bool isWaitingForAnalysis = false;
  String? transientError;

  ListingDeliveryDefaults _deliveryDefaults = const ListingDeliveryDefaults();
  Timer? _saveTimer;
  Timer? _retryTimer;
  Timer? _analysisPollTimer;
  Timer? _analysisRetryTimer;
  Future<void>? _analysisFuture;
  Future<Product>? _publishFuture;
  bool _disposed = false;
  bool _isRetrying = false;
  bool _analysisRestartRequested = false;
  int _analysisRetryCount = 0;

  bool get isAnalyzing =>
      draft.analysisStatus == ListingAnalysisStatus.processing;
  bool get canContinueFromPhotos => draft.photos.isNotEmpty;
  int get visibleStepNumber => switch (draft.currentStep) {
    ListingPublishStep.photos => 1,
    ListingPublishStep.basics => 2,
    ListingPublishStep.attributes => 3,
    ListingPublishStep.delivery => 4,
    ListingPublishStep.preview || ListingPublishStep.success => 5,
  };

  Future<void> initialize() async {
    _deliveryDefaults = await repository.loadDeliveryDefaults();
    savedAddresses = _deliveryDefaults.addresses;
    final drafts = await repository.loadLocalDrafts();
    if (drafts.isNotEmpty) {
      draft = drafts.first;
      hasRecoverableDraft = true;
    } else {
      draft = _newDraft();
      await repository.saveLocalDraft(draft);
    }
    _normalizeRecoveredDraft();
    _syncPhotoOrder();
    isInitialized = true;
    _safeNotify();
    await _recoverLostPickerData();
  }

  ListingDraft _newDraft() {
    final result = ListingDraft.empty(sellerId: repository.sellerId);
    final defaultAddress = _deliveryDefaults.addresses
        .where((address) => address.isDefault)
        .firstOrNull;
    if (defaultAddress != null) {
      result.shippingAddressId = defaultAddress.id;
      result.city = defaultAddress.city;
      result.shippingAddress = defaultAddress.address;
    } else {
      result.city = repository.fallbackCity;
    }
    result.deliveryMethods.addAll(
      _deliveryDefaults.deliveryMethods.isEmpty
          ? const ['cdek', 'yandex_delivery']
          : _deliveryDefaults.deliveryMethods,
    );
    return result;
  }

  Future<void> resumeDraft() async {
    hasRecoverableDraft = false;
    _safeNotify();
    for (final photo in draft.photos) {
      if (!photo.isUploaded) {
        photo.uploadStatus = ListingPhotoUploadStatus.pending;
        unawaited(_uploadPhoto(photo));
      }
    }
    if (draft.photos.isNotEmpty &&
        (draft.analysisStatus == ListingAnalysisStatus.pending ||
            draft.analysisStatus == ListingAnalysisStatus.processing)) {
      if (draft.analysisId.isNotEmpty) {
        _resumeAnalysisPolling();
      } else {
        _startAnalysis();
      }
    }
  }

  Future<void> createNewDraft() async {
    await flush();
    draft = _newDraft();
    hasRecoverableDraft = false;
    await repository.saveLocalDraft(draft);
    _safeNotify();
  }

  Future<void> deleteRecoverableDraft() async {
    await repository.deleteDraft(draft);
    draft = _newDraft();
    hasRecoverableDraft = false;
    await repository.saveLocalDraft(draft);
    _safeNotify();
  }

  Future<void> pickFromGallery() async {
    final remaining = 8 - draft.photos.length;
    if (remaining <= 0 || isPickingPhotos) return;
    isPickingPhotos = true;
    transientError = null;
    _safeNotify();
    try {
      final files = await imagePicker.pickMultiImage(
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 88,
        limit: remaining,
      );
      await addPickedPhotos(files.take(remaining));
    } catch (error, stackTrace) {
      debugPrint('Gallery picker error: $error\n$stackTrace');
      transientError = 'Не удалось открыть галерею';
    } finally {
      isPickingPhotos = false;
      _safeNotify();
    }
  }

  Future<void> takePhoto() async {
    if (draft.photos.length >= 8 || isPickingPhotos) return;
    isPickingPhotos = true;
    transientError = null;
    _safeNotify();
    try {
      final file = await imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 88,
      );
      if (file != null) await addPickedPhotos([file]);
    } catch (error, stackTrace) {
      debugPrint('Camera picker error: $error\n$stackTrace');
      transientError = 'Не удалось открыть камеру';
    } finally {
      isPickingPhotos = false;
      _safeNotify();
    }
  }

  @visibleForTesting
  Future<void> addPickedPhotos(Iterable<XFile> files) async {
    final wasEmpty = draft.photos.isEmpty;
    final initialPhotoCount = draft.photos.length;
    for (final source in files) {
      if (draft.photos.length >= 8) break;
      try {
        final photo = await repository.stagePhoto(draft: draft, source: source);
        photo
          ..position = draft.photos.length
          ..role = draft.photos.isEmpty ? 'main' : 'gallery';
        draft.photos.add(photo);
        if (draft.mainPhotoId.isEmpty) draft.mainPhotoId = photo.id;
        await repository.saveLocalDraft(draft);
        _safeNotify();
        unawaited(_uploadPhoto(photo));
      } on ListingPublishException catch (error) {
        transientError = error.userMessage;
      }
    }
    if (wasEmpty && draft.photos.isNotEmpty) {
      // The analyzer persists its status against the listing id. Ensure the
      // additive draft row exists before starting analysis, otherwise a fast
      // analyzer request can race the product upsert and lose durable status.
      await repository.ensureRemoteDraft(draft);
      _startAnalysis();
    } else if (draft.photos.length > initialPhotoCount) {
      _requestAnalysisRestart();
    }
    _markChanged();
  }

  Future<void> _uploadPhoto(ListingPhoto photo) async {
    photo.uploadStatus = ListingPhotoUploadStatus.uploading;
    _safeNotify();
    await repository.ensureRemoteDraft(draft);
    final didUpload = await repository.uploadPhoto(draft, photo);
    if (!didUpload) {
      transientError = 'Фото сохранено. Загрузим при восстановлении сети';
      _scheduleRetry();
    } else if (draft.photos.every((item) => item.isUploaded)) {
      _retryTimer?.cancel();
    }
    if (didUpload && draft.analysisStatus == ListingAnalysisStatus.failed) {
      _startAnalysis();
    }
    await repository.saveLocalDraft(draft);
    _safeNotify();
  }

  Future<void> retryPhotoUpload(ListingPhoto photo) => _uploadPhoto(photo);

  Future<void> retryPendingSync() async {
    if (!isInitialized ||
        _isRetrying ||
        draft.status == ListingStatus.published) {
      return;
    }
    _isRetrying = true;
    try {
      await repository.ensureRemoteDraft(draft);
      for (final photo in draft.photos.where((item) => !item.isUploaded)) {
        if (photo.uploadStatus == ListingPhotoUploadStatus.uploading) continue;
        await _uploadPhoto(photo);
      }
      await repository.syncRemoteDraft(draft);
      if (draft.photos.isNotEmpty &&
          draft.analysisStatus == ListingAnalysisStatus.failed) {
        _startAnalysis();
      }
    } finally {
      _isRetrying = false;
      if (draft.photos.any((item) => !item.isUploaded)) _scheduleRetry();
    }
  }

  Future<void> removePhoto(ListingPhoto photo) async {
    final removedMainPhoto = draft.mainPhotoId == photo.id;
    draft.photos.removeWhere((item) => item.id == photo.id);
    if (removedMainPhoto) {
      draft.mainPhotoId = draft.photos.firstOrNull?.id ?? '';
    }
    _syncPhotoOrder();
    _safeNotify();
    await repository.deletePhoto(draft, photo);
    _markChanged();
    if (removedMainPhoto && draft.photos.isNotEmpty) _requestAnalysisRestart();
  }

  void reorderPhotos(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    final photo = draft.photos.removeAt(oldIndex);
    draft.photos.insert(newIndex, photo);
    draft.mainPhotoId = draft.photos.firstOrNull?.id ?? '';
    _syncPhotoOrder();
    _markChanged();
  }

  void setMainPhoto(String photoId) {
    if (draft.mainPhotoId == photoId) return;
    final index = draft.photos.indexWhere((photo) => photo.id == photoId);
    if (index == -1) return;
    final photo = draft.photos.removeAt(index);
    draft.photos.insert(0, photo);
    draft.mainPhotoId = photoId;
    _syncPhotoOrder();
    _markChanged();
    _requestAnalysisRestart();
  }

  void setTitle(String value) {
    draft.title = value;
    draft.titleWasEdited = true;
    _markChanged();
  }

  void setPrice(String value) {
    draft.price = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    _markChanged();
  }

  void setDescription(String value) {
    draft.description = value;
    draft.descriptionWasEdited = true;
    _markChanged();
  }

  void setSize(String value) {
    draft.size = value;
    _setManualPrediction('size', value);
    _markChanged();
  }

  void setCondition(String value) {
    draft.condition = value;
    _setManualPrediction('condition', value);
    _markChanged();
  }

  void setAttribute(String field, String value) {
    switch (field) {
      case 'section':
        draft.section = value;
      case 'category':
        if (draft.category != value) {
          draft.category = value;
          draft.subcategory = '';
          draft.itemType = '';
        }
      case 'subcategory':
        if (draft.subcategory != value) {
          draft.subcategory = value;
          draft.itemType = '';
        }
      case 'item_type':
        draft.itemType = value;
      case 'normalized_category':
        final normalized = ListingCatalogs.normalizeCategory(value);
        if (normalized.isEmpty) return;
        if (draft.normalizedCategory != normalized) {
          draft.normalizedCategory = normalized;
          _applyLegacyCategory(normalized);
          final allowed = ListingCatalogs.attributesFor(
            normalized,
          ).map((definition) => definition.id).toSet();
          draft.categoryAttributes.removeWhere(
            (key, _) => !allowed.contains(key),
          );
        }
      case 'gender':
        draft.gender = value;
        draft.section = switch (value) {
          'female' => 'women',
          'male' => 'men',
          'kids' => 'kids',
          'unisex' => 'unisex',
          _ => draft.section,
        };
      case 'primary_color':
        draft.primaryColor = value;
      case 'brand':
        draft.brand = value;
      case 'material':
        draft.material = value;
      case 'pattern':
        draft.pattern = value;
      case 'season':
        draft.season = value;
      case 'style':
        draft.style = value;
      case 'fit':
        draft.fit = value;
      case 'sleeve_length':
        draft.sleeveLength = value;
      case 'closure':
        draft.closure = value;
      case 'collar':
        draft.collar = value;
      case 'rise':
        draft.rise = value;
      default:
        return;
    }
    if (const {
      'material',
      'pattern',
      'season',
      'style',
      'fit',
      'sleeve_length',
      'closure',
      'collar',
      'rise',
    }.contains(field)) {
      if (value.isEmpty) {
        draft.categoryAttributes.remove(field);
      } else {
        draft.categoryAttributes[field] = value;
      }
    }
    final prediction = draft.predictions.putIfAbsent(
      field,
      () => ListingFieldPrediction(fieldName: field),
    );
    prediction.confirmedValue = value;
    prediction.wasEdited = true;
    prediction.userConfirmed = true;
    prediction.source = 'user';
    prediction.updatedAt = DateTime.now().toUtc();
    _markChanged();
  }

  void setSecondaryColors(List<String> values) {
    draft.secondaryColors
      ..clear()
      ..addAll(values.where((value) => value != draft.primaryColor));
    final prediction = draft.predictions.putIfAbsent(
      'secondary_colors',
      () => ListingFieldPrediction(fieldName: 'secondary_colors'),
    );
    prediction.confirmedValue = draft.secondaryColors.join(',');
    prediction.wasEdited = true;
    prediction.userConfirmed = true;
    prediction.source = 'user';
    prediction.updatedAt = DateTime.now().toUtc();
    _markChanged();
  }

  void setHasDefects(bool value) {
    draft.hasDefects = value;
    if (!value) draft.defectDescription = '';
    _markChanged();
  }

  void setDefectDescription(String value) {
    draft.defectDescription = value;
    _markChanged();
  }

  void confirmRelevantAttributes() {
    for (final definition in ListingCatalogs.attributesFor(
      draft.normalizedCategory,
    )) {
      final value = _attributeValue(definition.id);
      if (value.isEmpty) continue;
      final prediction = draft.predictions.putIfAbsent(
        definition.id,
        () => ListingFieldPrediction(
          fieldName: definition.id,
          confirmedValue: value,
          source: 'user',
          userConfirmed: true,
        ),
      );
      prediction
        ..confirmedValue = value
        ..userConfirmed = true
        ..updatedAt = DateTime.now().toUtc();
    }
    _markChanged();
  }

  void selectAddress(ListingAddress address) {
    draft.shippingAddressId = address.id;
    draft.city = address.city;
    draft.shippingAddress = address.address;
    draft.saveAddressAsDefault = address.isDefault;
    _markChanged();
  }

  void setCity(String value) {
    draft.city = value;
    draft.shippingAddressId = '';
    _markChanged();
  }

  void setShippingAddress(String value) {
    draft.shippingAddress = value;
    draft.shippingAddressId = '';
    _markChanged();
  }

  void setSaveAddressAsDefault(bool value) {
    draft.saveAddressAsDefault = value;
    _markChanged();
  }

  void toggleDeliveryMethod(String method) {
    if (draft.deliveryMethods.contains(method)) {
      draft.deliveryMethods.remove(method);
    } else {
      draft.deliveryMethods.add(method);
    }
    _markChanged();
  }

  void goToStep(ListingPublishStep step) {
    draft.currentStep = step;
    _markChanged();
  }

  Future<void> waitBrieflyForAnalysis() async {
    final future = _analysisFuture;
    if (future == null || !isAnalyzing) return;
    isWaitingForAnalysis = true;
    _safeNotify();
    await Future.any<void>([
      future,
      Future<void>.delayed(const Duration(seconds: 2)),
    ]);
    isWaitingForAnalysis = false;
    _safeNotify();
  }

  void _startAnalysis() {
    if (_analysisFuture != null && isAnalyzing) return;
    if (draft.photos.isEmpty) return;
    _analysisPollTimer?.cancel();
    transientError = null;
    draft.analysisStatus = ListingAnalysisStatus.processing;
    _markChanged();
    final mainPhoto = draft.mainPhoto;
    final orderedPhotos = [
      ?mainPhoto,
      ...draft.photos.where((photo) => photo.id != mainPhoto?.id),
    ];
    final sources = orderedPhotos
        .map((photo) => photo.displaySource)
        .where((source) => source.isNotEmpty)
        .toList();
    _analysisFuture = _runAnalysis(sources);
  }

  void _requestAnalysisRestart() {
    if (isAnalyzing) {
      _analysisRestartRequested = true;
      return;
    }
    _startAnalysis();
  }

  Future<void> _runAnalysis(List<String> sources) async {
    try {
      final result = await analyzer.analyze(
        imageUrls: sources,
        listingId: draft.id,
      );
      _applyAnalysis(result);
      _analysisRetryCount = 0;
      draft.analysisId = result.analysisId ?? '';
      draft.analysisStartedAt = DateTime.now().toUtc();
      if (result.enrichmentStatus == 'completed') {
        draft.analysisStatus = ListingAnalysisStatus.completed;
      } else {
        draft.analysisStatus = ListingAnalysisStatus.processing;
        _resumeAnalysisPolling();
      }
    } catch (error, stackTrace) {
      draft.analysisStatus = ListingAnalysisStatus.failed;
      transientError =
          'Автоанализ сейчас недоступен. Можно заполнить объявление вручную — публикация не заблокирована.';
      debugPrint('Product image analysis failed: $error\n$stackTrace');
      if (_analysisRetryCount < 5 && !_disposed) {
        _analysisRetryCount += 1;
        _analysisRetryTimer?.cancel();
        _analysisRetryTimer = Timer(const Duration(seconds: 6), () {
          if (!_disposed &&
              draft.analysisStatus == ListingAnalysisStatus.failed) {
            _startAnalysis();
          }
        });
      }
    } finally {
      _analysisFuture = null;
      _markChanged();
      await flush();
      if (_analysisRestartRequested && !_disposed) {
        _analysisRestartRequested = false;
        _startAnalysis();
      }
    }
  }

  void _resumeAnalysisPolling() {
    _analysisPollTimer?.cancel();
    final started = draft.analysisStartedAt ?? DateTime.now().toUtc();
    draft.analysisStartedAt ??= started;
    _analysisPollTimer = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) async {
      if (_disposed || draft.analysisId.isEmpty) {
        timer.cancel();
        return;
      }
      if (DateTime.now().toUtc().difference(started) >
          const Duration(seconds: 90)) {
        draft.analysisStatus = ListingAnalysisStatus.failed;
        timer.cancel();
        _markChanged();
        return;
      }
      final result = await analyzer.getAnalysis(draft.analysisId);
      if (result == null) return;
      _applyAnalysis(result);
      switch (result.enrichmentStatus) {
        case 'completed':
          draft.analysisStatus = ListingAnalysisStatus.completed;
          timer.cancel();
        case 'failed':
          draft.analysisStatus = ListingAnalysisStatus.failed;
          timer.cancel();
        default:
          draft.analysisStatus = ListingAnalysisStatus.processing;
      }
      _markChanged();
      await flush();
    });
  }

  void _applyAnalysis(ProductAnalysisResult result) {
    final normalizedFromAnalysis = ListingCatalogs.normalizeCategory(
      result.normalizedCategory.value ?? result.itemType.value ?? '',
    );
    if (normalizedFromAnalysis.isNotEmpty) {
      _mergePrediction(
        'normalized_category',
        AnalyzedField<String>(
          value: normalizedFromAnalysis,
          confidence: result.normalizedCategory.hasValue
              ? result.normalizedCategory.confidence
              : result.itemType.confidence,
          source: result.normalizedCategory.hasValue
              ? result.normalizedCategory.source
              : result.itemType.source,
          modelVersion: result.normalizedCategory.hasValue
              ? result.normalizedCategory.modelVersion
              : result.itemType.modelVersion,
        ),
        (value) {
          draft.normalizedCategory = value;
          _applyLegacyCategory(value);
        },
      );
    }
    _mergePrediction(
      'section',
      result.section,
      (value) => draft.section = value,
    );
    _mergePrediction(
      'category',
      result.category,
      (value) => draft.category = value,
    );
    final predictedSubcategory = result.subcategory.value;
    final subcategoryIsCompatible =
        predictedSubcategory != null &&
        (ListingCatalogs.subcategoriesByCategory[draft.category] ?? const [])
            .any((option) => option.id == predictedSubcategory);
    if (subcategoryIsCompatible) {
      _mergePrediction(
        'subcategory',
        result.subcategory,
        (value) => draft.subcategory = value,
      );
    } else {
      _recordPredictionOnly('subcategory', result.subcategory);
    }
    final predictedItemType = result.itemType.value;
    final itemTypeIsCompatible =
        predictedItemType != null &&
        (ListingCatalogs.itemTypesBySubcategory[draft.subcategory] ?? const [])
            .any((option) => option.id == predictedItemType);
    if (itemTypeIsCompatible) {
      _mergePrediction(
        'item_type',
        result.itemType,
        (value) => draft.itemType = value,
      );
    } else {
      _recordPredictionOnly('item_type', result.itemType);
    }
    _mergePrediction('gender', result.gender, (value) => draft.gender = value);
    _mergePrediction(
      'primary_color',
      result.primaryColor,
      (value) => draft.primaryColor = value,
    );
    if (result.brand.value == 'other_brand') {
      _recordPredictionOnly('brand', result.brand);
    } else {
      _mergePrediction('brand', result.brand, (value) => draft.brand = value);
    }
    _mergePrediction(
      'material',
      result.material,
      (value) => draft.material = value,
    );
    _mergePrediction(
      'pattern',
      result.pattern,
      (value) => draft.pattern = value,
    );
    _mergePrediction('season', result.season, (value) => draft.season = value);
    _mergePrediction('style', result.style, (value) => draft.style = value);
    _mergePrediction('fit', result.fit, (value) => draft.fit = value);
    _mergePrediction(
      'sleeve_length',
      result.sleeveLength,
      (value) => draft.sleeveLength = value,
    );
    _mergePrediction(
      'closure',
      result.closure,
      (value) => draft.closure = value,
    );
    _mergePrediction('collar', result.collar, (value) => draft.collar = value);
    _mergePrediction('rise', result.rise, (value) => draft.rise = value);

    for (final definition in ListingCatalogs.attributesFor(
      draft.normalizedCategory,
    )) {
      final value = _attributeValue(definition.id);
      if (value.isNotEmpty) draft.categoryAttributes[definition.id] = value;
    }

    final secondaryEntry = draft.predictions['secondary_colors'];
    final predictedSecondary = result.secondaryColors
        .map((field) => field.value)
        .whereType<String>()
        .toList();
    if (predictedSecondary.isNotEmpty && secondaryEntry?.wasEdited == true) {
      secondaryEntry!
        ..predictedValue = predictedSecondary.join(',')
        ..confidence = result.secondaryColors
            .map((field) => field.confidence)
            .fold<double>(1, (a, b) => a < b ? a : b)
        ..modelVersion = result.secondaryColors.first.modelVersion
        ..updatedAt = DateTime.now().toUtc();
    } else if (predictedSecondary.isNotEmpty) {
      draft.secondaryColors
        ..clear()
        ..addAll(
          predictedSecondary.where((value) => value != draft.primaryColor),
        );
      draft.predictions['secondary_colors'] = ListingFieldPrediction(
        fieldName: 'secondary_colors',
        predictedValue: predictedSecondary.join(','),
        confidence: result.secondaryColors
            .map((field) => field.confidence)
            .fold<double>(1, (a, b) => a < b ? a : b),
        source: result.secondaryColors.first.source,
        modelVersion: result.secondaryColors.first.modelVersion,
      );
    }

    final suggestedTitle = result.suggestedTitle.value?.trim() ?? '';
    if (!draft.titleWasEdited &&
        draft.title.trim().isEmpty &&
        result.suggestedTitle.confidence >= 0.45 &&
        suggestedTitle.isNotEmpty) {
      draft.title = suggestedTitle;
    }
    final suggestedDescription =
        result.suggestedDescription.value?.trim() ?? '';
    if (!draft.descriptionWasEdited &&
        draft.description.trim().isEmpty &&
        result.suggestedDescription.confidence >= 0.45 &&
        suggestedDescription.isNotEmpty) {
      draft.description = suggestedDescription;
    }
    final suggestedSize = result.suggestedSize.value?.trim() ?? '';
    if (draft.size.isEmpty &&
        result.suggestedSize.confidence >= 0.65 &&
        suggestedSize.isNotEmpty) {
      draft.size = suggestedSize;
    }
  }

  @visibleForTesting
  void applyAnalysisResult(ProductAnalysisResult result) {
    _applyAnalysis(result);
  }

  void _mergePrediction(
    String field,
    AnalyzedField<String> analyzed,
    ValueChanged<String> apply,
  ) {
    final previous = draft.predictions[field];
    final value = analyzed.value;
    if (previous?.isProtected == true) {
      previous!
        ..predictedValue = value
        ..confidence = analyzed.confidence
        ..modelVersion = analyzed.modelVersion
        ..updatedAt = DateTime.now().toUtc();
      return;
    }
    draft.predictions[field] = ListingFieldPrediction(
      fieldName: field,
      predictedValue: value,
      confidence: analyzed.confidence,
      source: analyzed.source,
      modelVersion: analyzed.modelVersion,
    );
    if (value != null && value.isNotEmpty) apply(value);
  }

  void _recordPredictionOnly(String field, AnalyzedField<String> analyzed) {
    final previous = draft.predictions[field];
    if (previous?.isProtected == true) {
      previous!
        ..predictedValue = analyzed.value
        ..confidence = analyzed.confidence
        ..modelVersion = analyzed.modelVersion
        ..updatedAt = DateTime.now().toUtc();
      return;
    }
    draft.predictions[field] = ListingFieldPrediction(
      fieldName: field,
      predictedValue: analyzed.value,
      confidence: analyzed.confidence,
      source: analyzed.source,
      modelVersion: analyzed.modelVersion,
    );
  }

  ListingFieldPrediction? predictionFor(String field) =>
      draft.predictions[field];

  void _setManualPrediction(String field, String value) {
    final prediction = draft.predictions.putIfAbsent(
      field,
      () => ListingFieldPrediction(fieldName: field),
    );
    prediction
      ..confirmedValue = value
      ..source = 'user'
      ..wasEdited = true
      ..userConfirmed = true
      ..updatedAt = DateTime.now().toUtc();
  }

  void _syncPhotoOrder() {
    for (var index = 0; index < draft.photos.length; index++) {
      draft.photos[index]
        ..position = index
        ..role = index == 0 ? 'main' : 'gallery';
    }
  }

  void _normalizeRecoveredDraft() {
    final normalized = ListingCatalogs.normalizeCategory(
      draft.normalizedCategory.isNotEmpty
          ? draft.normalizedCategory
          : draft.itemType,
    );
    if (normalized.isEmpty) return;
    draft.normalizedCategory = normalized;
    _applyLegacyCategory(normalized);
    for (final definition in ListingCatalogs.attributesFor(normalized)) {
      final value = _attributeValue(definition.id);
      if (value.isNotEmpty) draft.categoryAttributes[definition.id] = value;
    }
  }

  void _applyLegacyCategory(String normalized) {
    final legacy = switch (normalized) {
      't_shirt' => ('clothing', 'tops', 'tshirt'),
      'hoodie' => ('clothing', 'tops', 'hoodie'),
      'shirt' => ('clothing', 'tops', 'shirt'),
      'jacket' => ('clothing', 'outerwear', 'jacket'),
      'jeans' => ('clothing', 'bottoms', 'jeans'),
      'trousers' => ('clothing', 'bottoms', 'trousers'),
      'dress' => ('clothing', 'dresses', 'dress'),
      'skirt' => ('clothing', 'bottoms', 'skirt'),
      'sneakers' => ('shoes', 'shoes_all', 'sneakers'),
      'boots' => ('shoes', 'shoes_all', 'boots'),
      'bag' => ('accessories', 'accessories_all', 'bag'),
      'accessory' => ('accessories', 'accessories_all', 'accessory'),
      _ => ('', '', ''),
    };
    draft
      ..category = legacy.$1
      ..subcategory = legacy.$2
      ..itemType = legacy.$3;
  }

  String _attributeValue(String field) => switch (field) {
    'material' => draft.material,
    'pattern' => draft.pattern,
    'season' => draft.season,
    'style' => draft.style,
    'fit' => draft.fit,
    'sleeve_length' => draft.sleeveLength,
    'closure' => draft.closure,
    'collar' => draft.collar,
    'rise' => draft.rise,
    _ => draft.categoryAttributes[field] ?? '',
  };

  Future<Product> publish() {
    final inFlight = _publishFuture;
    if (inFlight != null) return inFlight;
    final completer = _publishOnce();
    _publishFuture = completer;
    return completer;
  }

  Future<Product> _publishOnce() async {
    if (draft.status == ListingStatus.published) return buildProduct();
    isPublishing = true;
    transientError = null;
    _safeNotify();
    try {
      await flush();
      await repository.publish(draft);
      draft.currentStep = ListingPublishStep.success;
      return buildProduct();
    } on ListingPublishException catch (error) {
      transientError = error.userMessage;
      rethrow;
    } finally {
      isPublishing = false;
      _safeNotify();
      if (draft.status != ListingStatus.published) _publishFuture = null;
    }
  }

  Product buildProduct({bool preview = false}) {
    final urls = preview
        ? draft.photos
              .map((photo) => photo.displaySource)
              .toList(growable: false)
        : draft.uploadedImageUrls;
    final mainPhoto = draft.mainPhoto;
    final image = preview
        ? (mainPhoto?.displaySource ?? (urls.firstOrNull ?? ''))
        : (mainPhoto?.remoteUrl.isNotEmpty == true
              ? mainPhoto!.remoteUrl
              : (urls.firstOrNull ?? ''));
    final colorName = ListingCatalogs.nameOf(draft.primaryColor);
    return Product(
      id: draft.id,
      title: draft.title.trim(),
      detailTitle: draft.title.trim(),
      description: draft.description.trim(),
      price: '${_formatPrice(draft.price)} ₽',
      detailPrice: draft.price.toString(),
      priceValue: draft.price,
      image: image,
      images: urls,
      category: ListingCatalogs.nameOf(draft.normalizedCategory),
      categoryId: draft.category,
      brand: ListingCatalogs.nameOf(draft.brand),
      size: ListingCatalogs.nameOf(draft.size),
      color: colorName,
      primaryColor: draft.primaryColor,
      condition: ListingCatalogs.nameOf(draft.condition),
      location: draft.city,
      city: draft.city,
      ownerId: repository.sellerId,
      sellerName: sellerName,
      sellerHandle: sellerHandle,
      dotsOnDark: !const {
        'white',
        'beige',
        'yellow',
      }.contains(draft.primaryColor),
      status: 'published',
      section: draft.section,
      subcategory: draft.subcategory,
      itemType: draft.itemType,
      gender: draft.gender,
      secondaryColors: List.unmodifiable(draft.secondaryColors),
      material: draft.material,
      pattern: draft.pattern,
      season: draft.season,
      style: draft.style,
      fit: draft.fit,
      sleeveLength: draft.sleeveLength,
      closure: draft.closure,
      shippingAddressId: draft.shippingAddressId,
      shippingAddress: draft.shippingAddress,
      deliveryMethods: List.unmodifiable(draft.deliveryMethods),
      mainImage: image,
      publishedAt: DateTime.now().toUtc(),
      analysisStatus: draft.analysisStatus.value,
      normalizedCategory: draft.normalizedCategory,
      normalizedBrand: draft.brand,
      audience: draft.gender,
      hasDefects: draft.hasDefects,
      defectsDescription: draft.defectDescription.trim(),
      categoryAttributes: Map.unmodifiable(draft.categoryAttributes),
      enrichmentStatus: draft.analysisStatus == ListingAnalysisStatus.completed
          ? 'pending'
          : 'enrichment_pending',
    );
  }

  void clearTransientError() {
    transientError = null;
    _safeNotify();
  }

  void _markChanged() {
    draft.updatedAt = DateTime.now().toUtc();
    _safeNotify();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_persist());
    });
  }

  void _scheduleRetry() {
    if (_disposed || _retryTimer?.isActive == true) return;
    _retryTimer = Timer(const Duration(seconds: 12), () {
      unawaited(retryPendingSync());
    });
  }

  Future<void> _persist() async {
    if (draft.status == ListingStatus.published) return;
    await repository.saveLocalDraft(draft);
    await repository.syncRemoteDraft(draft);
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    if (draft.status == ListingStatus.published) return;
    await _persist();
  }

  Future<void> _recoverLostPickerData() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final response = await imagePicker.retrieveLostData();
      if (!response.isEmpty && response.files != null) {
        await addPickedPhotos(response.files!);
      }
    } catch (error) {
      debugPrint('Lost picker data recovery error: $error');
    }
  }

  String _formatPrice(int value) {
    final digits = value.toString();
    return digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    _retryTimer?.cancel();
    _analysisPollTimer?.cancel();
    _analysisRetryTimer?.cancel();
    super.dispose();
  }
}
