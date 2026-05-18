class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.isMine,
  });

  final String id;
  final String text;
  final DateTime createdAt;
  final bool isMine;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      isMine: json['isMine'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      'isMine': isMine,
    };
  }
}

class MessageThread {
  const MessageThread({
    required this.id,
    required this.sellerName,
    required this.productTitle,
    required this.lastMessage,
    required this.updatedAt,
    this.unreadCount = 0,
    this.messages = const [],
  });

  final String id;
  final String sellerName;
  final String productTitle;
  final String lastMessage;
  final DateTime updatedAt;
  final int unreadCount;
  final List<ChatMessage> messages;

  factory MessageThread.fromJson(Map<String, dynamic> json) {
    return MessageThread(
      id: json['id'] as String,
      sellerName: json['sellerName'] as String,
      productTitle: json['productTitle'] as String,
      lastMessage: json['lastMessage'] as String,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      unreadCount: json['unreadCount'] as int? ?? 0,
      messages: (json['messages'] as List<dynamic>?)
              ?.map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  factory MessageThread.fromSupabase(Map<String, dynamic> json) {
    return MessageThread(
      id: json['id'] as String,
      sellerName: json['seller_name'] as String? ?? 'Продавец',
      productTitle: json['product_title'] as String? ?? '',
      lastMessage: json['last_message'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
      unreadCount: json['unread_count'] as int? ?? 0,
      messages: (json['messages'] as List<dynamic>?)
              ?.map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  MessageThread copyWith({
    String? lastMessage,
    DateTime? updatedAt,
    int? unreadCount,
    List<ChatMessage>? messages,
  }) {
    return MessageThread(
      id: id,
      sellerName: sellerName,
      productTitle: productTitle,
      lastMessage: lastMessage ?? this.lastMessage,
      updatedAt: updatedAt ?? this.updatedAt,
      unreadCount: unreadCount ?? this.unreadCount,
      messages: messages ?? this.messages,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sellerName': sellerName,
      'productTitle': productTitle,
      'lastMessage': lastMessage,
      'updatedAt': updatedAt.toIso8601String(),
      'unreadCount': unreadCount,
      'messages': messages.map((message) => message.toJson()).toList(),
    };
  }

  Map<String, dynamic> toSupabaseJson() {
    return {
      'id': id,
      'seller_name': sellerName,
      'product_title': productTitle,
      'last_message': lastMessage,
      'updated_at': updatedAt.toIso8601String(),
      'unread_count': unreadCount,
      'messages': messages.map((message) => message.toJson()).toList(),
    };
  }
}
