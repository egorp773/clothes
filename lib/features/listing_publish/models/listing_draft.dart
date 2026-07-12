import 'package:uuid/uuid.dart';

enum ListingStatus { draft, processing, ready, published, archived, sold }

enum ListingAnalysisStatus { pending, processing, completed, failed }

enum ListingPublishStep {
  photos,
  basics,
  attributes,
  delivery,
  preview,
  success,
}

enum ListingPhotoUploadStatus { pending, uploading, uploaded, failed }

extension ListingStatusValue on ListingStatus {
  String get value => name;

  static ListingStatus parse(Object? value) => ListingStatus.values.firstWhere(
    (item) => item.name == value,
    orElse: () => ListingStatus.draft,
  );
}

extension ListingAnalysisStatusValue on ListingAnalysisStatus {
  String get value => name;

  static ListingAnalysisStatus parse(Object? value) =>
      ListingAnalysisStatus.values.firstWhere(
        (item) => item.name == value,
        orElse: () => ListingAnalysisStatus.pending,
      );
}

class ListingPhoto {
  ListingPhoto({
    required this.id,
    required this.localPath,
    this.remoteUrl = '',
    this.storagePath = '',
    this.uploadStatus = ListingPhotoUploadStatus.pending,
  });

  final String id;
  final String localPath;
  String remoteUrl;
  String storagePath;
  ListingPhotoUploadStatus uploadStatus;

  String get displaySource => remoteUrl.isNotEmpty ? remoteUrl : localPath;
  bool get isUploaded => remoteUrl.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'local_path': localPath,
    'remote_url': remoteUrl,
    'storage_path': storagePath,
    'upload_status': uploadStatus.name,
  };

  factory ListingPhoto.fromJson(Map<String, dynamic> json) => ListingPhoto(
    id: json['id'] as String? ?? const Uuid().v4(),
    localPath: json['local_path'] as String? ?? '',
    remoteUrl: json['remote_url'] as String? ?? '',
    storagePath: json['storage_path'] as String? ?? '',
    uploadStatus: ListingPhotoUploadStatus.values.firstWhere(
      (value) => value.name == json['upload_status'],
      orElse: () => (json['remote_url'] as String? ?? '').isNotEmpty
          ? ListingPhotoUploadStatus.uploaded
          : ListingPhotoUploadStatus.pending,
    ),
  );
}

class ListingFieldPrediction {
  ListingFieldPrediction({
    required this.fieldName,
    this.predictedValue,
    this.confirmedValue,
    this.confidence = 0,
    this.source = 'manual',
    this.wasEdited = false,
  });

  final String fieldName;
  String? predictedValue;
  String? confirmedValue;
  double confidence;
  String source;
  bool wasEdited;

  String? get effectiveValue => confirmedValue ?? predictedValue;
  bool get needsReview =>
      predictedValue != null && predictedValue!.isNotEmpty && confidence < 0.65;

  Map<String, dynamic> toJson() => {
    'field_name': fieldName,
    'predicted_value': predictedValue,
    'confirmed_value': confirmedValue,
    'confidence': confidence,
    'source': source,
    'was_edited': wasEdited,
  };

  factory ListingFieldPrediction.fromJson(Map<String, dynamic> json) =>
      ListingFieldPrediction(
        fieldName: json['field_name'] as String? ?? '',
        predictedValue: json['predicted_value'] as String?,
        confirmedValue: json['confirmed_value'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        source: json['source'] as String? ?? 'manual',
        wasEdited: json['was_edited'] as bool? ?? false,
      );
}

class ListingAddress {
  const ListingAddress({
    required this.id,
    required this.city,
    required this.address,
    this.isDefault = false,
  });

  final String id;
  final String city;
  final String address;
  final bool isDefault;

  String get label => address.isEmpty ? city : '$city, $address';

  Map<String, dynamic> toJson() => {
    'id': id,
    'city': city,
    'address': address,
    'is_default': isDefault,
  };

  factory ListingAddress.fromJson(Map<String, dynamic> json) => ListingAddress(
    id: json['id'] as String? ?? const Uuid().v4(),
    city: json['city'] as String? ?? '',
    address: json['address'] as String? ?? '',
    isDefault: json['is_default'] as bool? ?? false,
  );
}

class ListingDraft {
  ListingDraft({
    required this.id,
    required this.sellerId,
    required this.createdAt,
    required this.updatedAt,
    this.status = ListingStatus.draft,
    this.analysisStatus = ListingAnalysisStatus.pending,
    this.currentStep = ListingPublishStep.photos,
  });

  factory ListingDraft.empty({required String sellerId}) {
    final now = DateTime.now().toUtc();
    return ListingDraft(
      id: const Uuid().v4(),
      sellerId: sellerId,
      createdAt: now,
      updatedAt: now,
    );
  }

  final String id;
  final String sellerId;
  DateTime createdAt;
  DateTime updatedAt;
  ListingStatus status;
  ListingAnalysisStatus analysisStatus;
  String analysisId = '';
  DateTime? analysisStartedAt;
  ListingPublishStep currentStep;

  final List<ListingPhoto> photos = [];
  String mainPhotoId = '';

  String title = '';
  bool titleWasEdited = false;
  int price = 0;
  String description = '';
  bool descriptionWasEdited = false;
  String size = '';
  String condition = '';

  String section = '';
  String category = '';
  String subcategory = '';
  String itemType = '';
  String gender = '';
  String primaryColor = '';
  final List<String> secondaryColors = [];
  String brand = '';
  String material = '';
  String pattern = '';
  String season = '';
  String style = '';
  String fit = '';
  String sleeveLength = '';
  String closure = '';

  String city = '';
  String shippingAddressId = '';
  String shippingAddress = '';
  bool saveAddressAsDefault = false;
  final List<String> deliveryMethods = [];

  final Map<String, ListingFieldPrediction> predictions = {};

  List<String> get uploadedImageUrls => photos
      .where((photo) => photo.remoteUrl.isNotEmpty)
      .map((photo) => photo.remoteUrl)
      .toList(growable: false);

  ListingPhoto? get mainPhoto {
    if (photos.isEmpty) return null;
    return photos.firstWhere(
      (photo) => photo.id == mainPhotoId,
      orElse: () => photos.first,
    );
  }

  String get mainImageUrl {
    final main = mainPhoto;
    return main?.remoteUrl.isNotEmpty == true
        ? main!.remoteUrl
        : (main?.displaySource ?? '');
  }

  bool get hasPendingUploads => photos.any(
    (photo) =>
        photo.uploadStatus == ListingPhotoUploadStatus.pending ||
        photo.uploadStatus == ListingPhotoUploadStatus.uploading,
  );

  bool get hasFailedUploads => photos.any(
    (photo) => photo.uploadStatus == ListingPhotoUploadStatus.failed,
  );

  String? validateBasics() {
    if (title.trim().isEmpty) return 'Введите название';
    if (title.trim().length > 80) {
      return 'Название должно быть короче 80 символов';
    }
    if (price <= 0) return 'Укажите положительную цену';
    if (description.length > 2000) {
      return 'Описание должно быть короче 2000 символов';
    }
    if (size.isEmpty) return 'Выберите размер';
    if (condition.isEmpty) return 'Выберите состояние';
    return null;
  }

  String? validateAttributes() {
    if (section.isEmpty) return 'Выберите раздел';
    if (category.isEmpty) return 'Выберите категорию';
    if (subcategory.isEmpty) return 'Выберите подкатегорию';
    if (itemType.isEmpty) return 'Выберите тип вещи';
    if (gender.isEmpty) return 'Выберите пол';
    if (primaryColor.isEmpty) return 'Выберите основной цвет';
    if (brand.isEmpty) return 'Укажите бренд или выберите «Без бренда»';
    return null;
  }

  String? validateDelivery() {
    if (city.trim().isEmpty) return 'Укажите город';
    if (shippingAddress.trim().isEmpty) return 'Укажите адрес отправки';
    if (deliveryMethods.isEmpty) return 'Выберите хотя бы один способ передачи';
    return null;
  }

  String? validateForPublish() {
    if (photos.isEmpty) return 'Добавьте хотя бы одну фотографию';
    if (uploadedImageUrls.length != photos.length) {
      return 'Дождитесь загрузки всех фотографий';
    }
    return validateBasics() ?? validateAttributes() ?? validateDelivery();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'seller_id': sellerId,
    'status': status.value,
    'analysis_status': analysisStatus.value,
    'analysis_id': analysisId,
    'analysis_started_at': analysisStartedAt?.toIso8601String(),
    'current_step': currentStep.name,
    'photos': photos.map((photo) => photo.toJson()).toList(),
    'main_photo_id': mainPhotoId,
    'title': title,
    'title_was_edited': titleWasEdited,
    'price': price,
    'description': description,
    'description_was_edited': descriptionWasEdited,
    'size': size,
    'condition': condition,
    'section': section,
    'category': category,
    'subcategory': subcategory,
    'item_type': itemType,
    'gender': gender,
    'primary_color': primaryColor,
    'secondary_colors': secondaryColors,
    'brand': brand,
    'material': material,
    'pattern': pattern,
    'season': season,
    'style': style,
    'fit': fit,
    'sleeve_length': sleeveLength,
    'closure': closure,
    'city': city,
    'shipping_address_id': shippingAddressId,
    'shipping_address': shippingAddress,
    'save_address_as_default': saveAddressAsDefault,
    'delivery_methods': deliveryMethods,
    'predictions': predictions.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory ListingDraft.fromJson(Map<String, dynamic> json) {
    final draft = ListingDraft(
      id: json['id'] as String? ?? const Uuid().v4(),
      sellerId: json['seller_id'] as String? ?? '',
      status: ListingStatusValue.parse(json['status']),
      analysisStatus: ListingAnalysisStatusValue.parse(json['analysis_status']),
      currentStep: ListingPublishStep.values.firstWhere(
        (value) => value.name == json['current_step'],
        orElse: () => ListingPublishStep.photos,
      ),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
    );
    draft.photos.addAll(
      (json['photos'] as List<dynamic>? ?? const []).whereType<Map>().map(
        (item) => ListingPhoto.fromJson(Map<String, dynamic>.from(item)),
      ),
    );
    draft.mainPhotoId = json['main_photo_id'] as String? ?? '';
    draft.analysisId = json['analysis_id'] as String? ?? '';
    draft.analysisStartedAt = DateTime.tryParse(
      json['analysis_started_at'] as String? ?? '',
    )?.toUtc();
    draft.title = json['title'] as String? ?? '';
    draft.titleWasEdited = json['title_was_edited'] as bool? ?? false;
    draft.price = (json['price'] as num?)?.toInt() ?? 0;
    draft.description = json['description'] as String? ?? '';
    draft.descriptionWasEdited =
        json['description_was_edited'] as bool? ?? false;
    draft.size = json['size'] as String? ?? '';
    draft.condition = json['condition'] as String? ?? '';
    draft.section = json['section'] as String? ?? '';
    draft.category = json['category'] as String? ?? '';
    draft.subcategory = json['subcategory'] as String? ?? '';
    draft.itemType = json['item_type'] as String? ?? '';
    draft.gender = json['gender'] as String? ?? '';
    draft.primaryColor = json['primary_color'] as String? ?? '';
    draft.secondaryColors.addAll(
      (json['secondary_colors'] as List<dynamic>? ?? const [])
          .whereType<String>(),
    );
    draft.brand = json['brand'] as String? ?? '';
    draft.material = json['material'] as String? ?? '';
    draft.pattern = json['pattern'] as String? ?? '';
    draft.season = json['season'] as String? ?? '';
    draft.style = json['style'] as String? ?? '';
    draft.fit = json['fit'] as String? ?? '';
    draft.sleeveLength = json['sleeve_length'] as String? ?? '';
    draft.closure = json['closure'] as String? ?? '';
    draft.city = json['city'] as String? ?? '';
    draft.shippingAddressId = json['shipping_address_id'] as String? ?? '';
    draft.shippingAddress = json['shipping_address'] as String? ?? '';
    draft.saveAddressAsDefault =
        json['save_address_as_default'] as bool? ?? false;
    draft.deliveryMethods.addAll(
      (json['delivery_methods'] as List<dynamic>? ?? const [])
          .whereType<String>(),
    );
    final predictionJson = json['predictions'];
    if (predictionJson is Map) {
      for (final entry in predictionJson.entries) {
        if (entry.value is Map) {
          draft.predictions[entry.key
              .toString()] = ListingFieldPrediction.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    }
    if (draft.mainPhotoId.isEmpty && draft.photos.isNotEmpty) {
      draft.mainPhotoId = draft.photos.first.id;
    }
    return draft;
  }
}
