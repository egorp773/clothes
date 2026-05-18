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
        trimmed.contains('в‚Ѕ') ||
        trimmed.contains('�');
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

class CreatedOutfit {
  const CreatedOutfit({
    required this.id,
    required this.photos,
    required this.items,
    this.ownerId = '',
    this.authorName = 'Автор',
    this.authorHandle = '@user',
  });

  final String id;
  final List<String> photos;
  final List<OutfitItem> items;
  final String ownerId;
  final String authorName;
  final String authorHandle;

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
    );
  }

  factory CreatedOutfit.fromSupabase(Map<String, dynamic> json) {
    return CreatedOutfit(
      id: json['id'] as String,
      photos: (json['photos'] as List<dynamic>? ?? const []).cast<String>(),
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((item) => OutfitItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      ownerId: json['owner_id'] as String? ?? '',
      authorName: json['author_name'] as String? ?? 'Автор',
      authorHandle: json['author_handle'] as String? ?? '@user',
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
    };
  }

  CreatedOutfit copyWith({
    String? id,
    List<String>? photos,
    List<OutfitItem>? items,
    String? ownerId,
    String? authorName,
    String? authorHandle,
  }) {
    return CreatedOutfit(
      id: id ?? this.id,
      photos: photos ?? this.photos,
      items: items ?? this.items,
      ownerId: ownerId ?? this.ownerId,
      authorName: authorName ?? this.authorName,
      authorHandle: authorHandle ?? this.authorHandle,
    );
  }
}
