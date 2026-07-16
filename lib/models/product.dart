import '../features/listing_publish/data/listing_catalogs.dart';

/// Backward-compatible catalog model.
///
/// Legacy presentation fields stay intact while the optional listing fields
/// allow newly published products to retain the richer draft metadata.
class Product {
  final String id;
  final String title;
  final String detailTitle;
  final String description;
  final String price;
  final String detailPrice;
  final int priceValue;
  final String image;
  final String category;
  final String brand;
  final String size;
  final String color;
  final String condition;
  final String location;
  final String ownerId;
  final String sellerName;
  final String sellerHandle;
  final bool dotsOnDark;
  bool isLiked;
  bool isHidden;
  final bool isLocal;
  final List<String> images;
  final List<String> outfitImages;

  final String status;
  final String section;
  final String categoryId;
  final String subcategory;
  final String itemType;
  final String gender;
  final String primaryColor;
  final List<String> secondaryColors;
  final String material;
  final String pattern;
  final String season;
  final String style;
  final String fit;
  final String sleeveLength;
  final String closure;
  final String city;
  final String shippingAddressId;
  final String shippingAddress;
  final List<String> deliveryMethods;
  final String mainImage;
  final DateTime? publishedAt;
  final String analysisStatus;
  final String normalizedCategory;
  final String normalizedBrand;
  final String audience;
  final bool hasDefects;
  final String defectsDescription;
  final Map<String, String> categoryAttributes;
  final String enrichmentStatus;

  Product({
    required this.id,
    required this.title,
    required this.detailTitle,
    this.description = '',
    required this.price,
    required this.detailPrice,
    required this.priceValue,
    required this.image,
    required this.category,
    required this.brand,
    required this.size,
    required this.color,
    required this.condition,
    this.location = '',
    this.ownerId = '',
    this.sellerName = 'Продавец',
    this.sellerHandle = '@seller',
    required this.dotsOnDark,
    this.isLiked = false,
    this.isHidden = false,
    this.isLocal = false,
    this.images = const [],
    this.outfitImages = const [],
    this.status = 'published',
    this.section = '',
    this.categoryId = '',
    this.subcategory = '',
    this.itemType = '',
    this.gender = '',
    this.primaryColor = '',
    this.secondaryColors = const [],
    this.material = '',
    this.pattern = '',
    this.season = '',
    this.style = '',
    this.fit = '',
    this.sleeveLength = '',
    this.closure = '',
    this.city = '',
    this.shippingAddressId = '',
    this.shippingAddress = '',
    this.deliveryMethods = const [],
    this.mainImage = '',
    this.publishedAt,
    this.analysisStatus = 'pending',
    this.normalizedCategory = '',
    this.normalizedBrand = '',
    this.audience = '',
    this.hasDefects = false,
    this.defectsDescription = '',
    this.categoryAttributes = const {},
    this.enrichmentStatus = 'pending',
  });

  String get outfitImage => outfitImages.isNotEmpty ? outfitImages.first : '';
  String get outfitDisplayImage =>
      outfitImages.isNotEmpty ? outfitImages.first : image;

  Map<String, String> get importantCharacteristics {
    final values = <String, String>{...categoryAttributes};
    void add(String key, String value) {
      if (value.isNotEmpty) values.putIfAbsent(key, () => value);
    }

    add('material', material);
    add('pattern', pattern);
    add('fit', fit);
    add('sleeve_length', sleeveLength);
    add('closure', closure);
    add('season', season);
    add('style', style);
    return values;
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    final priceValue = (json['priceValue'] as num?)?.toInt() ?? 0;
    return Product(
      id: json['id'] as String,
      title: json['title'] as String,
      detailTitle: json['detailTitle'] as String? ?? json['title'] as String,
      description: json['description'] as String? ?? '',
      price: _normalizePrice(json['price'] as String?, priceValue),
      detailPrice: json['detailPrice'] as String? ?? priceValue.toString(),
      priceValue: priceValue,
      image: json['image'] as String? ?? '',
      category: json['category'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      size: json['size'] as String? ?? '',
      color: json['color'] as String? ?? '',
      condition: json['condition'] as String? ?? '',
      location: json['location'] as String? ?? '',
      ownerId: json['ownerId'] as String? ?? '',
      sellerName: json['sellerName'] as String? ?? 'Продавец',
      sellerHandle: json['sellerHandle'] as String? ?? '@seller',
      dotsOnDark: json['dotsOnDark'] as bool? ?? false,
      isLiked: json['isLiked'] as bool? ?? false,
      isHidden: json['isHidden'] as bool? ?? false,
      isLocal: json['isLocal'] as bool? ?? false,
      images: _strings(json['images']),
      outfitImages: _strings(json['outfitImages']),
      status: json['status'] as String? ?? 'published',
      section: json['section'] as String? ?? '',
      categoryId: json['categoryId'] as String? ?? '',
      subcategory: json['subcategory'] as String? ?? '',
      itemType: json['itemType'] as String? ?? '',
      gender: json['gender'] as String? ?? '',
      primaryColor: json['primaryColor'] as String? ?? '',
      secondaryColors: _strings(json['secondaryColors']),
      material: json['material'] as String? ?? '',
      pattern: json['pattern'] as String? ?? '',
      season: json['season'] as String? ?? '',
      style: json['style'] as String? ?? '',
      fit: json['fit'] as String? ?? '',
      sleeveLength: json['sleeveLength'] as String? ?? '',
      closure: json['closure'] as String? ?? '',
      city: json['city'] as String? ?? json['location'] as String? ?? '',
      shippingAddressId: json['shippingAddressId'] as String? ?? '',
      shippingAddress: json['shippingAddress'] as String? ?? '',
      deliveryMethods: _strings(json['deliveryMethods']),
      mainImage: json['mainImage'] as String? ?? json['image'] as String? ?? '',
      publishedAt: DateTime.tryParse(json['publishedAt'] as String? ?? ''),
      analysisStatus: json['analysisStatus'] as String? ?? 'pending',
      normalizedCategory: json['normalizedCategory'] as String? ?? '',
      normalizedBrand: json['normalizedBrand'] as String? ?? '',
      audience: json['audience'] as String? ?? json['gender'] as String? ?? '',
      hasDefects: json['hasDefects'] as bool? ?? false,
      defectsDescription: json['defectsDescription'] as String? ?? '',
      categoryAttributes: _attributeMap(json['categoryAttributes']),
      enrichmentStatus: json['enrichmentStatus'] as String? ?? 'pending',
    );
  }

  factory Product.fromSupabase(Map<String, dynamic> json) {
    final priceValue =
        (json['price'] as num?)?.toInt() ??
        (json['price_value'] as num?)?.toInt() ??
        0;
    final images = _strings(json['images']);
    final outfitImages = <String>[
      ..._strings(json['outfit_images']),
      if ((json['cutout_image'] as String?)?.isNotEmpty ?? false)
        json['cutout_image'] as String,
    ];
    final title = json['title'] as String? ?? '';
    final categoryId = json['category'] as String? ?? '';
    final itemType = json['item_type'] as String? ?? '';
    final storedNormalizedCategory =
        json['normalized_category'] as String? ?? '';
    final normalizedCategory = ListingCatalogs.normalizeCategory(
      storedNormalizedCategory.isNotEmpty ? storedNormalizedCategory : itemType,
    );
    final brandId = json['brand'] as String? ?? '';
    final normalizedBrand =
        json['normalized_brand'] as String? ?? brandId.toLowerCase();
    final sizeId = json['size'] as String? ?? '';
    final conditionId = json['condition'] as String? ?? '';
    final primaryColor =
        json['primary_color'] as String? ?? json['color'] as String? ?? '';
    final image =
        json['main_image'] as String? ??
        json['image'] as String? ??
        json['original_image'] as String? ??
        (images.isNotEmpty ? images.first : '');
    final city = json['city'] as String? ?? json['location'] as String? ?? '';
    return Product(
      id: json['id'] as String,
      title: title,
      detailTitle: json['detail_title'] as String? ?? title,
      description: json['description'] as String? ?? '',
      price: json['price'] is String
          ? _normalizePrice(json['price'] as String?, priceValue)
          : _priceWithCurrency(priceValue),
      detailPrice: json['detail_price'] as String? ?? priceValue.toString(),
      priceValue: priceValue,
      image: image,
      category: ListingCatalogs.categoryName(
        normalizedCategory.isNotEmpty
            ? normalizedCategory
            : (itemType.isNotEmpty ? itemType : categoryId),
        fallback: categoryId,
      ),
      brand: ListingCatalogs.brandName(
        brandId.isEmpty ? normalizedBrand : brandId,
        fallback: brandId.isEmpty ? normalizedBrand : brandId,
      ),
      size: ListingCatalogs.sizeName(sizeId, fallback: sizeId),
      color: ListingCatalogs.colorName(primaryColor, fallback: primaryColor),
      condition: ListingCatalogs.conditionName(
        conditionId,
        fallback: conditionId,
      ),
      location: city,
      ownerId:
          json['seller_id'] as String? ?? json['owner_id'] as String? ?? '',
      sellerName: json['seller_name'] as String? ?? 'Продавец',
      sellerHandle: json['seller_handle'] as String? ?? '@seller',
      dotsOnDark: json['dots_on_dark'] as bool? ?? false,
      isLiked: json['is_liked'] as bool? ?? false,
      isHidden: json['is_hidden'] as bool? ?? false,
      isLocal: false,
      images: images,
      outfitImages: outfitImages,
      status: json['status'] as String? ?? 'published',
      section: json['section'] as String? ?? '',
      categoryId: categoryId,
      subcategory: json['subcategory'] as String? ?? '',
      itemType: itemType,
      gender: json['audience'] as String? ?? json['gender'] as String? ?? '',
      primaryColor: primaryColor,
      secondaryColors: _strings(json['secondary_colors']),
      material: json['material'] as String? ?? '',
      pattern: json['pattern'] as String? ?? '',
      season: json['season'] as String? ?? '',
      style: json['style'] as String? ?? '',
      fit: json['fit'] as String? ?? '',
      sleeveLength: json['sleeve_length'] as String? ?? '',
      closure: json['closure'] as String? ?? '',
      city: city,
      shippingAddressId: json['shipping_address_id'] as String? ?? '',
      shippingAddress: json['shipping_address'] as String? ?? '',
      deliveryMethods: _strings(json['delivery_methods']),
      mainImage: image,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      analysisStatus: json['analysis_status'] as String? ?? 'pending',
      normalizedCategory: normalizedCategory,
      normalizedBrand: normalizedBrand,
      audience: json['audience'] as String? ?? json['gender'] as String? ?? '',
      hasDefects: json['has_defects'] as bool? ?? false,
      defectsDescription:
          json['defects_description'] as String? ??
          json['defect_description'] as String? ??
          '',
      categoryAttributes: _attributeMap(
        json['product_attributes'] ?? json['category_attributes'],
      ),
      enrichmentStatus:
          json['enrichment_status'] as String? ??
          json['analysis_status'] as String? ??
          'pending',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'detailTitle': detailTitle,
    'description': description,
    'price': price,
    'detailPrice': detailPrice,
    'priceValue': priceValue,
    'image': image,
    'category': category,
    'brand': brand,
    'size': size,
    'color': color,
    'condition': condition,
    'location': location,
    'ownerId': ownerId,
    'sellerName': sellerName,
    'sellerHandle': sellerHandle,
    'dotsOnDark': dotsOnDark,
    'isLiked': isLiked,
    'isHidden': isHidden,
    'isLocal': isLocal,
    'images': images,
    'outfitImages': outfitImages,
    'status': status,
    'section': section,
    'categoryId': categoryId,
    'subcategory': subcategory,
    'itemType': itemType,
    'gender': gender,
    'primaryColor': primaryColor,
    'secondaryColors': secondaryColors,
    'material': material,
    'pattern': pattern,
    'season': season,
    'style': style,
    'fit': fit,
    'sleeveLength': sleeveLength,
    'closure': closure,
    'city': city,
    'shippingAddressId': shippingAddressId,
    'shippingAddress': shippingAddress,
    'deliveryMethods': deliveryMethods,
    'mainImage': mainImage,
    'publishedAt': publishedAt?.toIso8601String(),
    'analysisStatus': analysisStatus,
    'normalizedCategory': normalizedCategory,
    'normalizedBrand': normalizedBrand,
    'audience': audience,
    'hasDefects': hasDefects,
    'defectsDescription': defectsDescription,
    'categoryAttributes': categoryAttributes,
    'enrichmentStatus': enrichmentStatus,
  };

  Map<String, dynamic> toSupabaseJson({
    required String sellerId,
    bool includeOutfitImages = true,
  }) {
    final data = <String, dynamic>{
      'id': id,
      'seller_id': sellerId,
      'seller_name': sellerName,
      'seller_handle': sellerHandle,
      'title': title,
      'description': description,
      'price': priceValue,
      'images': images.isNotEmpty ? images : [image],
      'category': categoryId.isNotEmpty
          ? categoryId
          : (ListingCatalogs.legacyPathFor(normalizedCategory).category.isEmpty
                ? category
                : ListingCatalogs.legacyPathFor(normalizedCategory).category),
      'brand': normalizedBrand.isEmpty ? brand : normalizedBrand,
      'size': ListingCatalogs.sizeIdOf(size),
      'color': primaryColor.isEmpty ? color : primaryColor,
      'condition': ListingCatalogs.conditionIdOf(condition),
      'location': location,
      'is_hidden': isHidden,
      'original_image': image,
      'background_status': outfitImages.isEmpty ? 'queued' : 'completed',
      'status': status,
      'section': section,
      'subcategory': subcategory,
      'item_type': itemType,
      'gender': gender,
      'primary_color': primaryColor,
      'secondary_colors': secondaryColors,
      'material': material,
      'pattern': pattern,
      'season': season,
      'style': style,
      'fit': fit,
      'sleeve_length': sleeveLength,
      'closure': closure,
      'city': city.isEmpty ? location : city,
      'shipping_address_id': shippingAddressId.isEmpty
          ? null
          : shippingAddressId,
      'shipping_address': shippingAddress,
      'delivery_methods': deliveryMethods,
      'main_image': mainImage.isEmpty ? image : mainImage,
      'published_at': publishedAt?.toIso8601String(),
      'analysis_status': analysisStatus,
      'normalized_category': normalizedCategory,
      'normalized_brand': normalizedBrand,
      'audience': audience.isEmpty ? gender : audience,
      'has_defects': hasDefects,
      'defects_description': defectsDescription,
      'enrichment_status': enrichmentStatus,
    };
    if (includeOutfitImages) data['outfit_images'] = outfitImages;
    return data;
  }

  Product copyWith({
    String? id,
    String? title,
    String? detailTitle,
    String? description,
    String? price,
    String? detailPrice,
    int? priceValue,
    String? image,
    String? category,
    String? brand,
    String? size,
    String? color,
    String? condition,
    String? location,
    String? ownerId,
    String? sellerName,
    String? sellerHandle,
    bool? dotsOnDark,
    bool? isLiked,
    bool? isHidden,
    bool? isLocal,
    List<String>? images,
    List<String>? outfitImages,
    String? status,
    String? section,
    String? categoryId,
    String? subcategory,
    String? itemType,
    String? gender,
    String? primaryColor,
    List<String>? secondaryColors,
    String? material,
    String? pattern,
    String? season,
    String? style,
    String? fit,
    String? sleeveLength,
    String? closure,
    String? city,
    String? shippingAddressId,
    String? shippingAddress,
    List<String>? deliveryMethods,
    String? mainImage,
    DateTime? publishedAt,
    String? analysisStatus,
    String? normalizedCategory,
    String? normalizedBrand,
    String? audience,
    bool? hasDefects,
    String? defectsDescription,
    Map<String, String>? categoryAttributes,
    String? enrichmentStatus,
  }) => Product(
    id: id ?? this.id,
    title: title ?? this.title,
    detailTitle: detailTitle ?? this.detailTitle,
    description: description ?? this.description,
    price: price ?? this.price,
    detailPrice: detailPrice ?? this.detailPrice,
    priceValue: priceValue ?? this.priceValue,
    image: image ?? this.image,
    category: category ?? this.category,
    brand: brand ?? this.brand,
    size: size ?? this.size,
    color: color ?? this.color,
    condition: condition ?? this.condition,
    location: location ?? this.location,
    ownerId: ownerId ?? this.ownerId,
    sellerName: sellerName ?? this.sellerName,
    sellerHandle: sellerHandle ?? this.sellerHandle,
    dotsOnDark: dotsOnDark ?? this.dotsOnDark,
    isLiked: isLiked ?? this.isLiked,
    isHidden: isHidden ?? this.isHidden,
    isLocal: isLocal ?? this.isLocal,
    images: images ?? this.images,
    outfitImages: outfitImages ?? this.outfitImages,
    status: status ?? this.status,
    section: section ?? this.section,
    categoryId: categoryId ?? this.categoryId,
    subcategory: subcategory ?? this.subcategory,
    itemType: itemType ?? this.itemType,
    gender: gender ?? this.gender,
    primaryColor: primaryColor ?? this.primaryColor,
    secondaryColors: secondaryColors ?? this.secondaryColors,
    material: material ?? this.material,
    pattern: pattern ?? this.pattern,
    season: season ?? this.season,
    style: style ?? this.style,
    fit: fit ?? this.fit,
    sleeveLength: sleeveLength ?? this.sleeveLength,
    closure: closure ?? this.closure,
    city: city ?? this.city,
    shippingAddressId: shippingAddressId ?? this.shippingAddressId,
    shippingAddress: shippingAddress ?? this.shippingAddress,
    deliveryMethods: deliveryMethods ?? this.deliveryMethods,
    mainImage: mainImage ?? this.mainImage,
    publishedAt: publishedAt ?? this.publishedAt,
    analysisStatus: analysisStatus ?? this.analysisStatus,
    normalizedCategory: normalizedCategory ?? this.normalizedCategory,
    normalizedBrand: normalizedBrand ?? this.normalizedBrand,
    audience: audience ?? this.audience,
    hasDefects: hasDefects ?? this.hasDefects,
    defectsDescription: defectsDescription ?? this.defectsDescription,
    categoryAttributes: categoryAttributes ?? this.categoryAttributes,
    enrichmentStatus: enrichmentStatus ?? this.enrichmentStatus,
  );

  static List<String> _strings(Object? value) =>
      (value as List<dynamic>? ?? const []).whereType<String>().toList();

  static Map<String, String> _attributeMap(Object? value) {
    final result = <String, String>{};
    if (value is Map) {
      for (final entry in value.entries) {
        final raw = entry.value;
        if (raw != null && raw.toString().isNotEmpty) {
          result[entry.key.toString()] = raw.toString();
        }
      }
    } else if (value is List) {
      for (final raw in value.whereType<Map>()) {
        final key = raw['attribute_key']?.toString() ?? '';
        final attributeValue = raw['value'];
        if (key.isNotEmpty && attributeValue != null) {
          result[key] = attributeValue.toString();
        }
      }
    }
    return Map.unmodifiable(result);
  }

  static String _formatPrice(int value) {
    final raw = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < raw.length; index++) {
      final remaining = raw.length - index;
      buffer.write(raw[index]);
      if (remaining > 1 && remaining % 3 == 1) buffer.write(' ');
    }
    return buffer.toString();
  }

  static const _ruble = '\u20BD';

  static String _priceWithCurrency(int value) =>
      '${_formatPrice(value)} $_ruble';

  static String _normalizePrice(String? price, int priceValue) {
    final trimmed = price?.trim() ?? '';
    if (trimmed.isEmpty) return _priceWithCurrency(priceValue);
    final hasBrokenCurrency =
        trimmed.contains('?') ||
        trimmed.contains('в‚Ѕ') ||
        trimmed.contains('\uFFFD');
    if (trimmed.contains(_ruble) && !hasBrokenCurrency) return trimmed;
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return trimmed;
    return '${_formatPrice(int.tryParse(digits) ?? priceValue)} $_ruble';
  }
}
