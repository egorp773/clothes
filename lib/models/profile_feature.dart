import 'product.dart';

class NotificationPreferences {
  const NotificationPreferences({
    this.pushEnabled = true,
    this.messagesEnabled = true,
    this.ordersEnabled = true,
    this.favoritesEnabled = true,
    this.promotionsEnabled = false,
    this.soundEnabled = true,
    this.emailEnabled = false,
    this.smsEnabled = true,
  });

  final bool pushEnabled;
  final bool messagesEnabled;
  final bool ordersEnabled;
  final bool favoritesEnabled;
  final bool promotionsEnabled;
  final bool soundEnabled;
  final bool emailEnabled;
  final bool smsEnabled;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      pushEnabled:
          json['push_enabled'] as bool? ?? json['pushEnabled'] as bool? ?? true,
      messagesEnabled:
          json['messages_enabled'] as bool? ??
          json['messagesEnabled'] as bool? ??
          true,
      ordersEnabled:
          json['orders_enabled'] as bool? ??
          json['ordersEnabled'] as bool? ??
          true,
      favoritesEnabled:
          json['favorites_enabled'] as bool? ??
          json['favoritesEnabled'] as bool? ??
          true,
      promotionsEnabled:
          json['promotions_enabled'] as bool? ??
          json['promotionsEnabled'] as bool? ??
          false,
      soundEnabled:
          json['sound_enabled'] as bool? ??
          json['soundEnabled'] as bool? ??
          true,
      emailEnabled:
          json['email_enabled'] as bool? ??
          json['emailEnabled'] as bool? ??
          false,
      smsEnabled:
          json['sms_enabled'] as bool? ?? json['smsEnabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pushEnabled': pushEnabled,
      'messagesEnabled': messagesEnabled,
      'ordersEnabled': ordersEnabled,
      'favoritesEnabled': favoritesEnabled,
      'promotionsEnabled': promotionsEnabled,
      'soundEnabled': soundEnabled,
      'emailEnabled': emailEnabled,
      'smsEnabled': smsEnabled,
    };
  }

  Map<String, dynamic> toSupabaseJson(String userId) {
    return {
      'user_id': userId,
      'push_enabled': pushEnabled,
      'messages_enabled': messagesEnabled,
      'orders_enabled': ordersEnabled,
      'favorites_enabled': favoritesEnabled,
      'promotions_enabled': promotionsEnabled,
      'sound_enabled': soundEnabled,
      'email_enabled': emailEnabled,
      'sms_enabled': smsEnabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  NotificationPreferences copyWith({
    bool? pushEnabled,
    bool? messagesEnabled,
    bool? ordersEnabled,
    bool? favoritesEnabled,
    bool? promotionsEnabled,
    bool? soundEnabled,
    bool? emailEnabled,
    bool? smsEnabled,
  }) {
    return NotificationPreferences(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      messagesEnabled: messagesEnabled ?? this.messagesEnabled,
      ordersEnabled: ordersEnabled ?? this.ordersEnabled,
      favoritesEnabled: favoritesEnabled ?? this.favoritesEnabled,
      promotionsEnabled: promotionsEnabled ?? this.promotionsEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      emailEnabled: emailEnabled ?? this.emailEnabled,
      smsEnabled: smsEnabled ?? this.smsEnabled,
    );
  }
}

class ProfileNotification {
  const ProfileNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.kind = 'general',
    this.targetId = '',
    this.data = const {},
    this.isRead = false,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final String kind;
  final String targetId;
  final Map<String, String> data;
  final bool isRead;

  factory ProfileNotification.fromJson(Map<String, dynamic> json) {
    return ProfileNotification(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      createdAt: DateTime.parse(
        json['created_at'] as String? ?? json['createdAt'] as String,
      ).toUtc(),
      kind: json['kind'] as String? ?? 'general',
      targetId:
          json['target_id'] as String? ?? json['targetId'] as String? ?? '',
      data: _stringMap(json['data']),
      isRead: json['is_read'] as bool? ?? json['isRead'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'kind': kind,
      'targetId': targetId,
      'data': data,
      'isRead': isRead,
    };
  }

  Map<String, dynamic> toSupabaseJson(String userId) {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'body': body,
      'kind': kind,
      'target_id': targetId,
      'data': data,
      'is_read': isRead,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  ProfileNotification copyWith({bool? isRead}) {
    return ProfileNotification(
      id: id,
      title: title,
      body: body,
      createdAt: createdAt,
      kind: kind,
      targetId: targetId,
      data: data,
      isRead: isRead ?? this.isRead,
    );
  }
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries)
      if (entry.key != null && entry.value != null)
        entry.key.toString(): entry.value.toString(),
  };
}

enum AppOrderRole { buyer, seller }

enum AppOrderStatus {
  created,
  paid,
  sellerConfirmed,
  shipped,
  received,
  inspection,
  completed,
  dispute,
  cancelled,
}

extension AppOrderStatusWire on AppOrderStatus {
  String get wireName => switch (this) {
    AppOrderStatus.sellerConfirmed => 'seller_confirmed',
    _ => name,
  };
}

class DeliveryProfile {
  const DeliveryProfile({
    this.fullName = '',
    this.phone = '',
    this.email = '',
    this.city = '',
    this.address = '',
    this.pickupProvider = '',
    this.pickupPointId = '',
    this.pickupPointName = '',
    this.pickupPointAddress = '',
  });

  final String fullName;
  final String phone;
  final String email;
  final String city;
  final String address;
  final String pickupProvider;
  final String pickupPointId;
  final String pickupPointName;
  final String pickupPointAddress;

  factory DeliveryProfile.fromJson(Map<String, dynamic> json) {
    return DeliveryProfile(
      fullName:
          json['full_name'] as String? ?? json['fullName'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      city: json['city'] as String? ?? '',
      address: json['address'] as String? ?? '',
      pickupProvider:
          json['pickup_provider'] as String? ??
          json['pickupProvider'] as String? ??
          '',
      pickupPointId:
          json['pickup_point_id'] as String? ??
          json['pickupPointId'] as String? ??
          '',
      pickupPointName:
          json['pickup_point_name'] as String? ??
          json['pickupPointName'] as String? ??
          '',
      pickupPointAddress:
          json['pickup_point_address'] as String? ??
          json['pickupPointAddress'] as String? ??
          '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fullName': fullName,
      'phone': phone,
      'email': email,
      'city': city,
      'address': address,
      'pickupProvider': pickupProvider,
      'pickupPointId': pickupPointId,
      'pickupPointName': pickupPointName,
      'pickupPointAddress': pickupPointAddress,
    };
  }

  Map<String, dynamic> toSupabaseJson(String userId) {
    return {
      'user_id': userId,
      'full_name': fullName,
      'phone': phone,
      'email': email,
      'city': city,
      'address': address,
      'pickup_provider': pickupProvider,
      'pickup_point_id': pickupPointId,
      'pickup_point_name': pickupPointName,
      'pickup_point_address': pickupPointAddress,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  DeliveryProfile copyWith({
    String? fullName,
    String? phone,
    String? email,
    String? city,
    String? address,
    String? pickupProvider,
    String? pickupPointId,
    String? pickupPointName,
    String? pickupPointAddress,
  }) {
    return DeliveryProfile(
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      city: city ?? this.city,
      address: address ?? this.address,
      pickupProvider: pickupProvider ?? this.pickupProvider,
      pickupPointId: pickupPointId ?? this.pickupPointId,
      pickupPointName: pickupPointName ?? this.pickupPointName,
      pickupPointAddress: pickupPointAddress ?? this.pickupPointAddress,
    );
  }
}

/// A user-facing checkout failure returned by the server-authoritative order
/// command. UI code may display [message]; [code] is stable for analytics and
/// tests and must not contain provider secrets or personal data.
class CheckoutException implements Exception {
  const CheckoutException({
    required this.code,
    required this.message,
    this.isRetryable = false,
  });

  final String code;
  final String message;
  final bool isRetryable;

  @override
  String toString() => 'CheckoutException($code)';
}

class AppOrder {
  const AppOrder({
    required this.id,
    required this.productId,
    required this.productTitle,
    required this.productImage,
    required this.productPrice,
    required this.productPriceValue,
    required this.sellerId,
    required this.buyerId,
    required this.trackingNumber,
    required this.deliveryService,
    required this.deliveryAddress,
    required this.recipientName,
    required this.recipientPhone,
    required this.recipientEmail,
    required this.deliveryPrice,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String productId;
  final String productTitle;
  final String productImage;
  final String productPrice;
  final int productPriceValue;
  final String sellerId;
  final String buyerId;
  final String trackingNumber;
  final String deliveryService;
  final String deliveryAddress;
  final String recipientName;
  final String recipientPhone;
  final String recipientEmail;
  final int deliveryPrice;
  final AppOrderStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory AppOrder.fromJson(Map<String, dynamic> json) {
    return AppOrder(
      id: json['id'] as String,
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
      productPrice:
          json['product_price'] as String? ??
          json['productPrice'] as String? ??
          '',
      productPriceValue:
          (json['product_price_value'] as num?)?.toInt() ??
          (json['productPriceValue'] as num?)?.toInt() ??
          0,
      sellerId:
          json['seller_id'] as String? ?? json['sellerId'] as String? ?? '',
      buyerId: json['buyer_id'] as String? ?? json['buyerId'] as String? ?? '',
      trackingNumber:
          json['tracking_number'] as String? ??
          json['trackingNumber'] as String? ??
          '',
      deliveryService:
          json['delivery_service'] as String? ??
          json['deliveryService'] as String? ??
          'Почта России',
      deliveryAddress:
          json['delivery_address'] as String? ??
          json['deliveryAddress'] as String? ??
          '',
      recipientName:
          json['recipient_name'] as String? ??
          json['recipientName'] as String? ??
          '',
      recipientPhone:
          json['recipient_phone'] as String? ??
          json['recipientPhone'] as String? ??
          '',
      recipientEmail:
          json['recipient_email'] as String? ??
          json['recipientEmail'] as String? ??
          '',
      deliveryPrice:
          (json['delivery_price'] as num?)?.toInt() ??
          (json['deliveryPrice'] as num?)?.toInt() ??
          0,
      status: _statusFromString(
        json['status'] as String? ?? json['statusName'] as String? ?? '',
      ),
      createdAt:
          DateTime.tryParse(
            json['created_at'] as String? ?? json['createdAt'] as String? ?? '',
          ) ??
          DateTime.now().toUtc(),
      updatedAt:
          DateTime.tryParse(
            json['updated_at'] as String? ?? json['updatedAt'] as String? ?? '',
          ) ??
          DateTime.now().toUtc(),
    );
  }

  factory AppOrder.fromProduct({
    required Product product,
    required String buyerId,
    required AppOrderStatus status,
    DeliveryProfile deliveryProfile = const DeliveryProfile(),
    String deliveryService = 'Почта России',
    int deliveryPrice = 122,
  }) {
    final now = DateTime.now().toUtc();
    return AppOrder(
      id: 'local_${product.id}_${now.millisecondsSinceEpoch}',
      productId: product.id,
      productTitle: product.title,
      productImage: product.image,
      productPrice: product.price,
      productPriceValue: product.priceValue,
      sellerId: product.ownerId,
      buyerId: buyerId,
      trackingNumber: '',
      deliveryService: deliveryService,
      deliveryAddress: deliveryProfile.address,
      recipientName: deliveryProfile.fullName,
      recipientPhone: deliveryProfile.phone,
      recipientEmail: deliveryProfile.email,
      deliveryPrice: deliveryPrice,
      status: status,
      createdAt: now,
      updatedAt: now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'productId': productId,
      'productTitle': productTitle,
      'productImage': productImage,
      'productPrice': productPrice,
      'productPriceValue': productPriceValue,
      'sellerId': sellerId,
      'buyerId': buyerId,
      'trackingNumber': trackingNumber,
      'deliveryService': deliveryService,
      'deliveryAddress': deliveryAddress,
      'recipientName': recipientName,
      'recipientPhone': recipientPhone,
      'recipientEmail': recipientEmail,
      'deliveryPrice': deliveryPrice,
      'statusName': status.name,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }
}

class SellerDashboardStats {
  const SellerDashboardStats({
    required this.rating,
    required this.commissionPercent,
    required this.revenue,
    required this.ordersCount,
    required this.averageOrder,
    required this.returnsPercent,
  });

  final double rating;
  final int commissionPercent;
  final int revenue;
  final int ordersCount;
  final int averageOrder;
  final double returnsPercent;
}

AppOrderStatus _statusFromString(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized == 'seller_confirmed') {
    return AppOrderStatus.sellerConfirmed;
  }
  return AppOrderStatus.values.firstWhere(
    (status) => status.name.toLowerCase() == normalized,
    // Unknown states must never be interpreted as paid or completed.
    orElse: () => AppOrderStatus.created,
  );
}
