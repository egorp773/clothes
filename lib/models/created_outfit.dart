class OutfitItem {
  const OutfitItem({
    required this.id,
    required this.name,
    required this.price,
    required this.image,
  });

  final String id;
  final String name;
  final String price;
  final String image;

  factory OutfitItem.fromJson(Map<String, dynamic> json) {
    return OutfitItem(
      id: json['id'] as String,
      name: json['name'] as String,
      price: _normalizePrice(json['price'] as String?),
      image: json['image'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'price': price, 'image': image};
  }

  static String _normalizePrice(String? price) {
    final trimmed = price?.trim() ?? '';
    if (trimmed.isEmpty) return '';

    const ruble = '\u20BD';
    final hasBrokenCurrency =
        trimmed.contains('?') ||
        trimmed.contains('₽') ||
        trimmed.contains('\uFFFD');
    if (trimmed.contains(ruble) && !hasBrokenCurrency) return trimmed;

    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return trimmed;

    final value = int.tryParse(digits);
    if (value == null) return '$digits $ruble';

    final raw = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final remaining = raw.length - i;
      buffer.write(raw[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(' ');
      }
    }
    return '$buffer $ruble';
  }
}

class OutfitLayoutItem {
  const OutfitLayoutItem({
    required this.image,
    required this.offsetX,
    required this.offsetY,
    required this.widthFactor,
    required this.heightFactor,
    required this.scale,
    required this.rotation,
  });

  final String image;
  final double offsetX;
  final double offsetY;
  final double widthFactor;
  final double heightFactor;
  final double scale;
  final double rotation;

  factory OutfitLayoutItem.fromJson(Map<String, dynamic> json) {
    return OutfitLayoutItem(
      image: json['image'] as String,
      offsetX: (json['offsetX'] as num).toDouble(),
      offsetY: (json['offsetY'] as num).toDouble(),
      widthFactor: (json['widthFactor'] as num).toDouble(),
      heightFactor: (json['heightFactor'] as num).toDouble(),
      scale: (json['scale'] as num).toDouble(),
      rotation: (json['rotation'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'image': image,
      'offsetX': offsetX,
      'offsetY': offsetY,
      'widthFactor': widthFactor,
      'heightFactor': heightFactor,
      'scale': scale,
      'rotation': rotation,
    };
  }
}

class CreatedOutfit {
  const CreatedOutfit({
    required this.id,
    required this.photos,
    required this.items,
    this.ownerId = '',
    this.authorName = 'Автор',
    this.authorHandle = '@user',
    this.authorAvatarUrl = '',
    this.previewBackgroundColor,
    this.layoutItems = const [],
    this.isLiked = false,
    this.likesCount = 0,
    this.viewsCount = 0,
    this.publishedAt,
  });

  final String id;
  final List<String> photos;
  final List<OutfitItem> items;
  final String ownerId;
  final String authorName;
  final String authorHandle;
  final String authorAvatarUrl;
  final int? previewBackgroundColor;
  final List<OutfitLayoutItem> layoutItems;
  final bool isLiked;
  final int likesCount;
  final int viewsCount;
  final DateTime? publishedAt;

  factory CreatedOutfit.fromJson(Map<String, dynamic> json) {
    return CreatedOutfit(
      id: json['id'] as String,
      photos: (json['photos'] as List<dynamic>).cast<String>(),
      items: (json['items'] as List<dynamic>)
          .map((item) => OutfitItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      ownerId: json['ownerId'] as String? ?? '',
      authorName: json['authorName'] as String? ?? 'Автор',
      authorHandle: json['authorHandle'] as String? ?? '@user',
      authorAvatarUrl: json['authorAvatarUrl'] as String? ?? '',
      previewBackgroundColor: (json['previewBackgroundColor'] as num?)?.toInt(),
      layoutItems:
          (json['layoutItems'] as List<dynamic>?)
              ?.map(
                (item) =>
                    OutfitLayoutItem.fromJson(item as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      isLiked: json['isLiked'] as bool? ?? false,
      likesCount: (json['likesCount'] as num?)?.toInt() ?? 0,
      viewsCount: (json['viewsCount'] as num?)?.toInt() ?? 0,
      publishedAt: _parseOutfitDate(
        json['publishedAt'] ?? json['createdAt'] ?? json['created_at'],
      ),
    );
  }

  factory CreatedOutfit.fromSupabase(Map<String, dynamic> json) {
    final previewJson = json['preview_layout'] as Map<String, dynamic>?;
    return CreatedOutfit(
      id: json['id'] as String,
      photos: (json['photos'] as List<dynamic>? ?? const []).cast<String>(),
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((item) => OutfitItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      ownerId: json['owner_id'] as String? ?? '',
      authorName: json['author_name'] as String? ?? 'Автор',
      authorHandle: json['author_handle'] as String? ?? '@user',
      authorAvatarUrl: json['author_avatar_url'] as String? ?? '',
      previewBackgroundColor: (previewJson?['backgroundColor'] as num?)
          ?.toInt(),
      layoutItems:
          (previewJson?['items'] as List<dynamic>?)
              ?.map(
                (item) =>
                    OutfitLayoutItem.fromJson(item as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      isLiked: json['is_liked'] as bool? ?? false,
      likesCount: (json['likes_count'] as num?)?.toInt() ?? 0,
      viewsCount: (json['views_count'] as num?)?.toInt() ?? 0,
      publishedAt: _parseOutfitDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'photos': photos,
      'items': items.map((item) => item.toJson()).toList(),
      'ownerId': ownerId,
      'authorName': authorName,
      'authorHandle': authorHandle,
      'authorAvatarUrl': authorAvatarUrl,
      'previewBackgroundColor': previewBackgroundColor,
      'layoutItems': layoutItems.map((item) => item.toJson()).toList(),
      'isLiked': isLiked,
      'likesCount': likesCount,
      'viewsCount': viewsCount,
      'publishedAt': publishedAt?.toUtc().toIso8601String(),
    };
  }

  CreatedOutfit copyWith({
    String? id,
    List<String>? photos,
    List<OutfitItem>? items,
    String? ownerId,
    String? authorName,
    String? authorHandle,
    String? authorAvatarUrl,
    int? previewBackgroundColor,
    List<OutfitLayoutItem>? layoutItems,
    bool? isLiked,
    int? likesCount,
    int? viewsCount,
    DateTime? publishedAt,
  }) {
    return CreatedOutfit(
      id: id ?? this.id,
      photos: photos ?? this.photos,
      items: items ?? this.items,
      ownerId: ownerId ?? this.ownerId,
      authorName: authorName ?? this.authorName,
      authorHandle: authorHandle ?? this.authorHandle,
      authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
      previewBackgroundColor:
          previewBackgroundColor ?? this.previewBackgroundColor,
      layoutItems: layoutItems ?? this.layoutItems,
      isLiked: isLiked ?? this.isLiked,
      likesCount: likesCount ?? this.likesCount,
      viewsCount: viewsCount ?? this.viewsCount,
      publishedAt: publishedAt ?? this.publishedAt,
    );
  }
}

DateTime? _parseOutfitDate(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}
