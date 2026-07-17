class OutfitAccessory {
  const OutfitAccessory({
    required this.id,
    required this.title,
    required this.image,
    required this.cutoutImage,
    required this.scope,
    this.ownerId = '',
    this.backgroundStatus = 'queued',
    this.isLocal = false,
  });

  final String id;
  final String title;
  final String image;
  final String cutoutImage;
  final String scope;
  final String ownerId;
  final String backgroundStatus;
  final bool isLocal;

  bool get isDefault => scope == 'default';
  bool get isProcessing => cutoutImage.isEmpty && backgroundStatus != 'failed';
  String get displayImage => cutoutImage.isNotEmpty ? cutoutImage : image;

  factory OutfitAccessory.fromJson(Map<String, dynamic> json) {
    return OutfitAccessory(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Аксессуар',
      image: json['image'] as String? ?? '',
      cutoutImage: json['cutoutImage'] as String? ?? '',
      scope: json['scope'] as String? ?? 'private',
      ownerId: json['ownerId'] as String? ?? '',
      backgroundStatus: json['backgroundStatus'] as String? ?? 'queued',
      isLocal: json['isLocal'] as bool? ?? false,
    );
  }

  factory OutfitAccessory.fromSupabase(Map<String, dynamic> json) {
    return OutfitAccessory(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Аксессуар',
      image:
          json['original_image'] as String? ?? json['image'] as String? ?? '',
      cutoutImage: json['cutout_image'] as String? ?? '',
      scope: json['scope'] as String? ?? 'private',
      ownerId: json['owner_id'] as String? ?? '',
      backgroundStatus: json['background_status'] as String? ?? 'queued',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'image': image,
      'cutoutImage': cutoutImage,
      'scope': scope,
      'ownerId': ownerId,
      'backgroundStatus': backgroundStatus,
      'isLocal': isLocal,
    };
  }

  Map<String, dynamic> toSupabaseJson() {
    return {
      'id': id,
      'title': title,
      'scope': scope,
      'owner_id': ownerId.isEmpty ? null : ownerId,
      'original_image': image,
      'cutout_image': cutoutImage.isEmpty ? null : cutoutImage,
      'background_status': backgroundStatus,
    };
  }

  OutfitAccessory copyWith({
    String? id,
    String? title,
    String? image,
    String? cutoutImage,
    String? scope,
    String? ownerId,
    String? backgroundStatus,
    bool? isLocal,
  }) {
    return OutfitAccessory(
      id: id ?? this.id,
      title: title ?? this.title,
      image: image ?? this.image,
      cutoutImage: cutoutImage ?? this.cutoutImage,
      scope: scope ?? this.scope,
      ownerId: ownerId ?? this.ownerId,
      backgroundStatus: backgroundStatus ?? this.backgroundStatus,
      isLocal: isLocal ?? this.isLocal,
    );
  }
}
