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
  });

  String get outfitImage => outfitImages.isNotEmpty ? outfitImages.first : '';
  String get outfitDisplayImage =>
      outfitImages.isNotEmpty ? outfitImages.first : image;

  factory Product.fromJson(Map<String, dynamic> json) {
    final priceValue = (json['priceValue'] as num?)?.toInt() ?? 0;
    return Product(
      id: json['id'] as String,
      title: json['title'] as String,
      detailTitle: json['detailTitle'] as String? ?? json['title'] as String,
      description: json['description'] as String? ?? '',
      price: _normalizePrice(json['price'] as String?, priceValue),
      detailPrice: json['detailPrice'] as String,
      priceValue: priceValue,
      image: json['image'] as String,
      category: json['category'] as String,
      brand: json['brand'] as String,
      size: json['size'] as String,
      color: json['color'] as String,
      condition: json['condition'] as String,
      location: json['location'] as String? ?? '',
      ownerId: json['ownerId'] as String? ?? '',
      sellerName: json['sellerName'] as String? ?? 'Продавец',
      sellerHandle: json['sellerHandle'] as String? ?? '@seller',
      dotsOnDark: json['dotsOnDark'] as bool,
      isLiked: json['isLiked'] as bool? ?? false,
      isHidden: json['isHidden'] as bool? ?? false,
      isLocal: json['isLocal'] as bool? ?? false,
      images: (json['images'] as List<dynamic>?)?.cast<String>() ?? const [],
      outfitImages:
          (json['outfitImages'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }

  factory Product.fromSupabase(Map<String, dynamic> json) {
    final priceValue =
        (json['price'] as num?)?.toInt() ??
        (json['price_value'] as num?)?.toInt() ??
        0;
    final images =
        (json['images'] as List<dynamic>?)?.cast<String>() ?? const <String>[];
    final outfitImages = [
      ...(json['outfit_images'] as List<dynamic>?)?.cast<String>() ??
          const <String>[],
      if ((json['cutout_image'] as String?)?.isNotEmpty ?? false)
        json['cutout_image'] as String,
    ];
    final title = json['title'] as String? ?? '';
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
      image:
          json['image'] as String? ??
          json['original_image'] as String? ??
          (images.isNotEmpty ? images.first : ''),
      category: json['category'] as String? ?? 'Другое',
      brand: json['brand'] as String? ?? '',
      size: json['size'] as String? ?? 'One Size',
      color: json['color'] as String? ?? '',
      condition: json['condition'] as String? ?? 'Хорошее',
      location: json['location'] as String? ?? json['city'] as String? ?? '',
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
    );
  }

  static String _formatPrice(int value) {
    final raw = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final remaining = raw.length - i;
      buffer.write(raw[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(' ');
      }
    }
    return buffer.toString();
  }

  static const String _ruble = '\u20BD';

  static String _priceWithCurrency(int value) {
    return '${_formatPrice(value)} $_ruble';
  }

  static String _normalizePrice(String? price, int priceValue) {
    final trimmed = price?.trim() ?? '';
    if (trimmed.isEmpty) return _priceWithCurrency(priceValue);

    final hasBrokenCurrency =
        trimmed.contains('?') ||
        trimmed.contains('₽') ||
        trimmed.contains('\uFFFD');
    if (trimmed.contains(_ruble) && !hasBrokenCurrency) return trimmed;

    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return trimmed;

    return '${_formatPrice(int.tryParse(digits) ?? priceValue)} $_ruble';
  }

  Map<String, dynamic> toJson() {
    return {
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
    };
  }

  Map<String, dynamic> toSupabaseJson({
    required String sellerId,
    bool includeOutfitImages = true,
  }) {
    final data = {
      'id': id,
      'seller_id': sellerId,
      'seller_name': sellerName,
      'seller_handle': sellerHandle,
      'title': title,
      'description': description,
      'price': priceValue,
      'images': images.isNotEmpty ? images : [image],
      'category': category,
      'brand': brand,
      'size': size,
      'color': color,
      'condition': condition,
      'location': location,
      'is_hidden': isHidden,
      'original_image': image,
      'background_status': outfitImages.isEmpty ? 'queued' : 'completed',
    };
    if (includeOutfitImages) {
      data['outfit_images'] = outfitImages;
    }
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
  }) {
    return Product(
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
    );
  }
}
