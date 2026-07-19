const Object _chatUnset = Object();

enum ChatMediaKind { image, video }

class ChatAttachment {
  const ChatAttachment({
    required this.url,
    this.name = '',
    this.mimeType = '',
    this.size = 0,
    this.width,
    this.height,
    this.durationMs,
    this.bucket = '',
    this.storagePath = '',
    this.thumbnailUrl = '',
  });

  final String url;
  final String name;
  final String mimeType;
  final int size;
  final int? width;
  final int? height;
  final int? durationMs;
  final String bucket;
  final String storagePath;
  final String thumbnailUrl;

  bool get isImage =>
      mimeType.toLowerCase().startsWith('image/') ||
      RegExp(
        r'\.(jpe?g|png|webp|gif|heic|heif)$',
        caseSensitive: false,
      ).hasMatch(name.isNotEmpty ? name : url);

  bool get isVideo =>
      mimeType.toLowerCase().startsWith('video/') ||
      RegExp(
        r'\.(mp4|mov|m4v|webm)$',
        caseSensitive: false,
      ).hasMatch(name.isNotEmpty ? name : url);

  bool get hasRemoteObject => bucket.isNotEmpty && storagePath.isNotEmpty;

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      url: json['url'] as String? ?? '',
      name: json['name'] as String? ?? '',
      mimeType:
          json['mime_type'] as String? ?? json['mimeType'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      durationMs:
          (json['duration_ms'] as num?)?.toInt() ??
          (json['durationMs'] as num?)?.toInt(),
      bucket: json['bucket'] as String? ?? '',
      storagePath:
          json['storage_path'] as String? ??
          json['storagePath'] as String? ??
          '',
      thumbnailUrl:
          json['thumbnail_url'] as String? ??
          json['thumbnailUrl'] as String? ??
          '',
    );
  }

  ChatAttachment copyWith({
    String? url,
    String? name,
    String? mimeType,
    int? size,
    Object? width = _chatUnset,
    Object? height = _chatUnset,
    Object? durationMs = _chatUnset,
    String? bucket,
    String? storagePath,
    String? thumbnailUrl,
  }) {
    return ChatAttachment(
      url: url ?? this.url,
      name: name ?? this.name,
      mimeType: mimeType ?? this.mimeType,
      size: size ?? this.size,
      width: identical(width, _chatUnset) ? this.width : width as int?,
      height: identical(height, _chatUnset) ? this.height : height as int?,
      durationMs: identical(durationMs, _chatUnset)
          ? this.durationMs
          : durationMs as int?,
      bucket: bucket ?? this.bucket,
      storagePath: storagePath ?? this.storagePath,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'name': name,
    'mime_type': mimeType,
    'size': size,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (durationMs != null) 'duration_ms': durationMs,
    if (bucket.isNotEmpty) 'bucket': bucket,
    if (storagePath.isNotEmpty) 'storage_path': storagePath,
    if (thumbnailUrl.isNotEmpty) 'thumbnail_url': thumbnailUrl,
  };

  Map<String, dynamic> toSupabaseJson() => {
    'name': name,
    'mime_type': mimeType,
    'size': size,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (durationMs != null) 'duration_ms': durationMs,
    if (bucket.isNotEmpty) 'bucket': bucket,
    if (storagePath.isNotEmpty) 'storage_path': storagePath,
  };
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.isMine,
    this.senderId = '',
    this.senderName = '',
    this.senderAvatar = '',
    this.type = 'text',
    this.sharedProduct,
    this.attachment,
    this.replyToId = '',
    this.replyToText = '',
    this.replyToSenderName = '',
    this.editedAt,
    this.deletedAt,
    this.readBy = const [],
    this.reactions = const {},
    this.isPending = false,
    this.hasError = false,
  });

  final String id;
  final String text;
  final DateTime createdAt;
  final bool isMine;
  final String senderId;
  final String senderName;
  final String senderAvatar;
  final String type;
  final SharedProductPreview? sharedProduct;
  final ChatAttachment? attachment;
  final String replyToId;
  final String replyToText;
  final String replyToSenderName;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final List<String> readBy;
  final Map<String, List<String>> reactions;
  final bool isPending;
  final bool hasError;

  bool get isProductShare => type == 'product' && sharedProduct != null;
  bool get isImage => type == 'image' && attachment?.isImage == true;
  bool get isVideo => type == 'video' && attachment?.isVideo == true;
  bool get isMedia => isImage || isVideo;
  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null && !isDeleted;
  bool get isReply => replyToId.isNotEmpty;
  int get reactionCount =>
      reactions.values.fold<int>(0, (total, users) => total + users.length);
  bool isReadByAnotherUser() =>
      readBy.any((userId) => userId.isNotEmpty && userId != senderId);

  String get previewText {
    if (isDeleted) return 'Сообщение удалено';
    if (isImage) return text.trim().isEmpty ? 'Фотография' : text.trim();
    if (isVideo) return text.trim().isEmpty ? 'Видео' : text.trim();
    if (isProductShare) return text.trim().isEmpty ? 'Объявление' : text.trim();
    return text.trim();
  }

  factory ChatMessage.fromJson(
    Map<String, dynamic> json, {
    String currentUserId = '',
  }) {
    final senderId =
        json['sender_id'] as String? ?? json['senderId'] as String? ?? '';
    final rawProduct = json['product'];
    final sharedProduct = rawProduct is Map
        ? SharedProductPreview.fromJson(Map<String, dynamic>.from(rawProduct))
        : null;
    final rawAttachment = json['attachment'];
    final attachment = rawAttachment is Map
        ? ChatAttachment.fromJson(Map<String, dynamic>.from(rawAttachment))
        : null;
    final rawReply = json['reply_snapshot'] ?? json['replySnapshot'];
    final reply = rawReply is Map
        ? Map<String, dynamic>.from(rawReply)
        : const <String, dynamic>{};
    final rawReadBy = json['read_by'] ?? json['readBy'];
    return ChatMessage(
      id: json['id'] as String,
      text: json['text'] as String? ?? '',
      createdAt:
          DateTime.tryParse(
            json['created_at'] as String? ?? json['createdAt'] as String? ?? '',
          ) ??
          DateTime.now(),
      isMine: currentUserId.isNotEmpty
          ? senderId == currentUserId
          : json['isMine'] as bool? ?? true,
      senderId: senderId,
      senderName:
          json['sender_name'] as String? ?? json['senderName'] as String? ?? '',
      senderAvatar:
          json['sender_avatar'] as String? ??
          json['senderAvatar'] as String? ??
          '',
      type:
          json['type'] as String? ??
          (sharedProduct != null
              ? 'product'
              : attachment?.isVideo == true
              ? 'video'
              : attachment?.isImage == true
              ? 'image'
              : 'text'),
      sharedProduct: sharedProduct,
      attachment: attachment,
      replyToId:
          json['reply_to_id'] as String? ?? json['replyToId'] as String? ?? '',
      replyToText:
          reply['text'] as String? ?? json['replyToText'] as String? ?? '',
      replyToSenderName:
          reply['sender_name'] as String? ??
          reply['senderName'] as String? ??
          json['replyToSenderName'] as String? ??
          '',
      editedAt: _parseOptionalDate(json['edited_at'] ?? json['editedAt']),
      deletedAt: _parseOptionalDate(json['deleted_at'] ?? json['deletedAt']),
      readBy: rawReadBy is List
          ? rawReadBy.whereType<String>().toList(growable: false)
          : const [],
      reactions: _parseReactions(json['reactions']),
      isPending: json['isPending'] as bool? ?? false,
      hasError: json['hasError'] as bool? ?? false,
    );
  }

  static DateTime? _parseOptionalDate(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  static Map<String, List<String>> _parseReactions(dynamic value) {
    if (value is! Map) return const {};
    final parsed = <String, List<String>>{};
    for (final entry in value.entries) {
      final users = entry.value;
      if (users is! List) continue;
      final ids = users.whereType<String>().toList(growable: false);
      if (ids.isNotEmpty) parsed[entry.key.toString()] = ids;
    }
    return parsed;
  }

  ChatMessage copyWith({
    String? text,
    DateTime? createdAt,
    bool? isMine,
    String? senderId,
    String? senderName,
    String? senderAvatar,
    String? type,
    Object? sharedProduct = _chatUnset,
    Object? attachment = _chatUnset,
    String? replyToId,
    String? replyToText,
    String? replyToSenderName,
    Object? editedAt = _chatUnset,
    Object? deletedAt = _chatUnset,
    List<String>? readBy,
    Map<String, List<String>>? reactions,
    bool? isPending,
    bool? hasError,
  }) {
    return ChatMessage(
      id: id,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      isMine: isMine ?? this.isMine,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      type: type ?? this.type,
      sharedProduct: identical(sharedProduct, _chatUnset)
          ? this.sharedProduct
          : sharedProduct as SharedProductPreview?,
      attachment: identical(attachment, _chatUnset)
          ? this.attachment
          : attachment as ChatAttachment?,
      replyToId: replyToId ?? this.replyToId,
      replyToText: replyToText ?? this.replyToText,
      replyToSenderName: replyToSenderName ?? this.replyToSenderName,
      editedAt: identical(editedAt, _chatUnset)
          ? this.editedAt
          : editedAt as DateTime?,
      deletedAt: identical(deletedAt, _chatUnset)
          ? this.deletedAt
          : deletedAt as DateTime?,
      readBy: readBy ?? this.readBy,
      reactions: reactions ?? this.reactions,
      isPending: isPending ?? this.isPending,
      hasError: hasError ?? this.hasError,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'isMine': isMine,
      'senderId': senderId,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'type': type,
      if (sharedProduct != null) 'product': sharedProduct!.toJson(),
      if (attachment != null) 'attachment': attachment!.toJson(),
      'replyToId': replyToId,
      if (isReply)
        'replySnapshot': {
          'text': replyToText,
          'sender_name': replyToSenderName,
        },
      if (editedAt != null) 'editedAt': editedAt!.toUtc().toIso8601String(),
      if (deletedAt != null) 'deletedAt': deletedAt!.toUtc().toIso8601String(),
      'readBy': readBy,
      'reactions': reactions,
      'isPending': isPending,
      'hasError': hasError,
    };
  }

  Map<String, dynamic> toSupabaseJson() {
    return {
      'id': id,
      'text': text,
      'created_at': createdAt.toUtc().toIso8601String(),
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_avatar': senderAvatar,
      'type': type,
      if (sharedProduct != null) 'product': sharedProduct!.toJson(),
      if (attachment != null) 'attachment': attachment!.toSupabaseJson(),
      if (isReply) 'reply_to_id': replyToId,
      if (isReply)
        'reply_snapshot': {
          'text': replyToText,
          'sender_name': replyToSenderName,
        },
    };
  }
}

class SharedProductPreview {
  const SharedProductPreview({
    required this.id,
    required this.title,
    required this.image,
    required this.price,
    this.sellerHandle = '',
  });

  final String id;
  final String title;
  final String image;
  final String price;
  final String sellerHandle;

  factory SharedProductPreview.fromJson(Map<String, dynamic> json) {
    return SharedProductPreview(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      image: json['image'] as String? ?? '',
      price: json['price']?.toString() ?? '',
      sellerHandle: json['seller_handle'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'image': image,
    'price': price,
    'seller_handle': sellerHandle,
  };
}

class ConversationMember {
  const ConversationMember({
    required this.id,
    required this.name,
    required this.handle,
    this.avatarUrl = '',
  });

  final String id;
  final String name;
  final String handle;
  final String avatarUrl;

  factory ConversationMember.fromJson(Map<String, dynamic> json) {
    return ConversationMember(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      handle: json['handle'] as String? ?? '',
      avatarUrl:
          json['avatar_url'] as String? ?? json['avatarUrl'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'handle': handle,
    'avatar_url': avatarUrl,
  };
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
    this.isGroup = false,
    this.title = '',
    this.groupAvatar = '',
    this.createdBy = '',
    this.members = const [],
    this.isPinned = false,
    this.isMuted = false,
    this.isArchived = false,
    this.draft = '',
    this.lastReadAt,
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
  final bool isGroup;
  final String title;
  final String groupAvatar;
  final String createdBy;
  final List<ConversationMember> members;
  final bool isPinned;
  final bool isMuted;
  final bool isArchived;
  final String draft;
  final DateTime? lastReadAt;

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
      isGroup: json['isGroup'] as bool? ?? false,
      title: json['title'] as String? ?? '',
      groupAvatar: json['groupAvatar'] as String? ?? '',
      createdBy: json['createdBy'] as String? ?? '',
      members: _parseMembers(json['members']),
      isPinned: json['isPinned'] as bool? ?? false,
      isMuted: json['isMuted'] as bool? ?? false,
      isArchived: json['isArchived'] as bool? ?? false,
      draft: json['draft'] as String? ?? '',
      lastReadAt: ChatMessage._parseOptionalDate(json['lastReadAt']),
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
      isGroup: json['is_group'] as bool? ?? false,
      title: json['title'] as String? ?? '',
      groupAvatar: json['group_avatar'] as String? ?? '',
      createdBy: json['created_by'] as String? ?? '',
      members: _parseMembers(json['members'], memberIds: json['member_ids']),
      // Remote preferences and drafts live in chat_thread_member_state and are
      // hydrated by AppRepository for the authenticated participant. Never
      // consume the deprecated shared columns from message_threads here.
      isPinned: false,
      isMuted: false,
      isArchived: false,
      draft: '',
      lastReadAt: null,
    );
  }

  static List<ConversationMember> _parseMembers(
    dynamic value, {
    dynamic memberIds,
  }) {
    final parsed = value is List
        ? value
              .whereType<Map>()
              .map(
                (item) => ConversationMember.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((member) => member.id.isNotEmpty)
              .toList()
        : <ConversationMember>[];
    final knownIds = parsed.map((member) => member.id).toSet();
    if (memberIds is List) {
      for (final id in memberIds.whereType<String>()) {
        if (id.isNotEmpty && knownIds.add(id)) {
          parsed.add(ConversationMember(id: id, name: '', handle: ''));
        }
      }
    }
    return List.unmodifiable(parsed);
  }

  List<String> get memberIds {
    final ids = <String>{
      if (buyerId.isNotEmpty) buyerId,
      if (sellerId.isNotEmpty) sellerId,
      ...members.map((member) => member.id).where((id) => id.isNotEmpty),
    };
    return ids.toList(growable: false);
  }

  bool containsUser(String userId) {
    if (userId.isEmpty) return false;
    return memberIds.contains(userId);
  }

  String displayTitle(String currentUserId) {
    if (!isGroup) return otherPartyName(currentUserId);
    if (title.trim().isNotEmpty) return title.trim();
    final names = members
        .where((member) => member.id != currentUserId)
        .map((member) => member.name.trim())
        .where((name) => name.isNotEmpty)
        .take(3)
        .toList();
    return names.isEmpty ? 'Беседа' : names.join(', ');
  }

  String displaySubtitle(String currentUserId) {
    if (!isGroup) return otherPartyHandle(currentUserId);
    final count = memberIds.length;
    return '$count ${_memberWord(count)}';
  }

  String displayAvatar(String currentUserId) {
    return isGroup ? groupAvatar : otherPartyAvatar(currentUserId);
  }

  String avatarForUser(String userId) {
    if (userId.isEmpty) return '';
    final storedAvatar = userId == buyerId
        ? buyerAvatar
        : userId == sellerId
        ? sellerAvatar
        : '';
    if (storedAvatar.trim().isNotEmpty) return storedAvatar.trim();

    final memberAvatar = memberById(userId)?.avatarUrl.trim() ?? '';
    if (memberAvatar.isNotEmpty) return memberAvatar;

    for (final message in messages.reversed) {
      if (message.senderId == userId &&
          message.senderAvatar.trim().isNotEmpty) {
        return message.senderAvatar.trim();
      }
    }
    return '';
  }

  ConversationMember? memberById(String userId) {
    for (final member in members) {
      if (member.id == userId) return member;
    }
    return null;
  }

  static String _memberWord(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return 'участник';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'участника';
    }
    return 'участников';
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
    return avatarForUser(otherPartyId(currentUserId));
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
    bool? isGroup,
    String? title,
    String? groupAvatar,
    String? createdBy,
    List<ConversationMember>? members,
    bool? isPinned,
    bool? isMuted,
    bool? isArchived,
    String? draft,
    Object? lastReadAt = _chatUnset,
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
      isGroup: isGroup ?? this.isGroup,
      title: title ?? this.title,
      groupAvatar: groupAvatar ?? this.groupAvatar,
      createdBy: createdBy ?? this.createdBy,
      members: members ?? this.members,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      isArchived: isArchived ?? this.isArchived,
      draft: draft ?? this.draft,
      lastReadAt: identical(lastReadAt, _chatUnset)
          ? this.lastReadAt
          : lastReadAt as DateTime?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sellerName': sellerName,
      'buyerName': buyerName,
      'productTitle': productTitle,
      'lastMessage': lastMessage,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
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
      'isGroup': isGroup,
      'title': title,
      'groupAvatar': groupAvatar,
      'createdBy': createdBy,
      'members': members.map((member) => member.toJson()).toList(),
      'isPinned': isPinned,
      'isMuted': isMuted,
      'isArchived': isArchived,
      'draft': draft,
      if (lastReadAt != null)
        'lastReadAt': lastReadAt!.toUtc().toIso8601String(),
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
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'is_group': isGroup,
      'title': title,
      'group_avatar': groupAvatar,
      'created_by': createdBy.isEmpty ? null : createdBy,
      'member_ids': memberIds,
      'members': members.map((member) => member.toJson()).toList(),
    };
  }
}
