class AppProfile {
  const AppProfile({
    required this.name,
    required this.handle,
    required this.city,
    required this.rating,
    required this.salesCount,
    required this.followersCount,
  });

  final String name;
  final String handle;
  final String city;
  final double rating;
  final int salesCount;
  final int followersCount;

  factory AppProfile.fromJson(Map<String, dynamic> json) {
    return AppProfile(
      name: json['name'] as String,
      handle: json['handle'] as String,
      city: json['city'] as String,
      rating: (json['rating'] as num).toDouble(),
      salesCount: json['salesCount'] as int? ?? 0,
      followersCount: json['followersCount'] as int? ?? 0,
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
    };
  }

  AppProfile copyWith({
    String? name,
    String? handle,
    String? city,
    double? rating,
    int? salesCount,
    int? followersCount,
  }) {
    return AppProfile(
      name: name ?? this.name,
      handle: handle ?? this.handle,
      city: city ?? this.city,
      rating: rating ?? this.rating,
      salesCount: salesCount ?? this.salesCount,
      followersCount: followersCount ?? this.followersCount,
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
