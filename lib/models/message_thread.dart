class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.isMine,
    this.senderId = '',
    this.senderName = '',
  });

  final String id;
  final String text;
  final DateTime createdAt;
  final bool isMine;
  final String senderId;
  final String senderName;

  factory ChatMessage.fromJson(
    Map<String, dynamic> json, {
    String currentUserId = '',
  }) {
    final senderId =
        json['sender_id'] as String? ?? json['senderId'] as String? ?? '';
    return ChatMessage(
      id: json['id'] as String,
      text: json['text'] as String,
      createdAt: DateTime.parse(
        json['created_at'] as String? ?? json['createdAt'] as String,
      ),
      isMine: currentUserId.isNotEmpty
          ? senderId == currentUserId
          : json['isMine'] as bool? ?? true,
      senderId: senderId,
      senderName:
          json['sender_name'] as String? ?? json['senderName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      'isMine': isMine,
      'senderId': senderId,
      'senderName': senderName,
    };
  }

  Map<String, dynamic> toSupabaseJson() {
    return {
      'id': id,
      'text': text,
      'created_at': createdAt.toIso8601String(),
      'sender_id': senderId,
      'sender_name': senderName,
    };
  }
}

class MessageThread {
  const MessageThread({
    required this.id,
    required this.sellerName,
    required this.buyerName,
    required this.productTitle,
    required this.lastMessage,
    required this.updatedAt,
    this.productId = '',
    this.productImage = '',
    this.buyerId = '',
    this.sellerId = '',
    this.buyerHandle = '',
    this.sellerHandle = '',
    this.buyerAvatar = '',
    this.sellerAvatar = '',
    this.unreadCount = 0,
    this.messages = const [],
  });

  final String id;
  final String sellerName;
  final String buyerName;
  final String productTitle;
  final String lastMessage;
  final DateTime updatedAt;
  final String productId;
  final String productImage;
  final String buyerId;
  final String sellerId;
  final String buyerHandle;
  final String sellerHandle;
  final String buyerAvatar;
  final String sellerAvatar;
  final int unreadCount;
  final List<ChatMessage> messages;

  factory MessageThread.fromJson(Map<String, dynamic> json) {
    return MessageThread(
      id: json['id'] as String,
      sellerName: json['sellerName'] as String? ?? 'Продавец',
      buyerName: json['buyerName'] as String? ?? 'Покупатель',
      productTitle: json['productTitle'] as String,
      lastMessage: json['lastMessage'] as String,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      productId: json['productId'] as String? ?? '',
      productImage: json['productImage'] as String? ?? '',
      buyerId: json['buyerId'] as String? ?? '',
      sellerId: json['sellerId'] as String? ?? '',
      buyerHandle: json['buyerHandle'] as String? ?? '',
      sellerHandle: json['sellerHandle'] as String? ?? '',
      buyerAvatar: json['buyerAvatar'] as String? ?? '',
      sellerAvatar: json['sellerAvatar'] as String? ?? '',
      unreadCount: json['unreadCount'] as int? ?? 0,
      messages:
          (json['messages'] as List<dynamic>?)
              ?.map(
                (item) => ChatMessage.fromJson(item as Map<String, dynamic>),
              )
              .toList() ??
          const [],
    );
  }

  factory MessageThread.fromSupabase(
    Map<String, dynamic> json, {
    String currentUserId = '',
  }) {
    return MessageThread(
      id: json['id'] as String,
      sellerName: json['seller_name'] as String? ?? 'Продавец',
      buyerName: json['buyer_name'] as String? ?? 'Покупатель',
      productTitle: json['product_title'] as String? ?? '',
      lastMessage: json['last_message'] as String? ?? '',
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
      productId: json['product_id'] as String? ?? '',
      productImage: json['product_image'] as String? ?? '',
      buyerId: json['buyer_id'] as String? ?? '',
      sellerId: json['seller_id'] as String? ?? '',
      buyerHandle: json['buyer_handle'] as String? ?? '',
      sellerHandle: json['seller_handle'] as String? ?? '',
      buyerAvatar: json['buyer_avatar'] as String? ?? '',
      sellerAvatar: json['seller_avatar'] as String? ?? '',
      unreadCount: json['unread_count'] as int? ?? 0,
      messages:
          (json['messages'] as List<dynamic>?)
              ?.map(
                (item) => ChatMessage.fromJson(
                  item as Map<String, dynamic>,
                  currentUserId: currentUserId,
                ),
              )
              .toList() ??
          const [],
    );
  }

  String otherPartyName(String currentUserId) {
    if (currentUserId.isNotEmpty && currentUserId == sellerId) {
      return buyerName.isEmpty ? 'Покупатель' : buyerName;
    }
    return sellerName.isEmpty ? 'Продавец' : sellerName;
  }

  String otherPartyHandle(String currentUserId) {
    if (currentUserId.isNotEmpty && currentUserId == sellerId) {
      return buyerHandle;
    }
    return sellerHandle;
  }

  String otherPartyAvatar(String currentUserId) {
    if (currentUserId.isNotEmpty && currentUserId == sellerId) {
      return buyerAvatar;
    }
    return sellerAvatar;
  }

  String otherPartyId(String currentUserId) {
    if (currentUserId.isNotEmpty && currentUserId == sellerId) {
      return buyerId;
    }
    return sellerId;
  }

  bool get isProductChat => productId.isNotEmpty;

  MessageThread copyWith({
    String? sellerName,
    String? buyerName,
    String? productTitle,
    String? lastMessage,
    DateTime? updatedAt,
    String? productId,
    String? productImage,
    String? buyerId,
    String? sellerId,
    String? buyerHandle,
    String? sellerHandle,
    String? buyerAvatar,
    String? sellerAvatar,
    int? unreadCount,
    List<ChatMessage>? messages,
  }) {
    return MessageThread(
      id: id,
      sellerName: sellerName ?? this.sellerName,
      buyerName: buyerName ?? this.buyerName,
      productTitle: productTitle ?? this.productTitle,
      lastMessage: lastMessage ?? this.lastMessage,
      updatedAt: updatedAt ?? this.updatedAt,
      productId: productId ?? this.productId,
      productImage: productImage ?? this.productImage,
      buyerId: buyerId ?? this.buyerId,
      sellerId: sellerId ?? this.sellerId,
      buyerHandle: buyerHandle ?? this.buyerHandle,
      sellerHandle: sellerHandle ?? this.sellerHandle,
      buyerAvatar: buyerAvatar ?? this.buyerAvatar,
      sellerAvatar: sellerAvatar ?? this.sellerAvatar,
      unreadCount: unreadCount ?? this.unreadCount,
      messages: messages ?? this.messages,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sellerName': sellerName,
      'buyerName': buyerName,
      'productTitle': productTitle,
      'lastMessage': lastMessage,
      'updatedAt': updatedAt.toIso8601String(),
      'productId': productId,
      'productImage': productImage,
      'buyerId': buyerId,
      'sellerId': sellerId,
      'buyerHandle': buyerHandle,
      'sellerHandle': sellerHandle,
      'buyerAvatar': buyerAvatar,
      'sellerAvatar': sellerAvatar,
      'unreadCount': unreadCount,
      'messages': messages.map((message) => message.toJson()).toList(),
    };
  }

  Map<String, dynamic> toSupabaseJson() {
    return {
      'id': id,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': productId,
      'seller_name': sellerName,
      'buyer_name': buyerName,
      'product_title': productTitle,
      'product_image': productImage,
      'buyer_handle': buyerHandle,
      'seller_handle': sellerHandle,
      'buyer_avatar': buyerAvatar,
      'seller_avatar': sellerAvatar,
      'last_message': lastMessage,
      'updated_at': updatedAt.toIso8601String(),
      'unread_count': unreadCount,
      'messages': messages.map((message) => message.toSupabaseJson()).toList(),
    };
  }
}
