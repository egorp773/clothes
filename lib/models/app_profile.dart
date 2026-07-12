class AppProfile {
  const AppProfile({
    required this.name,
    required this.handle,
    required this.city,
    required this.rating,
    required this.salesCount,
    required this.followersCount,
    this.firstName = '',
    this.lastName = '',
    this.middleName = '',
    this.gender = 'male',
    this.birthDate = '',
    this.phone = '',
    this.email = '',
    this.avatarUrl = '',
  });

  final String name;
  final String handle;
  final String city;
  final double rating;
  final int salesCount;
  final int followersCount;
  final String firstName;
  final String lastName;
  final String middleName;
  final String gender;
  final String birthDate;
  final String phone;
  final String email;
  final String avatarUrl;

  factory AppProfile.fromJson(Map<String, dynamic> json) {
    final legacyName = json['name'] as String? ?? '';
    final nameParts = legacyName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    return AppProfile(
      name: legacyName,
      handle: json['handle'] as String? ?? '@user',
      city: json['city'] as String? ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      salesCount: json['salesCount'] as int? ?? 0,
      followersCount: json['followersCount'] as int? ?? 0,
      firstName:
          json['firstName'] as String? ??
          (nameParts.isNotEmpty ? nameParts.first : ''),
      lastName:
          json['lastName'] as String? ??
          (nameParts.length > 1 ? nameParts[1] : ''),
      middleName: json['middleName'] as String? ?? '',
      gender: json['gender'] as String? ?? 'male',
      birthDate: json['birthDate'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'handle': handle,
      'city': city,
      'rating': rating,
      'salesCount': salesCount,
      'followersCount': followersCount,
      'firstName': firstName,
      'lastName': lastName,
      'middleName': middleName,
      'gender': gender,
      'birthDate': birthDate,
      'phone': phone,
      'email': email,
      'avatarUrl': avatarUrl,
    };
  }

  AppProfile copyWith({
    String? name,
    String? handle,
    String? city,
    double? rating,
    int? salesCount,
    int? followersCount,
    String? firstName,
    String? lastName,
    String? middleName,
    String? gender,
    String? birthDate,
    String? phone,
    String? email,
    String? avatarUrl,
  }) {
    return AppProfile(
      name: name ?? this.name,
      handle: handle ?? this.handle,
      city: city ?? this.city,
      rating: rating ?? this.rating,
      salesCount: salesCount ?? this.salesCount,
      followersCount: followersCount ?? this.followersCount,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      middleName: middleName ?? this.middleName,
      gender: gender ?? this.gender,
      birthDate: birthDate ?? this.birthDate,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}

class AppUserProfile {
  const AppUserProfile({
    required this.id,
    required this.name,
    required this.handle,
    this.avatarUrl = '',
  });

  final String id;
  final String name;
  final String handle;
  final String avatarUrl;

  factory AppUserProfile.fromSupabase(Map<String, dynamic> json) {
    return AppUserProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Пользователь',
      handle: json['handle'] as String? ?? '@user',
      avatarUrl: json['avatar_url'] as String? ?? '',
    );
  }
}

class SellerProfile {
  const SellerProfile({
    required this.id,
    required this.name,
    required this.handle,
    this.avatarUrl = '',
    this.city = '',
    this.bio = '',
    this.accountType = '',
    this.rating = 0,
    this.salesCount = 0,
    this.followersCount = 0,
  });

  final String id;
  final String name;
  final String handle;
  final String avatarUrl;
  final String city;
  final String bio;
  final String accountType;
  final double rating;
  final int salesCount;
  final int followersCount;

  factory SellerProfile.fromSupabase(Map<String, dynamic> json) {
    return SellerProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Продавец',
      handle: json['handle'] as String? ?? '@seller',
      avatarUrl: json['avatar_url'] as String? ?? '',
      city: json['city'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      accountType: json['account_type'] as String? ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      salesCount: (json['sales_count'] as num?)?.toInt() ?? 0,
      followersCount: (json['followers_count'] as num?)?.toInt() ?? 0,
    );
  }

  AppUserProfile toUserProfile() {
    return AppUserProfile(
      id: id,
      name: name,
      handle: handle,
      avatarUrl: avatarUrl,
    );
  }
}

class SellerReview {
  const SellerReview({
    required this.id,
    required this.sellerId,
    required this.buyerId,
    required this.buyerName,
    required this.productId,
    required this.productTitle,
    required this.rating,
    required this.createdAt,
    this.buyerAvatar = '',
    this.productImage = '',
    this.text = '',
    this.hasPhoto = false,
    this.dealCompleted = true,
  });

  final String id;
  final String sellerId;
  final String buyerId;
  final String buyerName;
  final String buyerAvatar;
  final String productId;
  final String productTitle;
  final String productImage;
  final int rating;
  final String text;
  final bool hasPhoto;
  final bool dealCompleted;
  final DateTime createdAt;

  factory SellerReview.fromJson(Map<String, dynamic> json) {
    return SellerReview(
      id: json['id'] as String? ?? '',
      sellerId:
          json['seller_id'] as String? ?? json['sellerId'] as String? ?? '',
      buyerId: json['buyer_id'] as String? ?? json['buyerId'] as String? ?? '',
      buyerName:
          json['buyer_name'] as String? ?? json['buyerName'] as String? ?? '',
      buyerAvatar:
          json['buyer_avatar'] as String? ??
          json['buyerAvatar'] as String? ??
          '',
      productId:
          json['product_id'] as String? ?? json['productId'] as String? ?? '',
      productTitle:
          json['product_title'] as String? ??
          json['productTitle'] as String? ??
          '',
      productImage:
          json['product_image'] as String? ??
          json['productImage'] as String? ??
          '',
      rating:
          (json['rating'] as num?)?.toInt().clamp(1, 5) ??
          (json['stars'] as num?)?.toInt().clamp(1, 5) ??
          5,
      text: json['text'] as String? ?? '',
      hasPhoto:
          json['has_photo'] as bool? ?? json['hasPhoto'] as bool? ?? false,
      dealCompleted:
          json['deal_completed'] as bool? ??
          json['dealCompleted'] as bool? ??
          true,
      createdAt:
          DateTime.tryParse(
            json['created_at'] as String? ?? json['createdAt'] as String? ?? '',
          ) ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sellerId': sellerId,
      'buyerId': buyerId,
      'buyerName': buyerName,
      'buyerAvatar': buyerAvatar,
      'productId': productId,
      'productTitle': productTitle,
      'productImage': productImage,
      'rating': rating,
      'text': text,
      'hasPhoto': hasPhoto,
      'dealCompleted': dealCompleted,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toSupabaseJson() {
    return {
      'id': id,
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'buyer_name': buyerName,
      'buyer_avatar': buyerAvatar,
      'product_id': productId,
      'product_title': productTitle,
      'product_image': productImage,
      'rating': rating,
      'text': text,
      'has_photo': hasPhoto,
      'deal_completed': dealCompleted,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
