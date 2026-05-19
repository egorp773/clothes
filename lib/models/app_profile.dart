class AppProfile {
  const AppProfile({
    required this.name,
    required this.handle,
    required this.city,
    required this.rating,
    required this.salesCount,
  });

  final String name;
  final String handle;
  final String city;
  final double rating;
  final int salesCount;

  factory AppProfile.fromJson(Map<String, dynamic> json) {
    return AppProfile(
      name: json['name'] as String,
      handle: json['handle'] as String,
      city: json['city'] as String,
      rating: (json['rating'] as num).toDouble(),
      salesCount: json['salesCount'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'handle': handle,
      'city': city,
      'rating': rating,
      'salesCount': salesCount,
    };
  }

  AppProfile copyWith({
    String? name,
    String? handle,
    String? city,
    double? rating,
    int? salesCount,
  }) {
    return AppProfile(
      name: name ?? this.name,
      handle: handle ?? this.handle,
      city: city ?? this.city,
      rating: rating ?? this.rating,
      salesCount: salesCount ?? this.salesCount,
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
