import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../core/oauth_callback.dart';
import '../core/supabase_config.dart';
import '../features/chat/chat_media_send_coordinator.dart';
import '../features/chat/chat_media_url_cache.dart';
import '../features/chat/chat_remote_write_coordinator.dart';
import '../features/chat/chat_sync_coordinator.dart';
import '../models/app_profile.dart';
import '../models/created_outfit.dart';
import '../models/message_thread.dart';
import '../models/outfit_accessory.dart';
import '../models/product.dart';
import '../models/profile_feature.dart';
import '../services/push_notification_service.dart';

class MessageNotification {
  const MessageNotification({
    required this.id,
    required this.threadId,
    required this.senderName,
    required this.text,
  });

  final String id;
  final String threadId;
  final String senderName;
  final String text;
}

class AppRepository extends ChangeNotifier {
  static const _productsKey = 'products_v4';
  static const _accessoriesKey = 'outfit_accessories_v1';
  static const _outfitsKey = 'outfits_v2';
  static const _threadsKey = 'threads_v2';
  static const _profileKey = 'profile_v1';
  static const _favoriteProductIdsKey = 'favorite_product_ids_v1';
  static const _favoriteOutfitIdsKey = 'favorite_outfit_ids_v1';
  static const _followedSellerIdsKey = 'followed_seller_ids_v1';
  static const _recentProductIdsKey = 'recent_product_ids_v1';
  static const _recentOutfitIdsKey = 'recent_outfit_ids_v1';
  static const _countedProductViewsKeyPrefix = 'counted_product_views_v1';
  static const _countedOutfitViewsKeyPrefix = 'counted_outfit_views_v1';
  static const _blockedUserIdsKeyPrefix = 'blocked_user_ids_v1';
  static const _notificationsKey = 'profile_notifications_v1';
  static const _notificationPreferencesKey = 'notification_preferences_v1';
  static const _deliveryProfileKey = 'delivery_profile_v1';
  static const _ordersKey = 'orders_v1';
  static const _checkoutAttemptKeyPrefix = 'checkout_attempt_v1';
  static const _sellerReviewsKey = 'seller_reviews_v1';
  static const _scopedStorageMigrationKey = 'user_storage_scoped_v1';
  static const _scopedUserStorageKeys = <String>[
    _threadsKey,
    _profileKey,
    _favoriteProductIdsKey,
    _favoriteOutfitIdsKey,
    _followedSellerIdsKey,
    _recentProductIdsKey,
    _recentOutfitIdsKey,
    _notificationsKey,
    _notificationPreferencesKey,
    _deliveryProfileKey,
    _ordersKey,
    _sellerReviewsKey,
  ];
  static const _bucketName = 'product-images';
  static const _chatMediaBucketName = 'chat-media';
  static const _maxChatImageBytes = 20 * 1024 * 1024;
  static const _maxChatVideoBytes = 100 * 1024 * 1024;
  static const _chatMediaSignedUrlSeconds = 60 * 60;
  static const _chatHydrationBatchSize = 40;
  static const _chatHydrationPageSize = 500;

  @visibleForTesting
  static List<AppOrder> mergeOrdersForParticipant({
    required Iterable<AppOrder> localOrders,
    required Iterable<AppOrder> remoteOrders,
    required String participantId,
  }) {
    final normalizedParticipantId = participantId.trim();
    if (normalizedParticipantId.isEmpty) return const <AppOrder>[];

    bool belongsToParticipant(AppOrder order) {
      return order.buyerId == normalizedParticipantId ||
          order.sellerId == normalizedParticipantId;
    }

    final localById = <String, AppOrder>{};
    for (final order in localOrders.where(belongsToParticipant)) {
      final previous = localById[order.id];
      if (previous == null || order.updatedAt.isAfter(previous.updatedAt)) {
        localById[order.id] = order;
      }
    }

    final remoteById = <String, AppOrder>{};
    for (final order in remoteOrders.where(belongsToParticipant)) {
      final previous = remoteById[order.id];
      if (previous == null || order.updatedAt.isAfter(previous.updatedAt)) {
        remoteById[order.id] = order;
      }
    }

    // Preserve participant orders missing from a possibly stale remote
    // snapshot, while making returned rows authoritative for matching ids.
    final mergedById = <String, AppOrder>{...localById, ...remoteById};
    final merged = mergedById.values.toList()
      ..sort((left, right) {
        final byUpdatedAt = right.updatedAt.compareTo(left.updatedAt);
        if (byUpdatedAt != 0) return byUpdatedAt;
        final byCreatedAt = right.createdAt.compareTo(left.createdAt);
        if (byCreatedAt != 0) return byCreatedAt;
        return left.id.compareTo(right.id);
      });
    return merged;
  }

  @visibleForTesting
  static bool hasCompletedOrderForReview({
    required Iterable<AppOrder> orders,
    required String buyerId,
    required String sellerId,
    required String productId,
  }) {
    final normalizedBuyerId = buyerId.trim();
    final normalizedSellerId = sellerId.trim();
    final normalizedProductId = productId.trim();
    if (normalizedBuyerId.isEmpty ||
        normalizedSellerId.isEmpty ||
        normalizedProductId.isEmpty ||
        normalizedBuyerId == normalizedSellerId) {
      return false;
    }
    return orders.any(
      (order) =>
          order.buyerId == normalizedBuyerId &&
          order.sellerId == normalizedSellerId &&
          order.productId == normalizedProductId &&
          order.status == AppOrderStatus.completed,
    );
  }

  @visibleForTesting
  static String userScopedStorageKey(String baseKey, String userId) {
    final identity = userId.trim();
    return '$baseKey:${identity.isEmpty ? 'guest' : identity}';
  }

  late final SharedPreferences _prefs;
  final _uuid = const Uuid();

  bool _isReady = false;
  List<Product> _products = [];
  List<OutfitAccessory> _accessories = [];
  List<CreatedOutfit> _outfits = [];
  List<MessageThread> _threads = [];
  List<ProfileNotification> _notifications = [];
  List<AppOrder> _orders = [];
  List<SellerReview> _sellerReviews = [];
  Set<String> _favoriteProductIds = {};
  Set<String> _favoriteOutfitIds = {};
  Set<String> _followedSellerIds = {};
  List<String> _recentProductIds = [];
  List<String> _recentOutfitIds = [];
  Set<String> _countedProductViewIds = {};
  String _countedProductViewsUserId = '';
  Set<String> _countedOutfitViewIds = {};
  String _countedOutfitViewsUserId = '';
  Set<String> _blockedUserIds = {};
  String _blockedUsersUserId = '';
  User? _currentUser;
  bool _isSigningIn = false;
  String? _authError;
  MessageNotification? _latestMessageNotification;
  NotificationPreferences _notificationPreferences =
      const NotificationPreferences();
  DeliveryProfile _deliveryProfile = const DeliveryProfile();
  bool _hasCompletedThreadSync = false;
  bool _isThreadSyncPending = false;
  String? _threadSyncError;
  String? _activeThreadId;
  final Map<String, DateTime> _lastSeenByUserId = {};
  AppProfile _profile = const AppProfile(
    name: 'Ваш профиль',
    handle: '@seller',
    city: 'Москва',
    rating: 0,
    salesCount: 0,
    followersCount: 0,
  );
  Timer? _syncTimer;
  StreamSubscription<AuthState>? _authSubscription;
  Future<User?>? _sessionRefreshInFlight;
  StreamSubscription<String>? _pushTokenSubscription;
  RealtimeChannel? _messagesChannel;
  int _messageSubscriptionGeneration = 0;
  final ChatMediaUrlCache _chatMediaUrlCache = ChatMediaUrlCache(
    timeToLive: const Duration(seconds: _chatMediaSignedUrlSeconds),
  );
  final ChatMediaSendCoordinator _chatMediaSendCoordinator =
      const ChatMediaSendCoordinator();
  final ChatRemoteWriteCoordinator _chatRemoteWriteCoordinator =
      const ChatRemoteWriteCoordinator();
  final ChatSyncCoordinator _chatThreadSync = ChatSyncCoordinator();
  final Set<String> _knownRemoteThreadIds = <String>{};
  String? _registeredPushToken;

  bool get isReady => _isReady;
  bool get isThreadSyncPending => _isThreadSyncPending;
  String? get threadSyncError => _threadSyncError;
  List<Product> get products => List.unmodifiable(
    _products.where(
      (product) =>
          product.ownerId.isEmpty || !_blockedUserIds.contains(product.ownerId),
    ),
  );
  List<Product> get likedProducts {
    return List.unmodifiable(
      _products
          .where(
            (product) =>
                _favoriteProductIds.contains(product.id) &&
                !product.isHidden &&
                !_blockedUserIds.contains(product.ownerId),
          )
          .toList(),
    );
  }

  List<Product> get recentlyViewedProducts {
    final productsById = {for (final product in _products) product.id: product};
    return List.unmodifiable(
      _recentProductIds
          .map((id) => productsById[id])
          .whereType<Product>()
          .where(
            (product) =>
                !product.isHidden && !_blockedUserIds.contains(product.ownerId),
          )
          .toList(),
    );
  }

  List<OutfitAccessory> get defaultAccessories {
    return List.unmodifiable(
      _accessories.where((item) => item.isDefault).toList(),
    );
  }

  List<OutfitAccessory> get myAccessories {
    if (currentUserId.isEmpty) return const [];
    return List.unmodifiable(
      _accessories
          .where((item) => !item.isDefault && item.ownerId == currentUserId)
          .toList(),
    );
  }

  List<CreatedOutfit> get outfits => List.unmodifiable(
    _outfits.where(
      (outfit) =>
          outfit.ownerId.isEmpty || !_blockedUserIds.contains(outfit.ownerId),
    ),
  );
  List<CreatedOutfit> get likedOutfits {
    return List.unmodifiable(
      _outfits
          .where(
            (outfit) =>
                _favoriteOutfitIds.contains(outfit.id) &&
                !_blockedUserIds.contains(outfit.ownerId),
          )
          .toList(),
    );
  }

  List<CreatedOutfit> get recentlyViewedOutfits {
    final outfitsById = {for (final outfit in _outfits) outfit.id: outfit};
    return List.unmodifiable(
      _recentOutfitIds
          .map((id) => outfitsById[id])
          .whereType<CreatedOutfit>()
          .where((outfit) => !_blockedUserIds.contains(outfit.ownerId))
          .toList(),
    );
  }

  Future<void> clearRecentlyViewed() async {
    _recentProductIds.clear();
    _recentOutfitIds.clear();
    await Future.wait([
      _writeStringList(
        _scopedStorageKey(_recentProductIdsKey),
        _recentProductIds,
      ),
      _writeStringList(
        _scopedStorageKey(_recentOutfitIdsKey),
        _recentOutfitIds,
      ),
    ]);
    notifyListeners();

    final userId = currentUserId;
    if (!_hasSupabase || userId.isEmpty) return;
    try {
      await _client.from('recent_products').delete().eq('user_id', userId);
    } catch (e) {
      debugPrint('Recent products clear error: $e');
    }
    try {
      await _client.from('recent_outfits').delete().eq('user_id', userId);
    } catch (e) {
      debugPrint('Recent outfits clear error: $e');
    }
  }

  List<MessageThread> get threads {
    if (!_hasSupabase || currentUserId.isEmpty) {
      return List.unmodifiable(_threads);
    }
    return List.unmodifiable(
      _threads.where(
        (thread) =>
            thread.containsUser(currentUserId) &&
            (thread.isGroup ||
                thread.otherPartyId(currentUserId).trim().isNotEmpty) &&
            !_isBlockedThread(thread),
      ),
    );
  }

  int get unreadMessageCount => threads.fold<int>(
    0,
    (total, thread) => total + thread.unreadCount.clamp(0, 9999),
  );

  AppProfile get profile => _profile;
  bool canFollowSeller(String sellerId) {
    final normalized = sellerId.trim();
    return normalized.isNotEmpty && normalized != currentUserId;
  }

  bool isFollowingSeller(String sellerId) =>
      _followedSellerIds.contains(sellerId.trim());
  List<ProfileNotification> get notifications => List.unmodifiable(
    _notifications.where(
      (notification) =>
          notification.kind != 'message' &&
          (notification.title.trim().isNotEmpty ||
              notification.body.trim().isNotEmpty),
    ),
  );
  NotificationPreferences get notificationPreferences =>
      _notificationPreferences;
  DeliveryProfile get deliveryProfile => _deliveryProfileWithFallbacks();
  List<AppOrder> get orders => List.unmodifiable(_orders);
  List<SellerReview> get sellerReviews => List.unmodifiable(_sellerReviews);
  User? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;
  bool get isSigningIn => _isSigningIn;
  String? get authError => _authError;
  MessageNotification? get latestMessageNotification =>
      _latestMessageNotification;
  bool isChatThreadVisible(String threadId) => _activeThreadId == threadId;
  String get currentUserId => _currentUser?.id ?? '';
  DateTime? lastSeenForUser(String userId) => _lastSeenByUserId[userId];

  void setChatThreadVisibility(String threadId, bool isVisible) {
    if (isVisible) {
      _activeThreadId = threadId;
    } else if (_activeThreadId == threadId) {
      _activeThreadId = null;
    }
  }

  Future<void> refreshCurrentProfile() async {
    final user = _currentUser;
    if (user != null) await _applyUserProfile(user);
  }

  DeliveryProfile _deliveryProfileWithFallbacks() {
    final metadata = _currentUser?.userMetadata ?? const {};
    final email = _currentUser?.email ?? '';
    final metadataName =
        metadata['full_name']?.toString() ?? metadata['name']?.toString() ?? '';
    return _deliveryProfile.copyWith(
      fullName: _deliveryProfile.fullName.trim().isNotEmpty
          ? _deliveryProfile.fullName
          : (_profile.name.trim().isNotEmpty ? _profile.name : metadataName),
      email: _deliveryProfile.email.trim().isNotEmpty
          ? _deliveryProfile.email
          : email,
      city: _deliveryProfile.city.trim().isNotEmpty
          ? _deliveryProfile.city
          : _profile.city,
    );
  }

  MessageThread? threadById(String threadId) {
    for (final thread in _threads) {
      if (thread.id != threadId) continue;
      if (_hasSupabase &&
          currentUserId.isNotEmpty &&
          !thread.containsUser(currentUserId)) {
        return null;
      }
      return thread;
    }
    return null;
  }

  List<Product> get myProducts {
    if (currentUserId.isEmpty) return [];
    return _products
        .where(
          (product) => product.ownerId == currentUserId && !product.isHidden,
        )
        .toList();
  }

  List<Product> productsBySellerId(String sellerId) {
    if (sellerId.isEmpty || _blockedUserIds.contains(sellerId)) return const [];
    return _products.where((product) => product.ownerId == sellerId).toList();
  }

  bool isUserBlocked(String userId) => _blockedUserIds.contains(userId);

  bool _isBlockedThread(MessageThread thread) {
    if (_blockedUserIds.isEmpty || currentUserId.isEmpty) return false;
    final otherPartyId = thread.otherPartyId(currentUserId);
    return otherPartyId.isNotEmpty && _blockedUserIds.contains(otherPartyId);
  }

  Future<SellerProfile?> fetchSellerProfile(Product product) async {
    final sellerId = product.ownerId;
    if (sellerId.isEmpty) {
      return SellerProfile(
        id: '',
        name: product.sellerName,
        handle: product.sellerHandle,
      );
    }

    if (_hasSupabase) {
      try {
        final response = await _client
            .from('profiles')
            .select(
              'id,name,handle,avatar_url,city,rating,sales_count,followers_count',
            )
            .eq('id', sellerId)
            .limit(1);
        final rows = response as List<dynamic>;
        if (rows.isNotEmpty) {
          return SellerProfile.fromSupabase(rows.first as Map<String, dynamic>);
        }
      } catch (e) {
        debugPrint('Seller profile fetch error: $e');
      }
    }

    return SellerProfile(
      id: sellerId,
      name: product.sellerName,
      handle: product.sellerHandle,
    );
  }

  Future<List<Product>> fetchSellerProducts(String sellerId) async {
    if (sellerId.isEmpty) return const [];
    final localProducts = productsBySellerId(sellerId);

    if (!_hasSupabase) return localProducts;

    try {
      final response = await _client
          .from('products')
          .select()
          .eq('seller_id', sellerId)
          .order('created_at', ascending: false);
      final productRows = await _attachPublicAttributes(
        (response as List<dynamic>).whereType<Map>().toList(),
      );
      final remoteProducts = productRows
          .map(Product.fromSupabase)
          .where((product) => product.status == 'published')
          .toList();
      _products = [
        ...remoteProducts,
        ..._products.where((product) => product.ownerId != sellerId),
      ];
      _applyProductFavoriteState();
      await _saveProducts();
      notifyListeners();
      return productsBySellerId(sellerId);
    } catch (e) {
      debugPrint('Seller products fetch error: $e');
      return localProducts;
    }
  }

  Future<List<SellerReview>> fetchSellerReviews(String sellerId) async {
    if (sellerId.isEmpty) return const [];
    if (_hasSupabase) {
      try {
        final response = await _client
            .from('seller_reviews')
            .select()
            .eq('seller_id', sellerId)
            .order('created_at', ascending: false);
        final remote = response.map(SellerReview.fromJson).toList();
        _sellerReviews
          ..removeWhere((review) => review.sellerId == sellerId)
          ..addAll(remote);
        await _saveSellerReviewsLocal();
        return remote;
      } catch (e) {
        debugPrint('Seller reviews fetch error: $e');
      }
    }
    return _sellerReviews
        .where((review) => review.sellerId == sellerId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> createSellerReview({
    required String sellerId,
    required String productId,
    required String productTitle,
    required String productImage,
    required int rating,
    required String text,
    bool hasPhoto = false,
  }) async {
    final normalizedSellerId = sellerId.trim();
    final normalizedProductId = productId.trim();
    final user = _hasSupabase
        ? await _ensureAuthSession(
            message: 'Войдите в профиль, чтобы оставить отзыв',
          )
        : null;
    final buyerId = user?.id ?? '';
    if (buyerId.isEmpty) {
      throw const SellerReviewSubmissionException(
        'Войдите в профиль, чтобы оставить отзыв',
      );
    }
    if (normalizedSellerId.isEmpty || normalizedProductId.isEmpty) {
      throw const SellerReviewSubmissionException(
        'Не удалось определить сделку для отзыва',
      );
    }
    if (normalizedSellerId == buyerId) {
      throw const SellerReviewSubmissionException(
        'Нельзя оставить отзыв самому себе',
      );
    }

    try {
      final eligible = await _hasRemoteCompletedOrderForReview(
        buyerId: buyerId,
        sellerId: normalizedSellerId,
        productId: normalizedProductId,
      );
      if (!eligible) {
        throw const SellerReviewSubmissionException(
          'Отзыв можно оставить только после завершённой сделки',
        );
      }
    } on SellerReviewSubmissionException {
      rethrow;
    } catch (error) {
      debugPrint('Seller review eligibility check error: $error');
      throw const SellerReviewSubmissionException(
        'Не удалось проверить завершение сделки. Попробуйте ещё раз',
      );
    }

    final draft = SellerReview(
      id: '',
      sellerId: normalizedSellerId,
      buyerId: buyerId,
      buyerName: _profile.name,
      buyerAvatar: _currentAvatarUrl(),
      productId: normalizedProductId,
      productTitle: productTitle,
      productImage: productImage,
      rating: rating.clamp(1, 5),
      text: text.trim(),
      hasPhoto: hasPhoto,
      createdAt: DateTime.now().toUtc(),
    );
    late final SellerReview review;
    try {
      review = await _upsertSellerReviewToSupabase(draft);
    } catch (error) {
      debugPrint('Seller review save error: $error');
      throw const SellerReviewSubmissionException(
        'Не удалось сохранить отзыв. Попробуйте ещё раз',
      );
    }

    _sellerReviews.removeWhere(
      (item) =>
          item.buyerId == buyerId && item.productId == normalizedProductId,
    );
    _sellerReviews.insert(0, review);
    await _saveSellerReviewsLocal();
    notifyListeners();
  }

  Future<bool> _hasRemoteCompletedOrderForReview({
    required String buyerId,
    required String sellerId,
    required String productId,
  }) async {
    final response = await _client
        .from('orders')
        .select('id')
        .eq('buyer_id', buyerId)
        .eq('seller_id', sellerId)
        .eq('product_id', productId)
        .eq('status', AppOrderStatus.completed.name)
        .limit(1);
    return response.isNotEmpty;
  }

  Future<SellerReview> _upsertSellerReviewToSupabase(
    SellerReview review,
  ) async {
    final response = await _client
        .from('seller_reviews')
        .upsert({
          'seller_id': review.sellerId,
          'buyer_id': review.buyerId,
          'buyer_name': review.buyerName,
          'buyer_avatar': review.buyerAvatar,
          'product_id': review.productId,
          'product_title': review.productTitle,
          'product_image': review.productImage,
          'rating': review.rating,
          'text': review.text,
          'has_photo': review.hasPhoto,
          'deal_completed': true,
        }, onConflict: 'buyer_id,product_id')
        .select()
        .single();
    return SellerReview.fromJson(response);
  }

  List<CreatedOutfit> get myOutfits {
    if (currentUserId.isEmpty) return [];
    return _outfits.where((outfit) => outfit.ownerId == currentUserId).toList();
  }

  List<AppOrder> get myBuyingOrders {
    if (currentUserId.isEmpty) return const [];
    return _orders.where((order) => order.buyerId == currentUserId).toList();
  }

  List<AppOrder> get mySellingOrders {
    if (currentUserId.isEmpty) return const [];
    return _orders.where((order) => order.sellerId == currentUserId).toList();
  }

  SellerDashboardStats sellerDashboardStats() {
    final sellerOrders = mySellingOrders;
    final completed = sellerOrders
        .where((order) => order.status == AppOrderStatus.completed)
        .toList();
    final revenue = completed.fold<int>(
      0,
      (sum, order) => sum + order.productPriceValue,
    );
    final returns = sellerOrders
        .where(
          (order) =>
              order.status == AppOrderStatus.returning ||
              order.status == AppOrderStatus.canceled,
        )
        .length;
    final average = completed.isEmpty
        ? 0
        : (revenue / completed.length).round();
    final returnsPercent = sellerOrders.isEmpty
        ? 0.0
        : returns * 100 / sellerOrders.length;
    final rating = _profile.rating.clamp(0, 5).toDouble();
    final commission = rating >= 4.8
        ? 7
        : rating >= 4.4
        ? 9
        : 12;
    return SellerDashboardStats(
      rating: rating,
      commissionPercent: commission,
      revenue: revenue,
      ordersCount: sellerOrders.length,
      averageOrder: average,
      returnsPercent: returnsPercent,
    );
  }

  SupabaseClient get _client => SupabaseConfig.client;
  bool get _hasSupabase => SupabaseConfig.isInitialized;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    if (_hasSupabase) _currentUser = _client.auth.currentUser;

    // Load from local cache first for instant UI
    _products = _readList(_productsKey, Product.fromJson);
    final removedLegacyDemo = _products.any(
      (product) => product.id == 'product-uploaded-be8b281a',
    );
    _products.removeWhere(
      (product) => product.id == 'product-uploaded-be8b281a',
    );
    _accessories = _readList(_accessoriesKey, OutfitAccessory.fromJson);
    _outfits = _readList(_outfitsKey, CreatedOutfit.fromJson);
    await _migrateLegacyUserStorage();
    _loadLocalUserState();
    if (_hasSupabase) {
      _activateBlockedUserIdentity(_currentUser?.id ?? '');
      await _applyUserProfile(_currentUser, notify: false);
      if (_currentUser != null) {
        unawaited(_registerPushToken(_currentUser!.id));
        await _subscribeToMessages();
      }
      _authSubscription = _client.auth.onAuthStateChange.listen((state) {
        unawaited(_handleAuthState(state.session?.user));
      });
    }

    if (removedLegacyDemo) {
      await _saveProducts();
    }
    _sortThreads();
    _isReady = true;
    notifyListeners();

    if (_hasSupabase) {
      // Then sync from Supabase in background.
      _syncFromSupabase();
      _syncAccessoriesFromSupabase();
      _syncOutfitsFromSupabase();
      _syncBlockedUsers();
      _syncUserCollectionsFromSupabase();
      _syncProfileFeaturesFromSupabase();
      _updatePresence();
      unawaited(_chatThreadSync.runNow(_syncThreadsFromSupabase));
      _syncTimer ??= Timer.periodic(const Duration(seconds: 15), (timer) {
        if (timer.tick % 4 == 0) {
          _syncFromSupabase();
          _syncAccessoriesFromSupabase();
          _syncOutfitsFromSupabase();
          _syncBlockedUsers();
          _syncUserCollectionsFromSupabase();
          _syncProfileFeaturesFromSupabase();
          _updatePresence();
        }
        unawaited(_chatThreadSync.runNow(_syncThreadsFromSupabase));
      });
    }
  }

  Future<void> signInWithYandex() {
    return _signInWithSocialOAuth(
      authUrl: SupabaseConfig.yandexAuthUrl,
      providerLabel: 'Яндекс ID',
    );
  }

  Future<void> signInWithVk() {
    return _signInWithSocialOAuth(
      authUrl: SupabaseConfig.vkAuthUrl,
      providerLabel: 'VK ID',
    );
  }

  Future<String?> requestPhoneOtp(String phone) async {
    final normalizedPhone = phone.replaceAll(RegExp(r'[^+\d]'), '');
    if (!RegExp(r'^\+7\d{10}$').hasMatch(normalizedPhone)) {
      return 'Введите номер телефона полностью';
    }
    if (!_hasSupabase) return 'Сервис входа временно недоступен';

    _isSigningIn = true;
    _authError = null;
    notifyListeners();
    try {
      await _client.auth.signInWithOtp(
        phone: normalizedPhone,
        shouldCreateUser: true,
      );
      return null;
    } on AuthException catch (error) {
      final message = _phoneAuthErrorMessage(error.message);
      _authError = message;
      return message;
    } catch (_) {
      const message = 'Не удалось отправить код. Попробуйте ещё раз';
      _authError = message;
      return message;
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  Future<String?> verifyPhoneOtp(String phone, String code) async {
    final normalizedPhone = phone.replaceAll(RegExp(r'[^+\d]'), '');
    final normalizedCode = code.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^\+7\d{10}$').hasMatch(normalizedPhone)) {
      return 'Введите номер телефона полностью';
    }
    if (normalizedCode.length < 4) return 'Введите код из сообщения';
    if (!_hasSupabase) return 'Сервис входа временно недоступен';

    _isSigningIn = true;
    _authError = null;
    notifyListeners();
    try {
      final response = await _client.auth.verifyOTP(
        phone: normalizedPhone,
        token: normalizedCode,
        type: OtpType.sms,
      );
      final user = response.user;
      if (user == null) return 'Не удалось подтвердить номер';
      await _handleAuthState(user);
      return null;
    } on AuthException catch (error) {
      final message = _phoneAuthErrorMessage(error.message);
      _authError = message;
      return message;
    } catch (_) {
      const message = 'Не удалось подтвердить код. Попробуйте ещё раз';
      _authError = message;
      return message;
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  String _phoneAuthErrorMessage(String rawMessage) {
    final message = rawMessage.toLowerCase();
    if (message.contains('expired') || message.contains('invalid token')) {
      return 'Код неверный или уже истёк';
    }
    if (message.contains('rate') || message.contains('seconds')) {
      return 'Слишком много попыток. Подождите и попробуйте снова';
    }
    if (message.contains('phone') && message.contains('disabled')) {
      return 'Вход по телефону пока недоступен';
    }
    return 'Не удалось выполнить вход по номеру телефона';
  }

  Future<void> _signInWithSocialOAuth({
    required String authUrl,
    required String providerLabel,
  }) async {
    if (!_hasSupabase) {
      _authError = 'Supabase не настроен';
      notifyListeners();
      return;
    }

    _isSigningIn = true;
    _authError = null;
    notifyListeners();

    final redirectTo = kIsWeb
        ? Uri.base
        : Uri.parse(SupabaseConfig.oauthRedirectUri);
    final uri = Uri.parse(
      authUrl,
    ).replace(queryParameters: {'redirect_to': redirectTo.toString()});

    try {
      if (kIsWeb) {
        final didOpen = await launchUrl(
          uri,
          mode: LaunchMode.platformDefault,
          webOnlyWindowName: '_self',
        );
        if (!didOpen) {
          _authError = 'Не удалось открыть вход через $providerLabel';
        }
        return;
      }

      final callback = await FlutterWebAuth2.authenticate(
        url: uri.toString(),
        callbackUrlScheme: redirectTo.scheme,
      );
      final tokens = parseOAuthCallback(
        Uri.parse(callback),
        expectedRedirect: redirectTo,
      );
      await _client.auth.setSession(
        tokens.refreshToken,
        accessToken: tokens.accessToken,
      );
    } on OAuthCallbackException catch (e) {
      _authError = 'Не удалось войти через $providerLabel: ${e.message}';
    } on PlatformException catch (e) {
      if (e.code.toUpperCase() == 'CANCELED') {
        _authError = null;
      } else {
        _authError =
            'Не удалось начать вход через $providerLabel: ${e.message ?? e.code}';
      }
    } catch (e) {
      _authError = 'Не удалось войти через $providerLabel: $e';
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  Future<void> signInWithTelegram() async {
    if (!_hasSupabase) {
      _authError = 'Supabase не настроен';
      notifyListeners();
      return;
    }

    _isSigningIn = true;
    _authError = null;
    notifyListeners();

    final redirectTo = kIsWeb
        ? Uri.base.toString()
        : SupabaseConfig.authRedirectUri;
    final uri = Uri.parse(
      SupabaseConfig.telegramAuthUrl,
    ).replace(queryParameters: {'redirect_to': redirectTo});

    try {
      final didOpen = await launchUrl(
        uri,
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
        webOnlyWindowName: '_self',
      );
      if (!didOpen) {
        _authError = 'Не удалось открыть вход через Telegram';
      }
    } catch (e) {
      _authError = 'Не удалось начать вход через Telegram: $e';
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    if (!_hasSupabase) return;
    await _removeCurrentPushToken();
    await _client.auth.signOut(scope: SignOutScope.local);
    await _handleAuthState(null);
  }

  Future<String?> updateProfile({
    required String name,
    required String handle,
  }) async {
    final cleanName = name.trim().isEmpty ? 'Ваш профиль' : name.trim();
    final cleanHandle = _normalizeHandle(handle);
    if (!_isValidHandle(cleanHandle)) {
      return 'Username должен быть 3-24 символа: латиница, цифры и _';
    }
    if (_hasSupabase && currentUserId.isNotEmpty) {
      final isTaken = await _isHandleTaken(cleanHandle, currentUserId);
      if (isTaken) return 'Такой username уже занят';
    }

    _profile = _profile.copyWith(name: cleanName, handle: cleanHandle);
    await _prefs.setString(
      _scopedStorageKey(_profileKey),
      jsonEncode(_profile.toJson()),
    );
    notifyListeners();

    if (_hasSupabase && _client.auth.currentUser != null) {
      try {
        await _upsertProfile(
          userId: _client.auth.currentUser!.id,
          profile: _profile,
        );
        final response = await _client.auth.updateUser(
          UserAttributes(
            data: {
              ...?_client.auth.currentUser?.userMetadata,
              'full_name': cleanName,
              'username': cleanHandle.substring(1),
              'preferred_username': cleanHandle.substring(1),
            },
          ),
        );
        _currentUser = response.user ?? _client.auth.currentUser;
        await _syncOwnedProductSellerFields(
          userId: _client.auth.currentUser!.id,
          profile: _profile,
        );
      } catch (e) {
        debugPrint('Profile update error: $e');
        return 'Не удалось сохранить профиль';
      }
    }
    return null;
  }

  Future<String?> savePersonalProfile(
    AppProfile updatedProfile,
    XFile? avatarFile,
  ) async {
    var avatarUrl = updatedProfile.avatarUrl;
    if (avatarFile != null) {
      avatarUrl = _hasSupabase
          ? await uploadImage(avatarFile, folder: 'avatars/$currentUserId') ??
                ''
          : await _inlineImage(avatarFile) ?? '';
      if (avatarUrl.isEmpty) return 'Не удалось сохранить фото профиля';
    }

    _profile = updatedProfile.copyWith(avatarUrl: avatarUrl);
    await _prefs.setString(
      _scopedStorageKey(_profileKey),
      jsonEncode(_profile.toJson()),
    );
    notifyListeners();

    final user = _hasSupabase ? _client.auth.currentUser : null;
    if (user == null) return null;
    try {
      await _upsertProfile(userId: user.id, profile: _profile);
      await _savePrivateProfileDetails(user.id, _profile);
      final response = await _client.auth.updateUser(
        UserAttributes(
          data: {
            ...?user.userMetadata,
            'full_name': _profile.name,
            'avatar_url': _profile.avatarUrl,
          },
        ),
      );
      _currentUser = response.user ?? _client.auth.currentUser;
      await _syncOwnedProductSellerFields(userId: user.id, profile: _profile);
    } catch (e) {
      debugPrint('Personal profile update error: $e');
      return 'Данные сохранены на устройстве, но не синхронизированы';
    }
    return null;
  }

  Future<String?> requestEmailConfirmation(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)) {
      return 'Проверьте формат email';
    }
    if (!_hasSupabase || _client.auth.currentUser == null) {
      return 'Войдите в аккаунт, чтобы подтвердить email';
    }
    final user = _client.auth.currentUser!;
    try {
      if ((user.email ?? '').toLowerCase() == normalized) {
        if (user.emailConfirmedAt != null) return 'Email уже подтвержден';
        await _client.auth.resend(type: OtpType.signup, email: normalized);
      } else {
        await _client.auth.updateUser(UserAttributes(email: normalized));
      }
      _profile = _profile.copyWith(email: normalized);
      await _prefs.setString(
        _scopedStorageKey(_profileKey),
        jsonEncode(_profile.toJson()),
      );
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('Email confirmation error: $e');
      return 'Не удалось отправить письмо. Попробуйте позже';
    }
  }

  Future<String?> deleteAccount() async {
    if (!_hasSupabase || _client.auth.currentUser == null) {
      await _clearScopedUserStorage('');
      _loadLocalUserState();
      notifyListeners();
      return null;
    }

    try {
      final deletedUserId = currentUserId;
      final response = await _client.functions.invoke('delete-account');
      final data = response.data;
      final confirmed =
          response.status == 200 && data is Map && data['deleted'] == true;
      if (!confirmed) {
        throw StateError('Account deletion was not confirmed by the server');
      }

      // Never clear user data or the local session until the backend confirms
      // that Storage, owned UGC and the Auth user were deleted.
      await _clearScopedUserStorage(deletedUserId);
      try {
        await _client.auth.signOut(scope: SignOutScope.local);
      } catch (e) {
        // The server already deleted this Auth user. Do not turn a local
        // session cleanup problem into a false "deletion failed" result.
        debugPrint('Deleted account local sign-out error: $e');
      }
      _currentUser = null;
      _loadLocalUserState();
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('Account delete error: $e');
      return 'Не удалось удалить аккаунт. Попробуйте ещё раз';
    }
  }

  Future<String?> _inlineImage(XFile imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final mimeType = _mimeTypeForImage(imageFile.name, imageFile.path);
      return 'data:$mimeType;base64,${base64Encode(bytes)}';
    } catch (e) {
      debugPrint('Inline avatar error: $e');
      return null;
    }
  }

  Future<void> _savePrivateProfileDetails(
    String userId,
    AppProfile profile,
  ) async {
    try {
      await _client.from('profile_private_details').upsert({
        'user_id': userId,
        'first_name': profile.firstName,
        'last_name': profile.lastName,
        'middle_name': profile.middleName,
        'gender': profile.gender,
        'birth_date': profile.birthDate.isEmpty ? null : profile.birthDate,
        'phone': profile.phone,
        'email': profile.email,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST205') rethrow;
      debugPrint('Private profile table is not installed yet');
    }
  }

  Future<void> _loadPrivateProfileDetails(String userId) async {
    try {
      final response = await _client
          .from('profile_private_details')
          .select()
          .eq('user_id', userId)
          .limit(1);
      final rows = response as List<dynamic>;
      if (rows.isEmpty) return;
      final row = rows.first as Map<String, dynamic>;
      _profile = _profile.copyWith(
        firstName: row['first_name'] as String? ?? _profile.firstName,
        lastName: row['last_name'] as String? ?? _profile.lastName,
        middleName: row['middle_name'] as String? ?? _profile.middleName,
        gender: row['gender'] as String? ?? _profile.gender,
        birthDate: row['birth_date']?.toString() ?? _profile.birthDate,
        phone: row['phone'] as String? ?? _profile.phone,
        email: row['email'] as String? ?? _profile.email,
      );
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST205') rethrow;
    }
  }

  Future<void> _handleAuthState(User? user) async {
    final previousUserId = currentUserId;
    _currentUser = user;
    if (previousUserId != currentUserId) {
      _chatMediaUrlCache.clear();
      _knownRemoteThreadIds.clear();
      _latestMessageNotification = null;
      _activeThreadId = null;
      _hasCompletedThreadSync = false;
      _lastSeenByUserId.clear();
      _loadLocalUserState();
      _isThreadSyncPending = false;
      _threadSyncError = null;
    }
    _activateBlockedUserIdentity(user?.id ?? '');
    _authError = null;
    await _applyUserProfile(user, notify: false);
    if (user != null) {
      await _subscribeToMessages();
      unawaited(_registerPushToken(user.id));
      unawaited(_updatePresence());
      unawaited(_syncFromSupabase());
      unawaited(_syncAccessoriesFromSupabase());
      unawaited(_syncOutfitsFromSupabase());
      unawaited(_syncBlockedUsers());
      unawaited(_syncUserCollectionsFromSupabase());
      unawaited(_syncProfileFeaturesFromSupabase());
      unawaited(_chatThreadSync.runNow(_syncThreadsFromSupabase));
    } else {
      _chatThreadSync.cancelPending();
      _messageSubscriptionGeneration++;
      final messagesChannel = _messagesChannel;
      _messagesChannel = null;
      if (messagesChannel != null) {
        try {
          await messagesChannel.unsubscribe();
        } catch (e) {
          debugPrint('Message channel unsubscribe error: $e');
        }
      }
      await _pushTokenSubscription?.cancel();
      _pushTokenSubscription = null;
      _registeredPushToken = null;
      _lastSeenByUserId.clear();
      _hasCompletedThreadSync = false;
    }
    notifyListeners();
  }

  Future<void> _applyUserProfile(User? user, {bool notify = true}) async {
    if (user == null) {
      if (notify) notifyListeners();
      return;
    }

    try {
      final response = await _client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .limit(1);
      final rows = response as List<dynamic>;
      if (rows.isNotEmpty) {
        final row = rows.first as Map<String, dynamic>;
        _profile = _profile.copyWith(
          name: row['name'] as String? ?? _profile.name,
          handle: row['handle'] as String? ?? _profile.handle,
          city: row['city'] as String? ?? _profile.city,
          avatarUrl: row['avatar_url'] as String? ?? _profile.avatarUrl,
          rating: (row['rating'] as num?)?.toDouble() ?? _profile.rating,
          salesCount:
              (row['sales_count'] as num?)?.toInt() ?? _profile.salesCount,
          followersCount:
              (row['followers_count'] as num?)?.toInt() ??
              _profile.followersCount,
          email: _profile.email.isEmpty ? (user.email ?? '') : _profile.email,
        );
        await _loadPrivateProfileDetails(user.id);
        await _prefs.setString(
          _scopedStorageKey(_profileKey),
          jsonEncode(_profile.toJson()),
        );
        await _syncOwnedProductSellerFields(userId: user.id, profile: _profile);
        if (notify) notifyListeners();
        return;
      }
    } catch (e) {
      debugPrint('Profile fetch error: $e');
    }

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final rawName =
        metadata['full_name'] ??
        metadata['name'] ??
        metadata['display_name'] ??
        metadata['username'] ??
        metadata['login'] ??
        user.email;
    final name = rawName?.toString().trim();
    final handleSource =
        metadata['preferred_username'] ??
        metadata['username'] ??
        metadata['login'] ??
        user.email?.split('@').first ??
        user.id.substring(0, 8);
    final handle = await _uniqueHandle(
      _normalizeHandle(handleSource.toString()),
      user.id,
    );

    if (name != null && name.isNotEmpty) {
      _profile = _profile.copyWith(
        name: name,
        handle: handle,
        firstName: _profile.firstName.isEmpty ? name.split(' ').first : null,
        email: _profile.email.isEmpty ? (user.email ?? '') : _profile.email,
        avatarUrl: _profile.avatarUrl.isEmpty ? _currentAvatarUrl() : null,
      );
      await _prefs.setString(
        _scopedStorageKey(_profileKey),
        jsonEncode(_profile.toJson()),
      );
      await _upsertProfile(userId: user.id, profile: _profile);
      await _syncOwnedProductSellerFields(userId: user.id, profile: _profile);
    }

    if (notify) notifyListeners();
  }

  String _normalizeHandle(String value) {
    final raw = value
        .trim()
        .replaceAll('@', '')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '')
        .toLowerCase();
    if (raw.isEmpty) return '@user';
    return '@$raw';
  }

  bool _isValidHandle(String value) {
    return RegExp(r'^@[a-z0-9_]{3,24}$').hasMatch(value);
  }

  Future<bool> _isHandleTaken(String handle, String currentUserId) async {
    if (!_hasSupabase) return false;
    try {
      final response = await _client
          .from('profiles')
          .select('id')
          .eq('handle', handle)
          .limit(1);
      final rows = response as List<dynamic>;
      if (rows.isEmpty) return false;
      return (rows.first as Map<String, dynamic>)['id'] != currentUserId;
    } catch (e) {
      debugPrint('Handle check error: $e');
      return false;
    }
  }

  Future<String> _uniqueHandle(String baseHandle, String userId) async {
    var candidate = _isValidHandle(baseHandle) ? baseHandle : '@user';
    if (!await _isHandleTaken(candidate, userId)) return candidate;

    final raw = candidate.substring(1);
    for (var i = 2; i < 100; i++) {
      final suffix = '_$i';
      final maxBaseLength = 24 - suffix.length;
      final base = raw.substring(0, raw.length.clamp(0, maxBaseLength));
      candidate = '@$base$suffix';
      if (!await _isHandleTaken(candidate, userId)) return candidate;
    }
    return '@${userId.replaceAll('-', '').substring(0, 12)}';
  }

  Future<void> _upsertProfile({
    required String userId,
    required AppProfile profile,
  }) async {
    if (!_hasSupabase) return;
    await _client.from('profiles').upsert({
      'id': userId,
      'name': profile.name,
      'handle': profile.handle,
      'avatar_url': _currentAvatarUrl(),
      'city': profile.city,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  Future<void> _registerPushToken(String userId) async {
    if (!_notificationPreferences.pushEnabled ||
        !_hasSupabase ||
        userId.isEmpty ||
        !PushNotificationService.isEnabled) {
      return;
    }

    var permission = await PushNotificationService.getPermissionStatus();
    if (permission == PushPermissionStatus.notDetermined) {
      permission = await PushNotificationService.requestPermission();
    }
    if (permission == PushPermissionStatus.denied) {
      _notificationPreferences = _notificationPreferences.copyWith(
        pushEnabled: false,
      );
      await _saveNotificationPreferencesLocal();
      notifyListeners();
      return;
    }
    if (permission == PushPermissionStatus.unsupported) return;

    final token = await PushNotificationService.currentToken();
    if (token != null && token.isNotEmpty) {
      await _upsertPushToken(userId: userId, token: token);
    }

    await _pushTokenSubscription?.cancel();
    _pushTokenSubscription = PushNotificationService.onTokenRefresh.listen((
      token,
    ) {
      unawaited(_upsertPushToken(userId: userId, token: token));
    });
  }

  Future<void> _upsertPushToken({
    required String userId,
    required String token,
  }) async {
    if (!_hasSupabase || userId.isEmpty || token.isEmpty) return;
    try {
      _registeredPushToken = token;
      await _client.from('device_push_tokens').upsert({
        'user_id': userId,
        'token': token,
        'platform': PushNotificationService.platform,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
    } catch (e) {
      debugPrint('Push token upsert error: $e');
    }
  }

  Future<void> _removeCurrentPushToken() async {
    await _pushTokenSubscription?.cancel();
    _pushTokenSubscription = null;

    if (_hasSupabase) {
      try {
        final token =
            _registeredPushToken ??
            await PushNotificationService.currentToken();
        if (token != null && token.isNotEmpty) {
          await _client.from('device_push_tokens').delete().eq('token', token);
        }
      } catch (e) {
        debugPrint('Push token remove error: $e');
      }
    }

    _registeredPushToken = null;
    try {
      await PushNotificationService.deleteToken();
    } catch (error) {
      // Push cleanup must never trap the user in an authenticated account.
      debugPrint('Local push token delete error: $error');
    }
  }

  Future<void> _updatePresence() async {
    if (!_hasSupabase || currentUserId.isEmpty) return;
    final now = DateTime.now().toUtc();
    _lastSeenByUserId[currentUserId] = now;
    try {
      await _client
          .from('profiles')
          .update({
            'last_seen_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          })
          .eq('id', currentUserId);
    } catch (e) {
      debugPrint('Presence update error: $e');
    }
  }

  Future<void> _syncThreadPresence(List<MessageThread> threads) async {
    if (!_hasSupabase || currentUserId.isEmpty || threads.isEmpty) return;

    final userIds = threads
        .expand((thread) => thread.memberIds)
        .where((id) => id != currentUserId)
        .where((id) => id.isNotEmpty)
        .toSet();
    if (userIds.isEmpty) return;

    try {
      final response = await _client
          .from('profiles')
          .select('id,last_seen_at')
          .inFilter('id', userIds.toList());
      for (final item in response as List<dynamic>) {
        final row = item as Map<String, dynamic>;
        final id = row['id'] as String? ?? '';
        final value = row['last_seen_at'] as String?;
        final parsed = value == null ? null : DateTime.tryParse(value);
        if (id.isNotEmpty && parsed != null) {
          _lastSeenByUserId[id] = parsed.toLocal();
        }
      }
    } catch (e) {
      debugPrint('Presence sync error: $e');
    }
  }

  Future<void> _syncOwnedProductSellerFields({
    required String userId,
    required AppProfile profile,
  }) async {
    if (userId.isEmpty) return;

    if (_hasSupabase) {
      try {
        await _client
            .from('products')
            .update({
              'seller_name': profile.name,
              'seller_handle': profile.handle,
            })
            .eq('seller_id', userId);
        await _client
            .from('outfits')
            .update({
              'author_name': profile.name,
              'author_handle': profile.handle,
              'author_avatar_url': profile.avatarUrl,
            })
            .eq('owner_id', userId);
      } catch (e) {
        debugPrint('Seller product sync error: $e');
      }
    }

    var changed = false;
    _products = _products.map((product) {
      if (product.ownerId != userId) return product;
      if (product.sellerName == profile.name &&
          product.sellerHandle == profile.handle) {
        return product;
      }
      changed = true;
      return product.copyWith(
        sellerName: profile.name,
        sellerHandle: profile.handle,
      );
    }).toList();
    if (changed) await _saveProducts();

    var outfitsChanged = false;
    _outfits = _outfits.map((outfit) {
      if (outfit.ownerId != userId) return outfit;
      if (outfit.authorName == profile.name &&
          outfit.authorHandle == profile.handle &&
          outfit.authorAvatarUrl == profile.avatarUrl) {
        return outfit;
      }
      outfitsChanged = true;
      return outfit.copyWith(
        authorName: profile.name,
        authorHandle: profile.handle,
        authorAvatarUrl: profile.avatarUrl,
      );
    }).toList();
    if (outfitsChanged) {
      await _writeList(_outfitsKey, _outfits.map((item) => item.toJson()));
    }
  }

  Future<void> _syncFromSupabase() async {
    if (!_hasSupabase) return;
    try {
      final response = await _client
          .from('products')
          .select()
          .eq('status', 'published')
          .eq('is_hidden', false)
          .order('created_at', ascending: false);
      final fetched = (response as List<dynamic>)
          .whereType<Map>()
          .map((row) => Product.fromSupabase(Map<String, dynamic>.from(row)))
          .toList();

      _products = fetched;
      _applyProductFavoriteState();
      await _saveProducts();
      notifyListeners();
    } catch (e) {
      debugPrint('Supabase sync error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _attachPublicAttributes(
    List<Map<dynamic, dynamic>> rows,
  ) async {
    final result = <Map<String, dynamic>>[];
    for (var start = 0; start < rows.length; start += 8) {
      final end = (start + 8).clamp(0, rows.length).toInt();
      final batch = rows.sublist(start, end);
      result.addAll(
        await Future.wait(
          batch.map((row) async {
            final product = Map<String, dynamic>.from(row);
            final productId = product['id'] as String? ?? '';
            if (productId.isEmpty) return product;
            try {
              final attributes = await _client.rpc(
                'get_product_public_attributes',
                params: {'p_product_id': productId},
              );
              if (attributes is List) {
                product['product_attributes'] = attributes;
              }
            } catch (_) {
              // Additive rollout: legacy scalar fields remain readable before
              // the public-attributes RPC is available.
            }
            return product;
          }),
        ),
      );
    }
    return result;
  }

  Future<void> _subscribeToMessages() async {
    if (!_hasSupabase || currentUserId.isEmpty) return;
    final subscriberId = currentUserId;
    final generation = ++_messageSubscriptionGeneration;
    final channelName = 'messages:$subscriberId';
    final previousChannel = _messagesChannel;
    _messagesChannel = null;
    if (previousChannel != null) {
      try {
        await previousChannel.unsubscribe();
      } catch (e) {
        debugPrint('Previous message channel unsubscribe error: $e');
      }
    }
    if (generation != _messageSubscriptionGeneration ||
        currentUserId != subscriberId) {
      return;
    }
    _messagesChannel = _client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_messages',
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.insert ||
                payload.eventType == PostgresChangeEvent.update) {
              unawaited(_applyRealtimeChatMessage(payload.newRecord));
            } else {
              _chatThreadSync.schedule(_syncThreadsFromSupabase);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_threads',
          callback: (_) => _chatThreadSync.schedule(_syncThreadsFromSupabase),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_thread_member_state',
          callback: (_) => _chatThreadSync.schedule(_syncThreadsFromSupabase),
        )
        .subscribe((status, error) {
          if (generation != _messageSubscriptionGeneration ||
              currentUserId != subscriberId) {
            return;
          }
          if (status == RealtimeSubscribeStatus.subscribed) {
            _chatThreadSync.schedule(_syncThreadsFromSupabase);
            return;
          }
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            debugPrint(
              'Message realtime subscription error '
              '(user=$subscriberId, status=$status): $error',
            );
          }
        });
  }

  Future<void> _applyRealtimeChatMessage(Map<String, dynamic> row) async {
    final syncUserId = currentUserId;
    if (syncUserId.isEmpty) return;
    final threadId = row['thread_id'] as String? ?? '';
    if (threadId.isEmpty) return;
    final threadIndex = _threads.indexWhere((thread) => thread.id == threadId);
    if (threadIndex == -1) {
      _chatThreadSync.schedule(_syncThreadsFromSupabase);
      return;
    }

    final currentThread = _threads[threadIndex];
    if (!currentThread.containsUser(syncUserId) ||
        _isBlockedThread(currentThread)) {
      return;
    }
    var message = ChatMessage.fromJson(row, currentUserId: syncUserId);
    message = await _resolveChatMessageMedia(message);
    if (currentUserId != syncUserId) return;

    final messages = List<ChatMessage>.from(currentThread.messages);
    final existingIndex = messages.indexWhere((item) => item.id == message.id);
    final isNew = existingIndex == -1;
    if (isNew) {
      messages.add(message);
    } else {
      messages[existingIndex] = message;
    }
    messages.sort((left, right) {
      final byTime = left.createdAt.compareTo(right.createdAt);
      return byTime != 0 ? byTime : left.id.compareTo(right.id);
    });

    final isIncoming = !message.isMine && !message.isDeleted;
    final isVisible = _activeThreadId == threadId;
    final alreadyRead =
        message.readBy.contains(syncUserId) ||
        (currentThread.lastReadAt?.isAfter(message.createdAt) ?? false);
    final updated = currentThread.copyWith(
      messages: messages,
      lastMessage: messages.isEmpty
          ? currentThread.lastMessage
          : messages.last.previewText,
      updatedAt: message.createdAt.isAfter(currentThread.updatedAt)
          ? message.createdAt
          : currentThread.updatedAt,
      unreadCount: isVisible
          ? 0
          : isNew && isIncoming && !alreadyRead
          ? currentThread.unreadCount + 1
          : currentThread.unreadCount,
    );
    _upsertLocalThread(updated);
    if (isNew && isIncoming && !isVisible && !currentThread.isMuted) {
      final senderName = message.senderName.trim().isNotEmpty
          ? message.senderName.trim()
          : currentThread.otherPartyName(syncUserId);
      _latestMessageNotification = MessageNotification(
        id: '$threadId:${message.id}',
        threadId: threadId,
        senderName: senderName,
        text: message.previewText,
      );
    }
    notifyListeners();
    if (isNew && isIncoming && isVisible) {
      unawaited(markThreadRead(threadId));
    }
    unawaited(
      _saveThreadsLocal().catchError((Object error) {
        debugPrint('Realtime chat cache write error: $error');
      }),
    );
  }

  Future<List<MessageThread>> _hydrateThreadMemberState(
    List<MessageThread> threads,
  ) async {
    if (threads.isEmpty || currentUserId.isEmpty) return threads;
    try {
      final stateByThread = <String, Map<String, dynamic>>{};
      final threadIds = threads.map((thread) => thread.id).toList();
      for (
        var start = 0;
        start < threadIds.length;
        start += _chatHydrationBatchSize
      ) {
        final end = (start + _chatHydrationBatchSize)
            .clamp(0, threadIds.length)
            .toInt();
        final response = await _client
            .from('chat_thread_member_state')
            .select(
              'thread_id,is_pinned,is_muted,is_archived,draft,last_read_at',
            )
            .eq('user_id', currentUserId)
            .inFilter('thread_id', threadIds.sublist(start, end));
        for (final item in response as List<dynamic>) {
          final row = item as Map<String, dynamic>;
          final threadId = row['thread_id'] as String? ?? '';
          if (threadId.isNotEmpty) stateByThread[threadId] = row;
        }
      }

      return threads
          .map((thread) {
            final state = stateByThread[thread.id];
            final rawLastReadAt = state?['last_read_at'] as String?;
            return thread.copyWith(
              isPinned: state?['is_pinned'] as bool? ?? false,
              isMuted: state?['is_muted'] as bool? ?? false,
              isArchived: state?['is_archived'] as bool? ?? false,
              draft: state?['draft'] as String? ?? '',
              lastReadAt: rawLastReadAt == null
                  ? null
                  : DateTime.tryParse(rawLastReadAt),
            );
          })
          .toList(growable: false);
    } catch (e) {
      debugPrint('Chat member state hydration error: $e');
      // Additive rollout fallback for a backend that has not run the member
      // state migration yet.
      return threads;
    }
  }

  Future<List<MessageThread>> _hydrateThreadMessages(
    List<MessageThread> threads,
  ) async {
    if (threads.isEmpty) return threads;
    try {
      final byThread = <String, List<ChatMessage>>{};
      final threadIds = threads.map((thread) => thread.id).toList();
      for (
        var start = 0;
        start < threadIds.length;
        start += _chatHydrationBatchSize
      ) {
        final end = (start + _chatHydrationBatchSize)
            .clamp(0, threadIds.length)
            .toInt();
        var offset = 0;
        while (true) {
          final response = await _client
              .from('chat_messages')
              .select()
              .inFilter('thread_id', threadIds.sublist(start, end))
              .order('created_at', ascending: true)
              .order('id', ascending: true)
              .range(offset, offset + _chatHydrationPageSize - 1);
          final rows = response as List<dynamic>;
          for (final item in rows) {
            final row = item as Map<String, dynamic>;
            final threadId = row['thread_id'] as String? ?? '';
            if (threadId.isEmpty) continue;
            final parsed = ChatMessage.fromJson(
              row,
              currentUserId: currentUserId,
            );
            final message = await _resolveChatMessageMedia(parsed);
            byThread.putIfAbsent(threadId, () => []).add(message);
          }
          if (rows.length < _chatHydrationPageSize) break;
          offset += rows.length;
        }
      }
      return threads
          .map((thread) {
            final messages = byThread[thread.id] ?? const <ChatMessage>[];
            final unreadCount = messages.where((message) {
              if (message.senderId == currentUserId || message.isDeleted) {
                return false;
              }
              if (message.readBy.contains(currentUserId)) return false;
              final lastReadAt = thread.lastReadAt;
              return lastReadAt == null ||
                  message.createdAt.isAfter(lastReadAt);
            }).length;
            return thread.copyWith(
              messages: messages,
              unreadCount: unreadCount,
            );
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      debugPrint('Chat messages sync error: $error');
      debugPrintStack(stackTrace: stackTrace);
      // Messages are core conversation data. Treating a failed hydration as
      // a successful empty response makes RLS/network failures indistinguish-
      // able from a genuinely empty chat, so let the outer sync expose retry.
      rethrow;
    }
  }

  Future<List<MessageThread>> _hydrateThreadProfiles(
    List<MessageThread> threads,
  ) async {
    final memberIds = threads
        .expand((thread) => thread.memberIds)
        .where((id) => id.isNotEmpty)
        .toSet();
    if (memberIds.isEmpty) return threads;
    try {
      final profiles = <String, AppUserProfile>{};
      final ids = memberIds.toList();
      for (
        var start = 0;
        start < ids.length;
        start += _chatHydrationBatchSize
      ) {
        final end = (start + _chatHydrationBatchSize)
            .clamp(0, ids.length)
            .toInt();
        final response = await _client
            .from('profiles')
            .select('id,name,handle,avatar_url')
            .inFilter('id', ids.sublist(start, end));
        for (final item in response as List<dynamic>) {
          final profile = AppUserProfile.fromSupabase(
            item as Map<String, dynamic>,
          );
          if (profile.id.isNotEmpty) profiles[profile.id] = profile;
        }
      }
      return threads
          .map((thread) {
            final buyer = profiles[thread.buyerId];
            final seller = profiles[thread.sellerId];
            final existingMembers = {
              for (final member in thread.members) member.id: member,
            };
            final hydratedMembers = thread.memberIds
                .map((id) {
                  final profile = profiles[id];
                  final existing = existingMembers[id];
                  return ConversationMember(
                    id: id,
                    name: profile?.name ?? existing?.name ?? '',
                    handle: profile?.handle ?? existing?.handle ?? '',
                    avatarUrl: profile?.avatarUrl ?? existing?.avatarUrl ?? '',
                  );
                })
                .toList(growable: false);
            return thread.copyWith(
              buyerName: buyer?.name,
              buyerHandle: buyer?.handle,
              buyerAvatar: buyer?.avatarUrl,
              sellerName: seller?.name,
              sellerHandle: seller?.handle,
              sellerAvatar: seller?.avatarUrl,
              members: hydratedMembers,
            );
          })
          .toList(growable: false);
    } catch (e) {
      debugPrint('Chat profile hydration error: $e');
      return threads;
    }
  }

  Future<ChatMessage> _resolveChatMessageMedia(ChatMessage message) async {
    final attachment = message.attachment;
    if (attachment == null || !attachment.hasRemoteObject) return message;
    try {
      final signedUrl = await _chatMediaUrlCache.resolve(
        key: _chatMediaCacheKey(attachment.bucket, attachment.storagePath),
        load: () => _client.storage
            .from(attachment.bucket)
            .createSignedUrl(
              attachment.storagePath,
              _chatMediaSignedUrlSeconds,
            ),
      );
      if (signedUrl == null || signedUrl.isEmpty) return message;
      return message.copyWith(attachment: attachment.copyWith(url: signedUrl));
    } catch (e) {
      debugPrint('Chat media URL refresh error: $e');
      return message;
    }
  }

  String _chatMediaCacheKey(String bucket, String storagePath) {
    return '$bucket/$storagePath';
  }

  Future<void> _syncThreadsFromSupabase() async {
    if (!_hasSupabase || currentUserId.isEmpty) return;
    final syncUserId = currentUserId;
    final shouldExposeProgress = _threads.isEmpty || _threadSyncError != null;
    if (shouldExposeProgress) {
      _isThreadSyncPending = true;
      _threadSyncError = null;
      notifyListeners();
    }

    try {
      final previousById = {for (final thread in _threads) thread.id: thread};
      final response = await _client
          .from('message_threads')
          .select()
          .or(
            'buyer_id.eq.$syncUserId,seller_id.eq.$syncUserId,'
            'member_ids.cs.{$syncUserId}',
          )
          .order('updated_at', ascending: false);

      var fetched = (response as List<dynamic>)
          .map(
            (item) => MessageThread.fromSupabase(
              item as Map<String, dynamic>,
              currentUserId: syncUserId,
            ),
          )
          .toList();
      if (currentUserId != syncUserId) return;
      _knownRemoteThreadIds.addAll(fetched.map((thread) => thread.id));
      fetched = await _hydrateThreadProfiles(fetched);
      fetched = await _hydrateThreadMemberState(fetched);
      fetched = await _hydrateThreadMessages(fetched);
      if (currentUserId != syncUserId) return;

      if (_hasCompletedThreadSync) {
        final notification = _incomingNotification(fetched, previousById);
        if (notification != null) {
          _latestMessageNotification = notification;
        }
      }
      if (currentUserId != syncUserId) return;
      _hasCompletedThreadSync = true;

      // A send can complete while the multi-request hydration and presence
      // refresh are in flight. Merge only at commit time against the live
      // local state; the older response must never erase that message.
      final latestLocalById = {
        for (final thread in _threads) thread.id: thread,
      };
      fetched = mergeChatOutgoingState(fetched, latestLocalById);
      fetched.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      if (currentUserId != syncUserId) return;
      _threads = fetched;
      _isThreadSyncPending = false;
      _threadSyncError = null;
      notifyListeners();
      // Presence and disk cache are recovery aids. Keep them off the critical
      // path so incoming messages and their unread badge appear immediately.
      unawaited(_syncThreadPresence(fetched));
      unawaited(
        _writeList(
          _scopedStorageKey(_threadsKey, syncUserId),
          fetched.map((item) => item.toJson()),
        ).catchError((Object error) {
          debugPrint('Chat cache write error: $error');
        }),
      );
    } catch (error, stackTrace) {
      if (currentUserId == syncUserId) {
        _isThreadSyncPending = false;
        _threadSyncError = 'Проверьте подключение и повторите попытку.';
        notifyListeners();
      }
      debugPrint('Threads sync error: $error');
      debugPrintStack(stackTrace: stackTrace);
      // Optional table. Local chats remain fully usable without it.
    }
  }

  Future<void> retryThreadSync() {
    if (!_hasSupabase || currentUserId.isEmpty) return Future<void>.value();
    return _chatThreadSync.runNow(_syncThreadsFromSupabase);
  }

  @visibleForTesting
  static List<MessageThread> mergeChatOutgoingState(
    List<MessageThread> remoteThreads,
    Map<String, MessageThread> previousById,
  ) {
    final merged = remoteThreads
        .map((remoteThread) {
          final localThread = previousById[remoteThread.id];
          if (localThread == null) return remoteThread;
          final localById = {
            for (final message in localThread.messages) message.id: message,
          };
          var reconciledLocalState = false;
          final reconciledRemoteMessages = remoteThread.messages
              .map((message) {
                // A server-hydrated message is never pending/failed. These
                // flags therefore identify a local-only row carried by an
                // earlier merge while another local state change completed.
                if (!message.isPending && !message.hasError) return message;
                final localMessage = localById[message.id];
                if (localMessage == null) return message;
                reconciledLocalState = true;
                return localMessage;
              })
              .toList(growable: false);
          final remoteIds = reconciledRemoteMessages
              .map((message) => message.id)
              .toSet();
          final localOnly = localThread.messages.where(
            (message) => message.isMine && !remoteIds.contains(message.id),
          );
          if (localOnly.isEmpty && !reconciledLocalState) return remoteThread;

          final messages = [...reconciledRemoteMessages, ...localOnly]
            ..sort((left, right) {
              final byTime = left.createdAt.compareTo(right.createdAt);
              return byTime != 0 ? byTime : left.id.compareTo(right.id);
            });
          final latest = messages.last;
          return remoteThread.copyWith(
            messages: messages,
            lastMessage: latest.previewText,
            updatedAt: latest.createdAt.isAfter(remoteThread.updatedAt)
                ? latest.createdAt
                : remoteThread.updatedAt,
          );
        })
        .toList(growable: false);
    final remoteThreadIds = remoteThreads.map((thread) => thread.id).toSet();
    final missingWithUnsentMessages = previousById.values.where(
      (thread) =>
          !remoteThreadIds.contains(thread.id) &&
          thread.messages.any(
            (message) =>
                message.isMine && (message.isPending || message.hasError),
          ),
    );
    return [...merged, ...missingWithUnsentMessages]
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  }

  MessageNotification? _incomingNotification(
    List<MessageThread> fetched,
    Map<String, MessageThread> previousById,
  ) {
    ChatMessage? newestMessage;
    MessageThread? newestThread;

    for (final thread in fetched) {
      if (_activeThreadId == thread.id || _isBlockedThread(thread)) continue;
      final previous = previousById[thread.id];
      final previousMessageIds = previous == null
          ? const <String>{}
          : previous.messages.map((message) => message.id).toSet();

      for (final message in thread.messages) {
        if (message.isMine || previousMessageIds.contains(message.id)) {
          continue;
        }
        if (newestMessage == null ||
            message.createdAt.isAfter(newestMessage.createdAt)) {
          newestMessage = message;
          newestThread = thread;
        }
      }
    }

    if (newestMessage == null || newestThread == null) return null;
    final senderName = newestMessage.senderName.trim().isNotEmpty
        ? newestMessage.senderName.trim()
        : newestThread.otherPartyName(currentUserId);
    return MessageNotification(
      id: '${newestThread.id}:${newestMessage.id}',
      threadId: newestThread.id,
      senderName: senderName,
      text: newestMessage.previewText,
    );
  }

  Future<void> _syncProfileFeaturesFromSupabase() async {
    if (!_hasSupabase || currentUserId.isEmpty) return;

    try {
      final settings = await _client
          .from('notification_settings')
          .select()
          .eq('user_id', currentUserId)
          .limit(1);
      final rows = settings as List<dynamic>;
      if (rows.isNotEmpty) {
        _notificationPreferences = NotificationPreferences.fromJson(
          rows.first as Map<String, dynamic>,
        );
        await _saveNotificationPreferencesLocal();
      }
    } catch (e) {
      debugPrint('Notification settings sync error: $e');
    }

    try {
      final deliveryProfiles = await _client
          .from('delivery_profiles')
          .select()
          .eq('user_id', currentUserId)
          .limit(1);
      final rows = deliveryProfiles as List<dynamic>;
      if (rows.isNotEmpty) {
        _deliveryProfile = DeliveryProfile.fromJson(
          rows.first as Map<String, dynamic>,
        );
        await _saveDeliveryProfileLocal();
      }
    } catch (e) {
      debugPrint('Delivery profile sync error: $e');
    }

    try {
      final notifications = await _client
          .from('notifications')
          .select()
          .eq('user_id', currentUserId)
          .neq('kind', 'message')
          .order('created_at', ascending: false)
          .limit(80);
      _notifications = (notifications as List<dynamic>)
          .map(
            (item) =>
                ProfileNotification.fromJson(item as Map<String, dynamic>),
          )
          .toList();
      await _saveNotificationsLocal();
    } catch (e) {
      debugPrint('Notifications sync error: $e');
    }

    final ordersUserId = currentUserId;
    try {
      final orders = await _client
          .from('orders')
          .select()
          .or('buyer_id.eq.$ordersUserId,seller_id.eq.$ordersUserId')
          .order('updated_at', ascending: false);
      final remoteOrders = (orders as List<dynamic>)
          .map((item) => AppOrder.fromJson(item as Map<String, dynamic>))
          .toList();
      if (ordersUserId.isNotEmpty && currentUserId == ordersUserId) {
        _orders = mergeOrdersForParticipant(
          localOrders: _orders,
          remoteOrders: remoteOrders,
          participantId: ordersUserId,
        );
        await _saveOrdersLocal();
      }
    } catch (e) {
      debugPrint('Orders sync error: $e');
    }

    notifyListeners();
  }

  Future<void> updateNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    final previous = _notificationPreferences;
    _notificationPreferences = preferences;
    await _saveNotificationPreferencesLocal();
    notifyListeners();

    if (previous.pushEnabled && !preferences.pushEnabled) {
      await _removeCurrentPushToken();
    } else if (!previous.pushEnabled && preferences.pushEnabled) {
      await _registerPushToken(currentUserId);
    }

    if (!_hasSupabase || currentUserId.isEmpty) return;
    try {
      await _client
          .from('notification_settings')
          .upsert(
            _notificationPreferences.toSupabaseJson(currentUserId),
            onConflict: 'user_id',
          );
    } catch (e) {
      debugPrint('Notification settings save error: $e');
    }
  }

  Future<void> updateDeliveryProfile(DeliveryProfile profile) async {
    _deliveryProfile = profile;
    await _saveDeliveryProfileLocal();
    notifyListeners();

    if (!_hasSupabase || currentUserId.isEmpty) return;
    try {
      await _client
          .from('delivery_profiles')
          .upsert(profile.toSupabaseJson(currentUserId), onConflict: 'user_id');
    } catch (e) {
      debugPrint('Delivery profile save error: $e');
    }
  }

  Future<AppOrder?> createDeliveryOrder(
    Product product, {
    String deliveryService = 'address:unassigned',
    int deliveryPrice = 0,
  }) async {
    final user = _hasSupabase
        ? await _ensureAuthSession(message: 'Войдите в профиль, чтобы купить')
        : null;
    if (_hasSupabase && user == null) {
      throw const CheckoutException(
        code: 'authentication_required',
        message: 'Войдите в профиль, чтобы оформить заказ',
      );
    }

    final buyerId = user?.id ?? currentUserId;
    if (buyerId.isEmpty) {
      _authError = 'Войдите в профиль, чтобы купить';
      notifyListeners();
      throw const CheckoutException(
        code: 'authentication_required',
        message: 'Войдите в профиль, чтобы оформить заказ',
      );
    }
    if (product.ownerId.isNotEmpty && product.ownerId == buyerId) {
      _authError = 'Это ваше объявление';
      notifyListeners();
      throw const CheckoutException(
        code: 'cannot_buy_own_listing',
        message: 'Нельзя купить собственное объявление',
      );
    }

    final delivery = _normalizeCheckoutDelivery(deliveryService);
    final deliveryType = delivery.$1;
    final deliveryProvider = delivery.$2;
    final isPickup = deliveryType == 'pickup_point';
    final destination = isPickup
        ? deliveryProfile.pickupPointAddress.trim()
        : [
            deliveryProfile.city.trim(),
            deliveryProfile.address.trim(),
          ].where((part) => part.isNotEmpty).join(', ');
    if (deliveryProfile.fullName.trim().isEmpty) {
      throw const CheckoutException(
        code: 'recipient_name_required',
        message: 'Укажите имя получателя',
      );
    }
    if (deliveryProfile.phone.trim().isEmpty) {
      throw const CheckoutException(
        code: 'recipient_phone_required',
        message: 'Укажите телефон получателя',
      );
    }
    if (destination.isEmpty ||
        (isPickup && deliveryProfile.pickupPointId.trim().isEmpty)) {
      throw CheckoutException(
        code: isPickup
            ? 'pickup_point_required'
            : 'delivery_destination_required',
        message: isPickup ? 'Выберите пункт выдачи' : 'Укажите адрес доставки',
      );
    }

    final displayDeliveryService = _deliveryServiceLabel(
      deliveryType,
      deliveryProvider,
    );
    final orderProfile = deliveryProfile.copyWith(address: destination);
    final pendingOrder = AppOrder.fromProduct(
      product: product,
      buyerId: buyerId,
      status: AppOrderStatus.pendingConfirmation,
      deliveryProfile: orderProfile,
      deliveryService: displayDeliveryService,
      deliveryPrice: deliveryPrice,
    );
    // Persist the active attempt before calling the server. If the app loses
    // the response or restarts, a retry receives the same authoritative order
    // instead of creating a duplicate. The key is rotated only after success.
    final attemptStorageKey = _scopedStorageKey(
      '$_checkoutAttemptKeyPrefix:${product.id}',
      buyerId,
    );
    late String idempotencyKey;
    try {
      idempotencyKey = _prefs.getString(attemptStorageKey)?.trim() ?? '';
      if (idempotencyKey.isEmpty) {
        idempotencyKey = _uuid.v4();
        final persisted = await _prefs.setString(
          attemptStorageKey,
          idempotencyKey,
        );
        if (!persisted) {
          throw const CheckoutException(
            code: 'checkout_attempt_save_failed',
            message: 'Не удалось начать оформление. Попробуйте ещё раз.',
            isRetryable: true,
          );
        }
      }
    } on CheckoutException {
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('Checkout attempt save error: $error\n$stackTrace');
      throw const CheckoutException(
        code: 'checkout_attempt_save_failed',
        message: 'Не удалось начать оформление. Попробуйте ещё раз.',
        isRetryable: true,
      );
    }

    var committedOrder = pendingOrder;
    if (_hasSupabase) {
      try {
        final response = await _client.rpc(
          'create_order',
          params: {
            'p_checkout': {
              'product_id': product.id,
              'idempotency_key': idempotencyKey,
              'delivery': {
                'type': deliveryType,
                'provider': deliveryProvider,
                'address': {
                  'city': deliveryProfile.city.trim(),
                  'line1': isPickup ? '' : deliveryProfile.address.trim(),
                },
                'pickup_point': isPickup
                    ? {
                        'id': deliveryProfile.pickupPointId.trim(),
                        'name': deliveryProfile.pickupPointName.trim(),
                        'address': deliveryProfile.pickupPointAddress.trim(),
                      }
                    : null,
              },
              'recipient': {
                'name': orderProfile.fullName.trim(),
                'phone': orderProfile.phone.trim(),
                'email': orderProfile.email.trim(),
              },
            },
          },
        );
        Object? row = response;
        if (row is List && row.isNotEmpty) row = row.first;
        if (row is! Map) {
          throw const FormatException('Invalid checkout response');
        }
        committedOrder = AppOrder.fromJson(Map<String, dynamic>.from(row));
      } on PostgrestException catch (e, stackTrace) {
        debugPrint('Order create error: $e\n$stackTrace');
        final failure = _checkoutFailure(e.message, code: e.code);
        _authError = failure.message;
        notifyListeners();
        throw failure;
      } on CheckoutException {
        rethrow;
      } catch (e, stackTrace) {
        debugPrint('Order create error: $e\n$stackTrace');
        _authError =
            'Не удалось создать заказ. Проверьте подключение и попробуйте ещё раз.';
        notifyListeners();
        throw const CheckoutException(
          code: 'checkout_unavailable',
          message:
              'Не удалось оформить заказ. Проверьте подключение и попробуйте ещё раз.',
          isRetryable: true,
        );
      }
    }

    _orders = mergeOrdersForParticipant(
      localOrders: _orders,
      remoteOrders: <AppOrder>[committedOrder],
      participantId: buyerId,
    );
    try {
      await _saveOrdersLocal();
    } catch (e, stackTrace) {
      debugPrint('Order local save error: $e\n$stackTrace');
      if (!_hasSupabase) {
        _orders.removeWhere((item) => item.id == committedOrder.id);
        _authError = 'Не удалось сохранить заказ. Попробуйте ещё раз.';
        notifyListeners();
        throw const CheckoutException(
          code: 'order_local_save_failed',
          message: 'Не удалось сохранить заказ. Попробуйте ещё раз.',
          isRetryable: true,
        );
      }
    }
    _authError = null;
    try {
      await _prefs.remove(attemptStorageKey);
    } catch (error, stackTrace) {
      // The server order is already committed. Keep the success path intact;
      // a retained key is safer than telling the buyer that checkout failed.
      debugPrint('Checkout attempt cleanup error: $error\n$stackTrace');
    }
    notifyListeners();
    unawaited(_addOrderCreatedNotification(committedOrder));
    return committedOrder;
  }

  Future<void> _addOrderCreatedNotification(AppOrder order) async {
    try {
      await _addProfileNotification(
        title: 'Заказ создан',
        body: order.productTitle,
        kind: 'order',
        targetId: order.id,
      );
    } catch (e, stackTrace) {
      debugPrint('Order notification error: $e\n$stackTrace');
    }
  }

  CheckoutException _checkoutFailure(String rawMessage, {String? code}) {
    final message = rawMessage.toLowerCase();
    if (message.contains('authentication_required')) {
      return const CheckoutException(
        code: 'authentication_required',
        message: 'Войдите в профиль, чтобы оформить заказ',
      );
    }
    if (message.contains('cannot_buy_own_listing')) {
      return const CheckoutException(
        code: 'cannot_buy_own_listing',
        message: 'Нельзя купить собственное объявление',
      );
    }
    if (message.contains('product_unavailable')) {
      return const CheckoutException(
        code: 'product_unavailable',
        message: 'Объявление уже недоступно',
      );
    }
    if (message.contains('listing_seller_required')) {
      return const CheckoutException(
        code: 'listing_seller_required',
        message: 'У объявления не указан продавец',
      );
    }
    if (message.contains('recipient_name_required')) {
      return const CheckoutException(
        code: 'recipient_name_required',
        message: 'Укажите имя получателя',
      );
    }
    if (message.contains('recipient_phone_required')) {
      return const CheckoutException(
        code: 'recipient_phone_required',
        message: 'Укажите телефон получателя',
      );
    }
    if (message.contains('recipient_email_invalid')) {
      return const CheckoutException(
        code: 'recipient_email_invalid',
        message: 'Проверьте email получателя',
      );
    }
    if (message.contains('delivery_destination_required')) {
      return const CheckoutException(
        code: 'delivery_destination_required',
        message: 'Выберите адрес или пункт выдачи',
      );
    }
    if (message.contains('pickup_point_required')) {
      return const CheckoutException(
        code: 'pickup_point_required',
        message: 'Выберите пункт выдачи',
      );
    }
    if (message.contains('unsupported_delivery_service')) {
      return const CheckoutException(
        code: 'unsupported_delivery_service',
        message: 'Этот способ доставки пока недоступен',
      );
    }
    if (message.contains('delivery_method_not_offered')) {
      return const CheckoutException(
        code: 'delivery_method_not_offered',
        message: 'Продавец не подключил выбранную службу доставки',
      );
    }
    if (message.contains('checkout_temporarily_disabled')) {
      return const CheckoutException(
        code: 'checkout_temporarily_disabled',
        message: 'Оформление временно приостановлено. Попробуйте позже.',
        isRetryable: true,
      );
    }
    if (message.contains('live_checkout_not_configured')) {
      return const CheckoutException(
        code: 'live_checkout_not_configured',
        message: 'Безопасная оплата и доставка ещё не подключены.',
      );
    }
    if (message.contains('verified_delivery_selection_required')) {
      return const CheckoutException(
        code: 'verified_delivery_selection_required',
        message: 'Выберите подтверждённый адрес службы доставки',
      );
    }
    if (code == 'PGRST202' ||
        code == '42883' ||
        message.contains('create_order')) {
      return const CheckoutException(
        code: 'checkout_not_deployed',
        message: 'Оформление временно недоступно. Попробуйте немного позже.',
        isRetryable: true,
      );
    }
    return const CheckoutException(
      code: 'checkout_unavailable',
      message:
          'Не удалось оформить заказ. Проверьте подключение и попробуйте ещё раз.',
      isRetryable: true,
    );
  }

  (String, String) _normalizeCheckoutDelivery(String rawValue) {
    final normalized = rawValue.trim();
    if (normalized == 'Почта России') return ('address', 'russian_post');
    if (normalized == 'Пункт выдачи') return ('pickup_point', 'unassigned');
    final parts = normalized.split(':');
    final type = switch (parts.firstOrNull) {
      'pickup_point' => 'pickup_point',
      _ => 'address',
    };
    final rawProvider = parts.length > 1 ? parts[1].trim() : 'unassigned';
    final provider =
        const {
          'cdek',
          'russian_post',
          'yandex_delivery',
          'unassigned',
        }.contains(rawProvider)
        ? rawProvider
        : 'unassigned';
    return (type, provider);
  }

  String _deliveryServiceLabel(String type, String provider) {
    final providerLabel = switch (provider) {
      'cdek' => 'СДЭК',
      'russian_post' => 'Почта России',
      'yandex_delivery' => 'Яндекс Доставка',
      _ => 'служба доставки',
    };
    return type == 'pickup_point'
        ? 'Пункт выдачи · $providerLabel'
        : 'До адреса · $providerLabel';
  }

  Future<void> markNotificationRead(String notificationId) async {
    var changed = false;
    _notifications = _notifications.map((notification) {
      if (notification.id != notificationId || notification.isRead) {
        return notification;
      }
      changed = true;
      return notification.copyWith(isRead: true);
    }).toList();
    if (changed) {
      await _saveNotificationsLocal();
      notifyListeners();
    }

    if (!_hasSupabase || currentUserId.isEmpty) return;
    try {
      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId)
          .eq('user_id', currentUserId);
    } catch (e) {
      debugPrint('Notification read sync error: $e');
    }
  }

  Future<void> markAllNotificationsRead() async {
    if (!_notifications.any((notification) => !notification.isRead)) return;
    _notifications = _notifications
        .map((notification) => notification.copyWith(isRead: true))
        .toList();
    await _saveNotificationsLocal();
    notifyListeners();

    if (!_hasSupabase || currentUserId.isEmpty) return;
    try {
      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', currentUserId)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('Notifications mark all read error: $e');
    }
  }

  Future<void> _addProfileNotification({
    required String title,
    required String body,
    required String kind,
    required String targetId,
  }) async {
    final notification = ProfileNotification(
      id: _uuid.v4(),
      title: title,
      body: body,
      kind: kind,
      targetId: targetId,
      createdAt: DateTime.now().toUtc(),
    );
    _notifications.removeWhere(
      (item) =>
          item.kind == kind && item.targetId == targetId && item.body == body,
    );
    _notifications.insert(0, notification);
    if (_notifications.length > 80) {
      _notifications.removeRange(80, _notifications.length);
    }
    await _saveNotificationsLocal();

    if (!_hasSupabase || currentUserId.isEmpty) return;
    try {
      await _client
          .from('notifications')
          .insert(notification.toSupabaseJson(currentUserId));
    } catch (e) {
      debugPrint('Notification insert error: $e');
    }
  }

  Future<void> _syncOutfitsFromSupabase() async {
    if (!_hasSupabase) return;

    try {
      final response = await _client
          .from('outfits')
          .select()
          .order('created_at', ascending: false);

      final fetched = (response as List<dynamic>)
          .map((item) => CreatedOutfit.fromSupabase(item))
          .toList();

      final localById = <String, CreatedOutfit>{
        for (final outfit in _outfits) outfit.id: outfit,
      };
      _outfits = fetched.map((remote) {
        final local = localById[remote.id];
        return local == null
            ? remote
            : remote.copyWith(
                isLiked: local.isLiked,
                viewsCount: remote.viewsCount < 0 ? 0 : remote.viewsCount,
                likesCount: remote.likesCount < 0 ? 0 : remote.likesCount,
              );
      }).toList();
      _applyOutfitFavoriteState();
      await _writeList(_outfitsKey, _outfits.map((item) => item.toJson()));
      notifyListeners();
    } catch (e) {
      debugPrint('Outfits sync error: $e');
    }
  }

  // ─── Image Upload ───

  Future<void> _syncBlockedUsers() async {
    if (!_hasSupabase || currentUserId.isEmpty) return;
    try {
      final response = await _client
          .from('blocked_users')
          .select('blocked_id')
          .eq('blocker_id', currentUserId);
      final remoteIds = (response as List<dynamic>)
          .whereType<Map>()
          .map((row) => row['blocked_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      if (setEquals(remoteIds, _blockedUserIds)) return;
      _blockedUserIds = remoteIds;
      await _saveBlockedUsers();
      notifyListeners();
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST205' && e.code != '42P01') rethrow;
    } catch (e) {
      debugPrint('Blocked users sync error: $e');
    }
  }

  Future<void> _syncUserCollectionsFromSupabase() async {
    if (!_hasSupabase || currentUserId.isEmpty) return;

    try {
      final productFavorites = await _client
          .from('product_favorites')
          .select('product_id')
          .eq('user_id', currentUserId);
      final outfitFavorites = await _client
          .from('outfit_favorites')
          .select('outfit_id')
          .eq('user_id', currentUserId);
      final followedSellers = await _client
          .from('profile_follows')
          .select('seller_id')
          .eq('follower_id', currentUserId);
      final recentProducts = await _client
          .from('recent_products')
          .select('product_id')
          .eq('user_id', currentUserId)
          .order('viewed_at', ascending: false);
      final recentOutfits = await _client
          .from('recent_outfits')
          .select('outfit_id')
          .eq('user_id', currentUserId)
          .order('viewed_at', ascending: false)
          .limit(24);

      final remoteFavoriteProductIds = (productFavorites as List<dynamic>)
          .map(
            (item) => (item as Map<String, dynamic>)['product_id'] as String?,
          )
          .whereType<String>()
          .toSet();
      final remoteFavoriteOutfitIds = (outfitFavorites as List<dynamic>)
          .map((item) => (item as Map<String, dynamic>)['outfit_id'] as String?)
          .whereType<String>()
          .toSet();
      final remoteFollowedSellerIds = (followedSellers as List<dynamic>)
          .map((item) => (item as Map<String, dynamic>)['seller_id'] as String?)
          .whereType<String>()
          .toSet();
      final remoteRecentProductIds = (recentProducts as List<dynamic>)
          .map(
            (item) => (item as Map<String, dynamic>)['product_id'] as String?,
          )
          .whereType<String>()
          .toList();
      final remoteRecentOutfitIds = (recentOutfits as List<dynamic>)
          .map((item) => (item as Map<String, dynamic>)['outfit_id'] as String?)
          .whereType<String>()
          .toList();

      _activateProductViewIdentity(currentUserId);
      _countedProductViewIds.addAll(remoteRecentProductIds);
      _activateOutfitViewIdentity(currentUserId);
      _countedOutfitViewIds.addAll(remoteRecentOutfitIds);

      _favoriteProductIds = {
        ..._favoriteProductIds,
        ...remoteFavoriteProductIds,
      };
      _favoriteOutfitIds = {..._favoriteOutfitIds, ...remoteFavoriteOutfitIds};
      _followedSellerIds = remoteFollowedSellerIds;
      _recentProductIds = _mergeRecentIds(
        remoteRecentProductIds,
        _recentProductIds,
      );
      _recentOutfitIds = _mergeRecentIds(
        remoteRecentOutfitIds,
        _recentOutfitIds,
      );

      _applyProductFavoriteState();
      _applyOutfitFavoriteState();
      await _pushLocalCollectionsToSupabase();
      await _saveCollectionState();
      await _saveCountedProductViews();
      await _saveCountedOutfitViews();
      await _saveProducts();
      await _writeList(_outfitsKey, _outfits.map((item) => item.toJson()));
      notifyListeners();
    } catch (e) {
      debugPrint('User collections sync error: $e');
    }
  }

  Future<void> _pushLocalCollectionsToSupabase() async {
    if (!_hasSupabase || currentUserId.isEmpty) return;

    final now = DateTime.now().toIso8601String();
    try {
      if (_favoriteProductIds.isNotEmpty) {
        await _client
            .from('product_favorites')
            .upsert(
              _favoriteProductIds
                  .map(
                    (id) => {
                      'user_id': currentUserId,
                      'product_id': id,
                      'created_at': now,
                    },
                  )
                  .toList(),
              onConflict: 'user_id,product_id',
            );
      }
      if (_favoriteOutfitIds.isNotEmpty) {
        await _client
            .from('outfit_favorites')
            .upsert(
              _favoriteOutfitIds
                  .map(
                    (id) => {
                      'user_id': currentUserId,
                      'outfit_id': id,
                      'created_at': now,
                    },
                  )
                  .toList(),
              onConflict: 'user_id,outfit_id',
            );
      }
      if (_recentProductIds.isNotEmpty) {
        await _client
            .from('recent_products')
            .upsert(
              _recentProductIds
                  .asMap()
                  .entries
                  .map(
                    (entry) => {
                      'user_id': currentUserId,
                      'product_id': entry.value,
                      'viewed_at': DateTime.now()
                          .subtract(Duration(milliseconds: entry.key))
                          .toIso8601String(),
                    },
                  )
                  .toList(),
              onConflict: 'user_id,product_id',
            );
      }
      // Outfit views are written per active identity by recordOutfitView.
      // Replaying the device-wide recent history here could attribute a
      // previous guest/account's views to the newly signed-in user.
    } catch (e) {
      debugPrint('Local collections push error: $e');
    }
  }

  Future<void> _syncAccessoriesFromSupabase() async {
    if (!_hasSupabase) return;

    try {
      final response = await _client
          .from('outfit_accessories')
          .select()
          .order('created_at', ascending: false);

      final fetched = (response as List<dynamic>)
          .map((item) => OutfitAccessory.fromSupabase(item))
          .toList();

      final merged = <String, OutfitAccessory>{
        for (final accessory in fetched) accessory.id: accessory,
      };
      for (final accessory in _accessories) {
        if (!accessory.isLocal) continue;
        merged.putIfAbsent(accessory.id, () => accessory);
      }
      _accessories = merged.values.toList();
      await _saveAccessories();
      notifyListeners();
    } catch (e) {
      debugPrint('Accessories sync error: $e');
    }
  }

  Future<String?> uploadImage(XFile imageFile, {String? folder}) async {
    if (!_hasSupabase) return null;
    try {
      final user = await _ensureAuthSession();
      if (user == null) return null;
      final ext = path.extension(imageFile.name).toLowerCase().isNotEmpty
          ? path.extension(imageFile.name).toLowerCase()
          : path.extension(imageFile.path).toLowerCase();
      final fileName = '${_uuid.v4()}$ext';
      final filePath = folder != null ? '$folder/$fileName' : fileName;

      const options = FileOptions(cacheControl: '3600', upsert: false);
      if (kIsWeb || imageFile.path.isEmpty) {
        await _client.storage
            .from(_bucketName)
            .uploadBinary(
              filePath,
              await imageFile.readAsBytes(),
              fileOptions: options,
            );
      } else {
        await _client.storage
            .from(_bucketName)
            .upload(filePath, File(imageFile.path), fileOptions: options);
      }

      final url = _client.storage.from(_bucketName).getPublicUrl(filePath);
      return url;
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  String _mimeTypeForImage(String name, String fallbackPath) {
    final ext = path.extension(name).isNotEmpty
        ? path.extension(name).toLowerCase()
        : path.extension(fallbackPath).toLowerCase();
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      case '.jpg':
      case '.jpeg':
      default:
        return 'image/jpeg';
    }
  }

  // ─── Products ───

  Future<bool> publishProduct(Product product) async {
    if (!_hasSupabase) return false;

    try {
      final user = await _ensureAuthSession();
      if (user == null) return false;

      final ownedProduct = product.copyWith(
        ownerId: user.id,
        sellerName: _profile.name,
        sellerHandle: _profile.handle,
        publishedAt: DateTime.now().toUtc(),
        viewsCount: 0,
        likesCount: 0,
      );
      final data = ownedProduct.toSupabaseJson(sellerId: user.id);
      await _client.from('products').upsert(data, onConflict: 'id');
      if (ownedProduct.outfitImages.isEmpty) {
        _queueBackgroundRemoval(ownedProduct);
      }

      _products.removeWhere((item) => item.id == ownedProduct.id);
      _products.insert(0, ownedProduct);
      await _saveProducts();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Publish to Supabase error: $e');
      return false;
    }
  }

  /// Caches a listing that was already atomically published by the dedicated
  /// publication repository, without writing it to Supabase a second time.
  Future<Product> adoptPublishedProduct(Product product) async {
    final ownedProduct = product.copyWith(
      ownerId: currentUserId,
      sellerName: _profile.name,
      sellerHandle: _profile.handle,
      status: 'published',
      isHidden: false,
    );
    _products.removeWhere((item) => item.id == ownedProduct.id);
    _products.insert(0, ownedProduct);
    await _saveProducts();
    notifyListeners();
    return ownedProduct;
  }

  void _queueBackgroundRemoval(Product product) {
    if (!_hasSupabase || product.image.isEmpty) return;

    unawaited(
      _client.functions
          .invoke('process-product-image', body: {'product_id': product.id})
          .then((_) => _syncFromSupabase())
          .catchError((e) {
            debugPrint('Background queue error: $e');
          }),
    );
  }

  Future<OutfitAccessory?> createOutfitAccessory({
    required XFile imageFile,
    required bool isDefault,
    required String title,
  }) async {
    if (isDefault) {
      _authError = 'Общие аксессуары добавляются после модерации';
      notifyListeners();
      return null;
    }
    final id = _uuid.v4();
    final user = _hasSupabase ? await _ensureAuthSession() : null;
    if (_hasSupabase && user == null) return null;

    final cleanTitle = title.trim().isEmpty ? 'Аксессуар' : title.trim();
    final localImage = imageFile.path;
    final fallback = OutfitAccessory(
      id: id,
      title: cleanTitle,
      image: localImage,
      cutoutImage: '',
      scope: 'private',
      ownerId: user?.id ?? currentUserId,
      isLocal: true,
    );

    if (!_hasSupabase) {
      _accessories.insert(0, fallback);
      await _saveAccessories();
      notifyListeners();
      return fallback;
    }

    try {
      final imageUrl = await uploadImage(
        imageFile,
        folder: 'accessories/${user!.id}',
      );
      if (imageUrl == null) return fallback;

      final accessory = fallback.copyWith(
        image: imageUrl,
        ownerId: user.id,
        isLocal: false,
      );

      await _client
          .from('outfit_accessories')
          .insert(accessory.toSupabaseJson());
      _queueAccessoryBackgroundRemoval(accessory);

      _accessories.removeWhere((item) => item.id == accessory.id);
      _accessories.insert(0, accessory);
      await _saveAccessories();
      notifyListeners();
      return accessory;
    } catch (e) {
      debugPrint('Create accessory error: $e');
      return fallback;
    }
  }

  void _queueAccessoryBackgroundRemoval(OutfitAccessory accessory) {
    if (!_hasSupabase || accessory.image.isEmpty) return;

    unawaited(
      _client.functions
          .invoke(
            'process-accessory-image',
            body: {'accessory_id': accessory.id},
          )
          .then((_) => _syncAccessoriesFromSupabase())
          .catchError((e) {
            debugPrint('Accessory background queue error: $e');
          }),
    );
  }

  Future<bool> toggleSellerFollow(String sellerId) async {
    final normalizedSellerId = sellerId.trim();
    if (!canFollowSeller(normalizedSellerId)) return false;

    final willFollow = !_followedSellerIds.contains(normalizedSellerId);
    if (willFollow) {
      _followedSellerIds.add(normalizedSellerId);
    } else {
      _followedSellerIds.remove(normalizedSellerId);
    }
    await _saveStringSet(
      _scopedStorageKey(_followedSellerIdsKey),
      _followedSellerIds,
    );
    notifyListeners();

    if (!_hasSupabase || currentUserId.isEmpty) return willFollow;
    try {
      if (willFollow) {
        await _client.from('profile_follows').upsert({
          'follower_id': currentUserId,
          'seller_id': normalizedSellerId,
        }, onConflict: 'follower_id,seller_id');
      } else {
        await _client
            .from('profile_follows')
            .delete()
            .eq('follower_id', currentUserId)
            .eq('seller_id', normalizedSellerId);
      }
      if (_followedSellerIds.isNotEmpty) {
        await _client
            .from('profile_follows')
            .upsert(
              _followedSellerIds
                  .where((sellerId) => sellerId != currentUserId)
                  .map(
                    (sellerId) => {
                      'follower_id': currentUserId,
                      'seller_id': sellerId,
                    },
                  )
                  .toList(),
              onConflict: 'follower_id,seller_id',
            );
      }
    } catch (e) {
      debugPrint('Seller follow sync error: $e');
      if (willFollow) {
        _followedSellerIds.remove(normalizedSellerId);
      } else {
        _followedSellerIds.add(normalizedSellerId);
      }
      await _saveStringSet(
        _scopedStorageKey(_followedSellerIdsKey),
        _followedSellerIds,
      );
      _authError = 'Не удалось обновить подписку. Попробуйте ещё раз.';
      notifyListeners();
    }
    return _followedSellerIds.contains(normalizedSellerId);
  }

  Future<void> toggleProductLike(String productId) async {
    final willLike = !_favoriteProductIds.contains(productId);
    final previousLikesCount = _productMetric(productId, metric: 'likes_count');
    if (willLike) {
      _favoriteProductIds.add(productId);
    } else {
      _favoriteProductIds.remove(productId);
    }
    for (final product in _products) {
      product.isLiked = _favoriteProductIds.contains(product.id);
      if (product.id != productId) continue;
      product.likesCount = (product.likesCount + (willLike ? 1 : -1))
          .clamp(0, 1 << 31)
          .toInt();
    }
    await _saveStringSet(
      _scopedStorageKey(_favoriteProductIdsKey),
      _favoriteProductIds,
    );
    await _saveProducts();
    notifyListeners();

    if (!_hasSupabase || currentUserId.isEmpty) return;
    try {
      if (willLike) {
        await _client.from('product_favorites').upsert({
          'user_id': currentUserId,
          'product_id': productId,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id,product_id');
      } else {
        await _client
            .from('product_favorites')
            .delete()
            .eq('user_id', currentUserId)
            .eq('product_id', productId);
      }
    } catch (e) {
      debugPrint('Product favorite sync error: $e');
      if (willLike) {
        _favoriteProductIds.remove(productId);
      } else {
        _favoriteProductIds.add(productId);
      }
      for (final product in _products) {
        product.isLiked = _favoriteProductIds.contains(product.id);
        if (product.id == productId) product.likesCount = previousLikesCount;
      }
      await _saveStringSet(
        _scopedStorageKey(_favoriteProductIdsKey),
        _favoriteProductIds,
      );
      await _saveProducts();
      _authError = 'Не удалось обновить избранное. Попробуйте ещё раз.';
      notifyListeners();
      return;
    }
    try {
      await _refreshProductMetric(productId, metric: 'likes_count');
    } catch (e) {
      debugPrint('Product favorite metric refresh error: $e');
    }
  }

  Future<void> toggleOutfitLike(String outfitId) async {
    final willLike = !_favoriteOutfitIds.contains(outfitId);
    final previousOutfit = _outfits
        .where((outfit) => outfit.id == outfitId)
        .firstOrNull;
    final previousLikesCount = previousOutfit?.likesCount ?? 0;
    if (willLike) {
      _favoriteOutfitIds.add(outfitId);
    } else {
      _favoriteOutfitIds.remove(outfitId);
    }
    var nextLikesCount = 0;
    _outfits = _outfits.map((outfit) {
      if (outfit.id != outfitId) {
        return outfit.copyWith(isLiked: _favoriteOutfitIds.contains(outfit.id));
      }
      nextLikesCount = outfit.likesCount + (willLike ? 1 : -1);
      if (nextLikesCount < 0) nextLikesCount = 0;
      return outfit.copyWith(isLiked: willLike, likesCount: nextLikesCount);
    }).toList();
    await _saveStringSet(
      _scopedStorageKey(_favoriteOutfitIdsKey),
      _favoriteOutfitIds,
    );
    await _writeList(_outfitsKey, _outfits.map((item) => item.toJson()));
    notifyListeners();

    if (!_hasSupabase || currentUserId.isEmpty) return;
    try {
      if (willLike) {
        await _client.from('outfit_favorites').upsert({
          'user_id': currentUserId,
          'outfit_id': outfitId,
          'created_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,outfit_id');
      } else {
        await _client
            .from('outfit_favorites')
            .delete()
            .eq('user_id', currentUserId)
            .eq('outfit_id', outfitId);
      }
    } catch (e) {
      debugPrint('Outfit favorite sync error: $e');
      if (willLike) {
        _favoriteOutfitIds.remove(outfitId);
      } else {
        _favoriteOutfitIds.add(outfitId);
      }
      _outfits = _outfits
          .map(
            (outfit) => outfit.id == outfitId
                ? outfit.copyWith(
                    isLiked: !willLike,
                    likesCount: previousLikesCount,
                  )
                : outfit.copyWith(
                    isLiked: _favoriteOutfitIds.contains(outfit.id),
                  ),
          )
          .toList();
      await _saveStringSet(
        _scopedStorageKey(_favoriteOutfitIdsKey),
        _favoriteOutfitIds,
      );
      await _writeList(_outfitsKey, _outfits.map((item) => item.toJson()));
      _authError = 'Не удалось обновить избранное. Попробуйте ещё раз.';
      notifyListeners();
      return;
    }
    try {
      final response = await _client
          .from('outfits')
          .select('likes_count')
          .eq('id', outfitId)
          .maybeSingle();
      final authoritative = (response?['likes_count'] as num?)?.toInt();
      if (authoritative != null) {
        await _applyAuthoritativeOutfitLikes(outfitId, authoritative);
      }
    } catch (e) {
      debugPrint('Outfit favorite metric refresh error: $e');
    }
  }

  Future<int> recordProductView(String productId) async {
    if (productId.isEmpty) return 0;
    final viewerId = currentUserId;
    _activateProductViewIdentity(viewerId);
    final isOwnListing = _products.any(
      (product) =>
          product.id == productId &&
          viewerId.isNotEmpty &&
          product.ownerId == viewerId,
    );
    final isFirstAuthorizedView =
        viewerId.isNotEmpty &&
        !isOwnListing &&
        _countedProductViewIds.add(productId);
    _recentProductIds.remove(productId);
    _recentProductIds.insert(0, productId);
    if (_recentProductIds.length > 24) {
      _recentProductIds.removeRange(24, _recentProductIds.length);
    }
    if (isFirstAuthorizedView) {
      for (final product in _products) {
        if (product.id != productId) continue;
        product.viewsCount = (product.viewsCount + 1).clamp(0, 1 << 31).toInt();
        break;
      }
    }
    await _writeStringList(
      _scopedStorageKey(_recentProductIdsKey),
      _recentProductIds,
    );
    if (isFirstAuthorizedView) await _saveCountedProductViews();
    if (isFirstAuthorizedView) await _saveProducts();
    notifyListeners();

    final currentCount = _productMetric(productId, metric: 'views_count');
    if (!_hasSupabase || viewerId.isEmpty) return currentCount;
    unawaited(_recordRemoteProductView(productId, viewerId));
    return currentCount;
  }

  Future<void> _recordRemoteProductView(
    String productId,
    String viewerId,
  ) async {
    try {
      final response = await _client.rpc(
        'record_product_view',
        params: {'p_product_id': productId},
      );
      Object? row = response;
      if (row is List && row.isNotEmpty) row = row.first;
      final authoritative = row is Map
          ? (row['views_count'] as num?)?.toInt()
          : null;
      if (authoritative != null && currentUserId == viewerId) {
        await _applyAuthoritativeProductViews(productId, authoritative);
      }
    } catch (e) {
      debugPrint('Product view sync error: $e');
    }
  }

  Future<void> _applyAuthoritativeProductViews(
    String productId,
    int remoteCount,
  ) async {
    final safeCount = remoteCount < 0 ? 0 : remoteCount;
    var changed = false;
    for (final product in _products) {
      if (product.id != productId || product.viewsCount == safeCount) continue;
      product.viewsCount = safeCount;
      changed = true;
      break;
    }
    if (!changed) return;
    await _saveProducts();
    notifyListeners();
  }

  int _productMetric(String productId, {required String metric}) {
    for (final product in _products) {
      if (product.id != productId) continue;
      return metric == 'likes_count' ? product.likesCount : product.viewsCount;
    }
    return 0;
  }

  Future<void> _refreshProductMetric(
    String productId, {
    required String metric,
  }) async {
    final response = await _client
        .from('products')
        .select(metric)
        .eq('id', productId)
        .maybeSingle();
    if (response == null) return;
    final authoritative = (response[metric] as num?)?.toInt();
    if (authoritative == null) return;
    for (final product in _products) {
      if (product.id != productId) continue;
      if (metric == 'likes_count') {
        product.likesCount = authoritative < 0 ? 0 : authoritative;
      } else {
        product.viewsCount = authoritative < 0 ? 0 : authoritative;
      }
      break;
    }
    await _saveProducts();
    notifyListeners();
  }

  Future<int> recordOutfitView(String outfitId) async {
    if (outfitId.isEmpty) return 0;
    final viewerId = currentUserId;
    _activateOutfitViewIdentity(viewerId);
    final isOwnOutfit = _outfits.any(
      (outfit) =>
          outfit.id == outfitId &&
          viewerId.isNotEmpty &&
          outfit.ownerId == viewerId,
    );
    final isFirstAuthorizedView =
        viewerId.isNotEmpty &&
        !isOwnOutfit &&
        _countedOutfitViewIds.add(outfitId);
    _recentOutfitIds.remove(outfitId);
    _recentOutfitIds.insert(0, outfitId);
    if (_recentOutfitIds.length > 24) {
      _recentOutfitIds.removeRange(24, _recentOutfitIds.length);
    }
    if (isFirstAuthorizedView) {
      _outfits = _outfits
          .map(
            (outfit) => outfit.id == outfitId
                ? outfit.copyWith(viewsCount: outfit.viewsCount + 1)
                : outfit,
          )
          .toList();
      await _writeList(_outfitsKey, _outfits.map((item) => item.toJson()));
      await _saveCountedOutfitViews();
    }
    await _writeStringList(
      _scopedStorageKey(_recentOutfitIdsKey),
      _recentOutfitIds,
    );
    notifyListeners();

    if (!_hasSupabase || viewerId.isEmpty) {
      return _outfitViewsCount(outfitId);
    }
    try {
      final remoteCount = await _recordRemoteOutfitView(
        outfitId,
        viewerId,
      ).timeout(const Duration(seconds: 4));
      if (remoteCount != null && currentUserId == viewerId) {
        await _applyAuthoritativeOutfitViews(outfitId, remoteCount);
      }
    } on TimeoutException {
      debugPrint('Outfit view sync timed out: $outfitId');
    } catch (e) {
      debugPrint('Outfit view sync error: $e');
    }
    return _outfitViewsCount(outfitId);
  }

  int _outfitViewsCount(String outfitId) {
    for (final outfit in _outfits) {
      if (outfit.id == outfitId) return outfit.viewsCount;
    }
    return 0;
  }

  Future<void> _applyAuthoritativeOutfitViews(
    String outfitId,
    int remoteCount,
  ) async {
    final safeRemoteCount = remoteCount < 0 ? 0 : remoteCount;
    var changed = false;
    _outfits = _outfits.map((outfit) {
      if (outfit.id != outfitId || safeRemoteCount == outfit.viewsCount) {
        return outfit;
      }
      changed = true;
      return outfit.copyWith(viewsCount: safeRemoteCount);
    }).toList();
    if (!changed) return;
    await _writeList(_outfitsKey, _outfits.map((item) => item.toJson()));
    notifyListeners();
  }

  Future<void> _applyAuthoritativeOutfitLikes(
    String outfitId,
    int remoteCount,
  ) async {
    final safeRemoteCount = remoteCount < 0 ? 0 : remoteCount;
    var changed = false;
    _outfits = _outfits.map((outfit) {
      if (outfit.id != outfitId || outfit.likesCount == safeRemoteCount) {
        return outfit;
      }
      changed = true;
      return outfit.copyWith(likesCount: safeRemoteCount);
    }).toList();
    if (!changed) return;
    await _writeList(_outfitsKey, _outfits.map((item) => item.toJson()));
    notifyListeners();
  }

  Future<int?> _recordRemoteOutfitView(String outfitId, String viewerId) async {
    try {
      final response = await _client.rpc(
        'record_outfit_view',
        params: {'p_outfit_id': outfitId},
      );
      Object? row = response;
      if (row is List && row.isNotEmpty) row = row.first;
      if (row is Map) {
        return (row['views_count'] as num?)?.toInt();
      }
    } catch (e) {
      debugPrint('Outfit view RPC fallback: $e');
    }

    try {
      await _client.from('recent_outfits').upsert({
        'user_id': viewerId,
        'outfit_id': outfitId,
        'viewed_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,outfit_id');
      final response = await _client
          .from('outfits')
          .select('views_count')
          .eq('id', outfitId)
          .maybeSingle();
      return (response?['views_count'] as num?)?.toInt();
    } catch (e) {
      debugPrint('Recent outfit sync error: $e');
      return null;
    }
  }

  Future<void> hideProduct(String productId) async {
    final product = _products.firstWhere((item) => item.id == productId);
    product.isHidden = true;
    await _saveProducts();
    notifyListeners();
  }

  Future<bool> submitContentReport({
    required String targetType,
    required String targetId,
    required String reason,
    String details = '',
  }) async {
    final normalizedType = targetType.trim();
    final normalizedTargetId = targetId.trim();
    final normalizedReason = reason.trim();
    if (normalizedTargetId.isEmpty || normalizedReason.isEmpty) return false;
    if (!_hasSupabase) return true;
    final user = await _ensureAuthSession(
      message: 'Войдите в профиль, чтобы отправить жалобу',
    );
    if (user == null) return false;
    try {
      await _client.from('content_reports').insert({
        'reporter_id': user.id,
        'target_type': normalizedType,
        'target_id': normalizedTargetId,
        'reason': normalizedReason,
        'details': details.trim(),
      });
      return true;
    } on PostgrestException catch (e) {
      // Repeated taps on an already open report are idempotent for the user.
      if (e.code == '23505') return true;
      debugPrint('Content report error: $e');
      return false;
    } catch (e) {
      debugPrint('Content report error: $e');
      return false;
    }
  }

  Future<bool> blockUser(String userId) async {
    final blockedId = userId.trim();
    if (blockedId.isEmpty || blockedId == currentUserId) return false;
    if (_hasSupabase) {
      final user = await _ensureAuthSession(
        message: 'Войдите в профиль, чтобы заблокировать пользователя',
      );
      if (user == null) return false;
    }

    _blockedUserIds.add(blockedId);
    await _saveBlockedUsers();
    notifyListeners();

    if (!_hasSupabase) return true;
    try {
      await _client.from('blocked_users').upsert({
        'blocker_id': currentUserId,
        'blocked_id': blockedId,
      }, onConflict: 'blocker_id,blocked_id');
      return true;
    } catch (e) {
      _blockedUserIds.remove(blockedId);
      await _saveBlockedUsers();
      notifyListeners();
      debugPrint('Block user error: $e');
      return false;
    }
  }

  Future<bool> unblockUser(String userId) async {
    final blockedId = userId.trim();
    if (blockedId.isEmpty) return false;
    final existed = _blockedUserIds.remove(blockedId);
    if (!existed) return true;
    await _saveBlockedUsers();
    notifyListeners();
    if (!_hasSupabase || currentUserId.isEmpty) return true;
    try {
      await _client
          .from('blocked_users')
          .delete()
          .eq('blocker_id', currentUserId)
          .eq('blocked_id', blockedId);
      return true;
    } catch (e) {
      _blockedUserIds.add(blockedId);
      await _saveBlockedUsers();
      notifyListeners();
      debugPrint('Unblock user error: $e');
      return false;
    }
  }

  Future<void> deleteProduct(String productId) async {
    if (_hasSupabase) {
      try {
        final deleted = await _client
            .from('products')
            .delete()
            .eq('id', productId)
            .select('id');
        if ((deleted as List<dynamic>).isEmpty) {
          throw StateError('product_delete_not_permitted');
        }
      } catch (e) {
        debugPrint('Product delete error: $e');
        rethrow;
      }
    }

    _products.removeWhere((item) => item.id == productId);
    _favoriteProductIds.remove(productId);
    _recentProductIds.remove(productId);
    await _saveProducts();
    await _saveStringSet(
      _scopedStorageKey(_favoriteProductIdsKey),
      _favoriteProductIds,
    );
    await _writeStringList(
      _scopedStorageKey(_recentProductIdsKey),
      _recentProductIds,
    );
    notifyListeners();
  }

  // ─── Outfits ───

  Future<void> publishOutfit(CreatedOutfit outfit) async {
    final user = _hasSupabase ? await _ensureAuthSession() : null;
    if (_hasSupabase && user == null) return;

    final publishedAt = DateTime.now().toUtc();
    final ownedOutfit = outfit.copyWith(
      ownerId: user?.id ?? currentUserId,
      authorName: _profile.name,
      authorHandle: _profile.handle,
      authorAvatarUrl: _profile.avatarUrl,
      publishedAt: publishedAt,
    );

    if (_hasSupabase) {
      try {
        await _client.from('outfits').insert({
          'id': ownedOutfit.id,
          'owner_id': ownedOutfit.ownerId,
          'author_name': ownedOutfit.authorName,
          'author_handle': ownedOutfit.authorHandle,
          'author_avatar_url': ownedOutfit.authorAvatarUrl,
          'photos': ownedOutfit.photos,
          'items': ownedOutfit.items.map((i) => i.toJson()).toList(),
          'preview_layout': {
            'backgroundColor': ownedOutfit.previewBackgroundColor,
            'items': ownedOutfit.layoutItems.map((i) => i.toJson()).toList(),
          },
          'created_at': publishedAt.toIso8601String(),
        });
      } catch (e) {
        debugPrint('Outfit publish error: $e');
        _authError = 'Не удалось опубликовать образ. Попробуйте ещё раз';
        notifyListeners();
        rethrow;
      }
    }

    _outfits.removeWhere((item) => item.id == ownedOutfit.id);
    _outfits.insert(0, ownedOutfit);
    await _writeList(_outfitsKey, _outfits.map((item) => item.toJson()));
    notifyListeners();
  }

  // ─── Messages ───

  Future<MessageThread?> contactSeller(
    Product product, {
    bool imageOnly = false,
  }) async {
    final user = _hasSupabase
        ? await _ensureAuthSession(
            message: 'Войдите в профиль, чтобы написать продавцу',
          )
        : null;
    if (_hasSupabase && user == null) return null;

    final buyerId = user?.id ?? currentUserId;
    final sellerId = product.ownerId;
    if (_hasSupabase && sellerId.isEmpty) {
      _authError = 'У объявления не указан продавец';
      notifyListeners();
      return null;
    }
    if (buyerId.isNotEmpty && sellerId == buyerId) {
      _authError = 'Это ваше объявление';
      notifyListeners();
      return null;
    }

    final threadId = _messageThreadId(
      productId: product.id,
      buyerId: buyerId,
      sellerId: sellerId,
    );
    final existing = threadById(threadId);
    if (existing != null) {
      if (!imageOnly) return existing;
      final updated = existing.copyWith(
        productTitle: '',
        productImage: product.image,
      );
      _upsertLocalThread(updated);
      await _saveThreadsLocal();
      await _saveThreadOrShowError(updated);
      notifyListeners();
      return updated;
    }
    MessageThread? remoteExisting;
    try {
      remoteExisting = await _fetchThreadFromSupabase(threadId);
    } catch (_) {
      _authError = 'Не удалось проверить диалог. Попробуйте ещё раз.';
      notifyListeners();
      return null;
    }
    if (remoteExisting != null) {
      final thread = imageOnly
          ? remoteExisting.copyWith(
              productTitle: '',
              productImage: product.image,
            )
          : remoteExisting;
      _upsertLocalThread(thread);
      await _saveThreadsLocal();
      if (imageOnly) {
        await _saveThreadOrShowError(thread);
      }
      notifyListeners();
      return thread;
    }

    final now = DateTime.now();
    final publicSeller = await fetchSellerProfile(product);
    final sellerName = publicSeller?.name.trim().isNotEmpty == true
        ? publicSeller!.name
        : (product.sellerName.trim().isEmpty ? 'Продавец' : product.sellerName);
    final sellerHandle = publicSeller?.handle.trim().isNotEmpty == true
        ? publicSeller!.handle
        : product.sellerHandle;
    final sellerAvatar = publicSeller?.avatarUrl.trim() ?? '';
    const firstMessage = 'Здравствуйте! Вещь ещё доступна?';
    _threads.removeWhere((thread) => thread.id == threadId);
    _threads.insert(
      0,
      MessageThread(
        id: threadId,
        sellerName: sellerName,
        buyerName: _profile.name,
        sellerHandle: sellerHandle,
        buyerHandle: _profile.handle,
        buyerAvatar: _currentAvatarUrl(),
        sellerAvatar: sellerAvatar,
        productTitle: imageOnly ? '' : product.title,
        lastMessage: firstMessage,
        updatedAt: now,
        productId: product.id,
        productImage: product.image,
        buyerId: buyerId,
        sellerId: sellerId,
        members: [
          ConversationMember(
            id: buyerId,
            name: _profile.name,
            handle: _profile.handle,
            avatarUrl: _currentAvatarUrl(),
          ),
          ConversationMember(
            id: sellerId,
            name: sellerName,
            handle: sellerHandle,
            avatarUrl: sellerAvatar,
          ),
        ],
        unreadCount: 0,
        messages: [
          ChatMessage(
            id: _uuid.v4(),
            text: firstMessage,
            createdAt: now,
            isMine: true,
            senderId: buyerId,
            senderName: _profile.name,
            senderAvatar: _currentAvatarUrl(),
          ),
        ],
      ),
    );
    _sortThreads();
    await _saveThreadsLocal();
    final createdThread = threadById(threadId) ?? _threads.first;
    final didCreate = await _saveThreadOrShowError(
      createdThread,
      newMessages: [createdThread.messages.last],
      ensureThreadFirst: true,
    );
    if (!didCreate) {
      await _discardFailedThreadCreation(threadId);
      return null;
    }
    unawaited(
      _notifyMessageRecipient(createdThread, createdThread.messages.last),
    );
    notifyListeners();
    return threadById(threadId) ?? createdThread;
  }

  Future<List<AppUserProfile>> searchUserProfiles(String query) async {
    final safeQuery = query.trim().replaceAll(
      RegExp(r'[^a-zA-Z0-9_а-яА-ЯёЁ .-]'),
      '',
    );
    final normalized = _normalizeHandle(safeQuery);
    final plainQuery = safeQuery.replaceAll('@', '');
    if (!_hasSupabase || plainQuery.length < 2) return const [];

    try {
      final pattern = '%${plainQuery.toLowerCase()}%';
      final response = await _client
          .from('profiles')
          .select('id,name,handle,avatar_url')
          .or('handle.ilike.$pattern,name.ilike.$pattern')
          .neq('id', currentUserId)
          .limit(20);
      final profiles = (response as List<dynamic>)
          .map((item) => AppUserProfile.fromSupabase(item))
          .where((profile) {
            if (profile.id.isEmpty) return false;
            if (query.trim().startsWith('@')) {
              return profile.handle.toLowerCase().contains(
                normalized.substring(1),
              );
            }
            return true;
          })
          .toList();
      profiles.sort((a, b) => a.handle.compareTo(b.handle));
      return profiles;
    } catch (e) {
      debugPrint('Profile search error: $e');
      return const [];
    }
  }

  Future<MessageThread?> startDirectChat(AppUserProfile recipient) async {
    final user = _hasSupabase
        ? await _ensureAuthSession(message: 'Войдите в профиль, чтобы написать')
        : null;
    if (_hasSupabase && user == null) return null;
    if (recipient.id.isEmpty || recipient.id == currentUserId) return null;

    final senderId = user?.id ?? currentUserId;
    final threadId = _directThreadId(senderId, recipient.id);
    final existing = threadById(threadId);
    if (existing != null) return existing;

    MessageThread? remoteExisting;
    try {
      remoteExisting = await _fetchThreadFromSupabase(threadId);
    } catch (_) {
      _authError = 'Не удалось проверить диалог. Попробуйте ещё раз.';
      notifyListeners();
      return null;
    }
    if (remoteExisting != null) {
      _upsertLocalThread(remoteExisting);
      await _saveThreadsLocal();
      notifyListeners();
      return remoteExisting;
    }

    final now = DateTime.now();
    final thread = MessageThread(
      id: threadId,
      sellerName: recipient.name,
      buyerName: _profile.name,
      sellerHandle: recipient.handle,
      buyerHandle: _profile.handle,
      sellerAvatar: recipient.avatarUrl,
      buyerAvatar: _currentAvatarUrl(),
      productTitle: '',
      lastMessage: '',
      updatedAt: now,
      buyerId: senderId,
      sellerId: recipient.id,
      members: [
        _currentConversationMember(senderId),
        ConversationMember(
          id: recipient.id,
          name: recipient.name,
          handle: recipient.handle,
          avatarUrl: recipient.avatarUrl,
        ),
      ],
      messages: const [],
    );

    _threads.removeWhere((item) => item.id == threadId);
    _threads.insert(0, thread);
    _sortThreads();
    await _saveThreadsLocal();
    final didCreate = await _saveThreadOrShowError(
      thread,
      ensureThreadFirst: true,
    );
    if (!didCreate) {
      await _discardFailedThreadCreation(threadId);
      return null;
    }
    notifyListeners();
    return thread;
  }

  Future<MessageThread?> createConversation(
    List<AppUserProfile> recipients, {
    String title = '',
  }) async {
    final user = _hasSupabase
        ? await _ensureAuthSession(message: 'Войдите, чтобы создать беседу')
        : null;
    if (_hasSupabase && user == null) return null;
    final senderId = user?.id ?? currentUserId;
    final uniqueRecipients = <String, AppUserProfile>{
      for (final recipient in recipients)
        if (recipient.id.isNotEmpty && recipient.id != senderId)
          recipient.id: recipient,
    }.values.toList(growable: false);
    if (uniqueRecipients.isEmpty) return null;
    if (uniqueRecipients.length == 1) {
      return startDirectChat(uniqueRecipients.single);
    }

    final now = DateTime.now();
    final members = [
      _currentConversationMember(senderId),
      ...uniqueRecipients.map(
        (recipient) => ConversationMember(
          id: recipient.id,
          name: recipient.name,
          handle: recipient.handle,
          avatarUrl: recipient.avatarUrl,
        ),
      ),
    ];
    final cleanTitle = title.trim();
    final fallbackTitle = uniqueRecipients
        .map((recipient) => recipient.name.trim())
        .where((name) => name.isNotEmpty)
        .take(3)
        .join(', ');
    final systemMessage = ChatMessage(
      id: _uuid.v4(),
      text: 'Беседа создана',
      createdAt: now,
      isMine: true,
      senderId: senderId,
      senderName: _profile.name,
      senderAvatar: _currentAvatarUrl(),
      type: 'system',
    );
    final thread = MessageThread(
      id: 'group_${_uuid.v4()}',
      sellerName: uniqueRecipients.first.name,
      buyerName: _profile.name,
      sellerHandle: uniqueRecipients.first.handle,
      buyerHandle: _profile.handle,
      sellerAvatar: uniqueRecipients.first.avatarUrl,
      buyerAvatar: _currentAvatarUrl(),
      productTitle: '',
      lastMessage: systemMessage.text,
      updatedAt: now,
      buyerId: senderId,
      sellerId: uniqueRecipients.first.id,
      isGroup: true,
      title: cleanTitle.isEmpty ? fallbackTitle : cleanTitle,
      createdBy: senderId,
      members: members,
      messages: [systemMessage],
    );
    _upsertLocalThread(thread);
    await _saveThreadsLocal();
    final didCreate = await _saveThreadOrShowError(
      thread,
      newMessages: [systemMessage],
      ensureThreadFirst: true,
    );
    if (!didCreate) {
      await _discardFailedThreadCreation(thread.id);
      return null;
    }
    notifyListeners();
    return thread;
  }

  Future<MessageThread?> shareProductToUser(
    AppUserProfile recipient,
    Product product,
  ) async {
    final thread = await startDirectChat(recipient);
    if (thread == null) return null;
    final sent = await shareProductToThread(thread.id, product);
    return sent ? threadById(thread.id) : null;
  }

  Future<bool> shareProductToThread(String threadId, Product product) async {
    final user = _hasSupabase
        ? await _ensureAuthSession(message: 'Войдите, чтобы поделиться')
        : null;
    if (_hasSupabase && user == null) return false;
    if (_hasSupabase && threadById(threadId) == null) {
      try {
        final remoteThread = await _fetchThreadFromSupabase(threadId);
        if (remoteThread != null) _upsertLocalThread(remoteThread);
      } catch (_) {
        _authError = 'Не удалось загрузить диалог. Попробуйте ещё раз.';
        notifyListeners();
        return false;
      }
    }
    final index = _threads.indexWhere((thread) => thread.id == threadId);
    if (index == -1) return false;
    final thread = _threads[index];
    final senderId = user?.id ?? currentUserId;
    if (_hasSupabase && !thread.containsUser(senderId)) return false;
    final now = DateTime.now();
    final message = ChatMessage(
      id: _uuid.v4(),
      text: 'Объявление: ${product.title}',
      createdAt: now,
      isMine: true,
      senderId: senderId,
      senderName: _profile.name,
      senderAvatar: _currentAvatarUrl(),
      type: 'product',
      sharedProduct: SharedProductPreview(
        id: product.id,
        title: product.title,
        image: product.image,
        price: product.price,
        sellerHandle: product.sellerHandle,
      ),
      isPending: _hasSupabase,
    );
    return _appendOutgoingMessage(thread, message);
  }

  Future<bool> sendChatText(String threadId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    final user = _hasSupabase
        ? await _ensureAuthSession(
            message: 'Войдите в профиль, чтобы отправить сообщение',
          )
        : null;
    if (_hasSupabase && user == null) return false;

    if (_hasSupabase && threadById(threadId) == null) {
      try {
        final remoteThread = await _fetchThreadFromSupabase(threadId);
        if (remoteThread != null) {
          _upsertLocalThread(remoteThread);
        }
      } catch (_) {
        _authError = 'Не удалось загрузить диалог. Попробуйте ещё раз.';
        notifyListeners();
        return false;
      }
    }

    final index = _threads.indexWhere((thread) => thread.id == threadId);
    if (index == -1) return false;

    final now = DateTime.now();
    final thread = _threads[index];
    final senderId = user?.id ?? currentUserId;
    if (_hasSupabase && !thread.containsUser(senderId)) {
      return false;
    }

    final message = ChatMessage(
      id: _uuid.v4(),
      text: trimmed,
      createdAt: now,
      isMine: true,
      senderId: senderId,
      senderName: _profile.name,
      senderAvatar: _currentAvatarUrl(),
      isPending: _hasSupabase,
    );

    return _appendOutgoingMessage(thread, message);
  }

  Future<bool> sendMessage(String threadId, String text) {
    return sendChatText(threadId, text);
  }

  Future<bool> sendPendingChatText(
    String threadId,
    ChatMessage pendingMessage,
  ) async {
    final trimmed = pendingMessage.text.trim();
    if (threadId.isEmpty || pendingMessage.id.isEmpty || trimmed.isEmpty) {
      return false;
    }

    final actorId = await _resolveChatActor(
      message: 'Войдите в профиль, чтобы отправить сообщение',
    );
    if (actorId == null) return false;

    final thread = threadById(threadId);
    if (thread == null || (_hasSupabase && !thread.containsUser(actorId))) {
      return false;
    }
    if (thread.messages.any((message) => message.id == pendingMessage.id)) {
      return false;
    }

    final message = pendingMessage.copyWith(
      text: trimmed,
      isMine: true,
      senderId: actorId,
      senderName: _profile.name,
      senderAvatar: _currentAvatarUrl(),
      type: 'text',
      isPending: _hasSupabase,
      hasError: false,
    );
    return _appendOutgoingMessage(thread, message);
  }

  Future<bool> retryChatText(String threadId, ChatMessage failedMessage) async {
    final trimmed = failedMessage.text.trim();
    if (threadId.isEmpty ||
        failedMessage.id.isEmpty ||
        trimmed.isEmpty ||
        failedMessage.type != 'text' ||
        !failedMessage.hasError) {
      return false;
    }

    final actorId = await _resolveChatActor(
      message: 'Войдите в профиль, чтобы повторить отправку',
    );
    if (actorId == null) return false;

    var thread = threadById(threadId);
    if (thread == null || (_hasSupabase && !thread.containsUser(actorId))) {
      return false;
    }

    final existingIndex = thread.messages.indexWhere(
      (message) => message.id == failedMessage.id,
    );
    final candidate = existingIndex == -1
        ? failedMessage
        : thread.messages[existingIndex];
    final belongsToActor = _hasSupabase
        ? candidate.senderId == actorId
        : candidate.isMine ||
              candidate.senderId.isEmpty ||
              candidate.senderId == actorId;
    if (!candidate.hasError ||
        candidate.isDeleted ||
        candidate.type != 'text' ||
        !belongsToActor) {
      return false;
    }

    final retrying = candidate.copyWith(
      text: trimmed,
      isPending: _hasSupabase,
      hasError: false,
    );
    if (existingIndex == -1) {
      thread = thread.copyWith(
        lastMessage: retrying.previewText,
        updatedAt: retrying.createdAt,
        messages: [...thread.messages, retrying],
      );
      _upsertLocalThread(thread);
      await _saveThreadsLocal();
      notifyListeners();
    } else {
      await _replaceLocalMessage(threadId, retrying, updateLastPreview: true);
      thread = threadById(threadId) ?? thread;
    }

    final saved = await _upsertThread(thread, newMessages: [retrying]);
    if (_hasSupabase) {
      await _replaceLocalMessage(
        threadId,
        retrying.copyWith(isPending: false, hasError: !saved),
        updateLastPreview: true,
      );
    }
    if (saved) {
      final latestThread = threadById(threadId) ?? thread;
      unawaited(_notifyMessageRecipient(latestThread, retrying));
    } else {
      _authError = 'Не удалось повторно отправить сообщение.';
      notifyListeners();
    }
    return saved;
  }

  Future<bool> retryChatMedia(
    String threadId,
    ChatMessage failedMessage,
  ) async {
    final failedAttachment = failedMessage.attachment;
    if (threadId.isEmpty ||
        failedMessage.id.isEmpty ||
        !failedMessage.hasError ||
        !failedMessage.isMedia ||
        failedAttachment == null ||
        failedAttachment.url.trim().isEmpty ||
        failedAttachment.hasRemoteObject) {
      return false;
    }

    final actorId = await _resolveChatActor(
      message: 'Войдите в профиль, чтобы повторить отправку вложения',
    );
    if (actorId == null) return false;

    final thread = threadById(threadId);
    if (thread == null || (_hasSupabase && !thread.containsUser(actorId))) {
      return false;
    }
    final existingIndex = thread.messages.indexWhere(
      (message) => message.id == failedMessage.id,
    );
    if (existingIndex == -1) return false;
    final candidate = thread.messages[existingIndex];
    final belongsToActor = _hasSupabase
        ? candidate.senderId == actorId
        : candidate.isMine ||
              candidate.senderId.isEmpty ||
              candidate.senderId == actorId;
    final attachment = candidate.attachment;
    if (!candidate.hasError ||
        candidate.isDeleted ||
        !candidate.isMedia ||
        attachment == null ||
        attachment.url.trim().isEmpty ||
        attachment.hasRemoteObject ||
        !belongsToActor) {
      return false;
    }

    var localPath = attachment.url.trim();
    if (localPath.startsWith('http://') ||
        localPath.startsWith('https://') ||
        localPath.startsWith('data:')) {
      return false;
    }
    if (localPath.startsWith('file://')) {
      try {
        localPath = Uri.parse(
          localPath,
        ).toFilePath(windows: Platform.isWindows);
      } catch (error, stackTrace) {
        debugPrint('Retry chat media path error: $error');
        debugPrintStack(stackTrace: stackTrace);
        return false;
      }
    }

    final mediaFile = XFile(localPath, name: attachment.name);
    final kind = candidate.isVideo ? ChatMediaKind.video : ChatMediaKind.image;
    ChatMessage? retryingMessage;
    final sent = await _chatMediaSendCoordinator.send(
      ensureRemoteThread: () => _upsertThread(thread),
      upload: () => _uploadChatMedia(
        threadId: threadId,
        actorId: actorId,
        mediaFile: mediaFile,
        kind: kind,
      ),
      persist: (uploaded) async {
        final latestThread = threadById(threadId);
        if (latestThread == null ||
            (_hasSupabase &&
                (currentUserId != actorId ||
                    !latestThread.containsUser(actorId)))) {
          return false;
        }
        final currentIndex = latestThread.messages.indexWhere(
          (message) => message.id == candidate.id,
        );
        if (currentIndex == -1) return false;
        final current = latestThread.messages[currentIndex];
        if (!current.hasError || !current.isMedia || current.isDeleted) {
          return false;
        }

        final retrying = current.copyWith(
          attachment: uploaded,
          isPending: _hasSupabase,
          hasError: false,
        );
        retryingMessage = retrying;
        await _replaceLocalMessage(threadId, retrying, updateLastPreview: true);
        final threadToSave = threadById(threadId);
        if (threadToSave == null) return false;
        final saved = await _upsertThread(
          threadToSave,
          newMessages: [retrying],
        );
        if (saved) {
          final delivered = retrying.copyWith(
            isPending: false,
            hasError: false,
          );
          await _replaceLocalMessage(
            threadId,
            delivered,
            updateLastPreview: true,
          );
          final deliveredThread = threadById(threadId) ?? threadToSave;
          unawaited(_notifyMessageRecipient(deliveredThread, delivered));
        }
        return saved;
      },
      markFailed: (uploaded) async {
        final localAttachment = _chatMediaSendCoordinator
            .localFailureAttachment(uploaded, localUrl: localPath);
        await _markLocalOutgoingMessageFailed(
          threadId,
          (retryingMessage ?? candidate).copyWith(attachment: localAttachment),
          actorId: actorId,
        );
      },
      cleanup: (uploaded) => _removeRemoteChatMedia(
        uploaded.bucket,
        uploaded.storagePath,
        logContext: 'Failed retried chat media cleanup',
      ),
    );
    if (!sent) {
      _authError = 'Не удалось повторно отправить вложение.';
      notifyListeners();
    }
    return sent;
  }

  Future<bool> sendReply(
    String threadId,
    String text,
    ChatMessage replyTo,
  ) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || replyTo.id.isEmpty) return false;

    final actorId = await _resolveChatActor(
      message: 'Войдите в профиль, чтобы отправить сообщение',
    );
    if (actorId == null) return false;
    final thread = threadById(threadId);
    if (thread == null || (_hasSupabase && !thread.containsUser(actorId))) {
      return false;
    }

    ChatMessage? target;
    for (final message in thread.messages) {
      if (message.id == replyTo.id) {
        target = message;
        break;
      }
    }
    if (target == null) return false;

    final now = DateTime.now();
    final message = ChatMessage(
      id: _uuid.v4(),
      text: trimmed,
      createdAt: now,
      isMine: true,
      senderId: actorId,
      senderName: _profile.name,
      senderAvatar: _currentAvatarUrl(),
      replyToId: target.id,
      replyToText: target.previewText,
      replyToSenderName: _replySenderName(thread, target),
      isPending: _hasSupabase,
    );
    return _appendOutgoingMessage(thread, message);
  }

  Future<bool> sendChatImage(
    String threadId,
    XFile imageFile, {
    String caption = '',
    ChatMessage? replyTo,
  }) async {
    return sendChatMedia(
      threadId,
      imageFile,
      kind: ChatMediaKind.image,
      caption: caption,
      replyTo: replyTo,
    );
  }

  Future<bool> sendChatMedia(
    String threadId,
    XFile mediaFile, {
    required ChatMediaKind kind,
    String caption = '',
    ChatMessage? replyTo,
  }) async {
    final actorId = await _resolveChatActor(
      message: kind == ChatMediaKind.video
          ? 'Войдите в профиль, чтобы отправить видео'
          : 'Войдите в профиль, чтобы отправить фотографию',
    );
    if (actorId == null) return false;

    var thread = threadById(threadId);
    if (thread == null || (_hasSupabase && !thread.containsUser(actorId))) {
      return false;
    }

    ChatMessage? target;
    if (replyTo != null) {
      for (final message in thread.messages) {
        if (message.id == replyTo.id) {
          target = message;
          break;
        }
      }
      if (target == null) return false;
    }

    final initialThread = thread;
    ChatMessage? outgoingMessage;
    return _chatMediaSendCoordinator.send(
      ensureRemoteThread: () async {
        final ready = await _upsertThread(initialThread);
        if (!ready) {
          _authError = 'Не удалось подготовить чат. Проверьте подключение.';
          notifyListeners();
        }
        return ready;
      },
      upload: () => _uploadChatMedia(
        threadId: threadId,
        actorId: actorId,
        mediaFile: mediaFile,
        kind: kind,
      ),
      persist: (attachment) async {
        // Auth or membership may have changed while a large file uploaded.
        final latestThread = threadById(threadId);
        if (latestThread == null ||
            (_hasSupabase &&
                (currentUserId != actorId ||
                    !latestThread.containsUser(actorId)))) {
          return false;
        }

        ChatMessage? latestReplyTarget;
        if (target != null) {
          for (final message in latestThread.messages) {
            if (message.id == target.id && !message.isDeleted) {
              latestReplyTarget = message;
              break;
            }
          }
          if (latestReplyTarget == null) return false;
        }

        final now = DateTime.now();
        final message = ChatMessage(
          id: _uuid.v4(),
          text: caption.trim(),
          createdAt: now,
          isMine: true,
          senderId: actorId,
          senderName: _profile.name,
          senderAvatar: _currentAvatarUrl(),
          type: kind == ChatMediaKind.video ? 'video' : 'image',
          attachment: attachment,
          replyToId: latestReplyTarget?.id ?? '',
          replyToText: latestReplyTarget?.previewText ?? '',
          replyToSenderName: latestReplyTarget == null
              ? ''
              : _replySenderName(latestThread, latestReplyTarget),
          isPending: _hasSupabase,
        );
        outgoingMessage = message;
        return _appendOutgoingMessage(latestThread, message);
      },
      markFailed: (attachment) async {
        final message = outgoingMessage;
        if (message == null || (_hasSupabase && currentUserId != actorId)) {
          return;
        }
        final localAttachment = _chatMediaSendCoordinator
            .localFailureAttachment(attachment, localUrl: mediaFile.path);
        await _markLocalOutgoingMessageFailed(
          threadId,
          message.copyWith(attachment: localAttachment),
          actorId: actorId,
        );
      },
      cleanup: (attachment) => _removeRemoteChatMedia(
        attachment.bucket,
        attachment.storagePath,
        logContext: 'Failed chat media cleanup',
      ),
    );
  }

  Future<ChatAttachment?> _uploadChatMedia({
    required String threadId,
    required String actorId,
    required XFile mediaFile,
    required ChatMediaKind kind,
  }) async {
    int size;
    try {
      size = await mediaFile.length();
    } catch (e) {
      debugPrint('Chat media size read error: $e');
      return null;
    }

    final maxBytes = kind == ChatMediaKind.video
        ? _maxChatVideoBytes
        : _maxChatImageBytes;
    if (size <= 0 || size > maxBytes) {
      _authError = kind == ChatMediaKind.video
          ? 'Видео должно быть не больше 100 МБ'
          : 'Фотография должна быть не больше 20 МБ';
      notifyListeners();
      return null;
    }

    final mimeType = _mimeTypeForChatMedia(
      mediaFile.name,
      mediaFile.path,
      kind,
    );
    if (mimeType == null) {
      _authError = kind == ChatMediaKind.video
          ? 'Поддерживаются MP4, MOV и WebM'
          : 'Поддерживаются JPEG, PNG, WebP, GIF и HEIC';
      notifyListeners();
      return null;
    }

    if (!_hasSupabase) {
      final localUrl = kind == ChatMediaKind.image
          ? await _inlineImage(mediaFile)
          : mediaFile.path;
      if (localUrl == null || localUrl.isEmpty) return null;
      return ChatAttachment(
        url: localUrl,
        name: mediaFile.name,
        mimeType: mimeType,
        size: size,
      );
    }

    final extension = _chatMediaExtension(mediaFile.name, mediaFile.path, kind);
    final storagePath = 'threads/$threadId/$actorId/${_uuid.v4()}$extension';
    final storage = _client.storage.from(_chatMediaBucketName);
    var uploadStarted = false;
    try {
      final options = FileOptions(
        cacheControl: '3600',
        upsert: false,
        contentType: mimeType,
      );
      if (kIsWeb || mediaFile.path.isEmpty) {
        uploadStarted = true;
        await storage.uploadBinary(
          storagePath,
          await mediaFile.readAsBytes(),
          fileOptions: options,
        );
      } else {
        uploadStarted = true;
        await storage.upload(
          storagePath,
          File(mediaFile.path),
          fileOptions: options,
        );
      }
      final signedUrl = await storage.createSignedUrl(
        storagePath,
        _chatMediaSignedUrlSeconds,
      );
      return ChatAttachment(
        url: signedUrl,
        name: mediaFile.name,
        mimeType: mimeType,
        size: size,
        bucket: _chatMediaBucketName,
        storagePath: storagePath,
      );
    } catch (e) {
      debugPrint('Chat media upload error: $e');
      if (uploadStarted) {
        await _removeRemoteChatMedia(
          _chatMediaBucketName,
          storagePath,
          logContext: 'Incomplete chat media upload cleanup',
        );
      }
      _authError = 'Не удалось загрузить медиа. Проверьте подключение.';
      notifyListeners();
      return null;
    }
  }

  Future<void> _removeRemoteChatMedia(
    String bucket,
    String storagePath, {
    required String logContext,
  }) async {
    final cleanBucket = bucket.trim();
    final cleanPath = storagePath.trim();
    if (!_hasSupabase || cleanBucket.isEmpty || cleanPath.isEmpty) return;
    _chatMediaUrlCache.invalidate(_chatMediaCacheKey(cleanBucket, cleanPath));
    try {
      await _client.storage.from(cleanBucket).remove([cleanPath]);
    } catch (e) {
      debugPrint('$logContext error: $e');
    }
  }

  String _chatMediaExtension(
    String name,
    String fallbackPath,
    ChatMediaKind kind,
  ) {
    final fromName = path.extension(name).toLowerCase();
    if (fromName.isNotEmpty) return fromName;
    final fromPath = path.extension(fallbackPath).toLowerCase();
    if (fromPath.isNotEmpty) return fromPath;
    return kind == ChatMediaKind.video ? '.mp4' : '.jpg';
  }

  String? _mimeTypeForChatMedia(
    String name,
    String fallbackPath,
    ChatMediaKind kind,
  ) {
    final extension = _chatMediaExtension(name, fallbackPath, kind);
    if (kind == ChatMediaKind.image) {
      switch (extension) {
        case '.jpg':
        case '.jpeg':
          return 'image/jpeg';
        case '.png':
          return 'image/png';
        case '.webp':
          return 'image/webp';
        case '.gif':
          return 'image/gif';
        case '.heic':
        case '.heif':
          return 'image/heic';
        default:
          return null;
      }
    }
    switch (extension) {
      case '.mp4':
      case '.m4v':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.webm':
        return 'video/webm';
      default:
        return null;
    }
  }

  Future<bool> toggleMessageReaction(
    String threadId,
    String messageId,
    String emoji,
  ) async {
    final cleanEmoji = emoji.trim();
    if (messageId.isEmpty ||
        cleanEmoji.isEmpty ||
        cleanEmoji.runes.length > 16) {
      return false;
    }

    final actorId = await _resolveChatActor();
    if (actorId == null) return false;
    final thread = threadById(threadId);
    if (thread == null || (_hasSupabase && !thread.containsUser(actorId))) {
      return false;
    }
    final messageIndex = thread.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (messageIndex == -1 || thread.messages[messageIndex].isDeleted) {
      return false;
    }

    final reactionActor = actorId.isEmpty ? 'local-user' : actorId;
    final originalMessage = thread.messages[messageIndex];
    final reactions = <String, List<String>>{
      for (final entry in originalMessage.reactions.entries)
        entry.key: List<String>.from(entry.value),
    };
    final users = reactions.putIfAbsent(cleanEmoji, () => <String>[]);
    if (users.contains(reactionActor)) {
      users.remove(reactionActor);
      if (users.isEmpty) reactions.remove(cleanEmoji);
    } else {
      users.add(reactionActor);
    }

    await _replaceLocalMessage(
      threadId,
      originalMessage.copyWith(reactions: reactions),
    );

    if (_hasSupabase) {
      try {
        await _client.rpc(
          'toggle_chat_message_reaction',
          params: {
            'p_thread_id': threadId,
            'p_message_id': messageId,
            'p_emoji': cleanEmoji,
          },
        );
      } catch (e) {
        debugPrint('Message reaction sync error: $e');
        await _replaceLocalMessage(threadId, originalMessage);
        return false;
      }
    }
    return true;
  }

  Future<bool> editMessage(
    String threadId,
    String messageId,
    String text,
  ) async {
    final trimmed = text.trim();
    if (messageId.isEmpty || trimmed.isEmpty) return false;

    final actorId = await _resolveChatActor();
    if (actorId == null) return false;
    final thread = threadById(threadId);
    if (thread == null) return false;
    final messageIndex = thread.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (messageIndex == -1) return false;
    final original = thread.messages[messageIndex];
    final canEdit = _hasSupabase
        ? original.senderId == actorId
        : original.isMine || original.senderId == actorId;
    if (!canEdit || original.isDeleted || original.type == 'system') {
      return false;
    }

    final editedAt = DateTime.now();
    final edited = original.copyWith(text: trimmed, editedAt: editedAt);
    await _replaceLocalMessage(threadId, edited, updateLastPreview: true);

    if (_hasSupabase) {
      try {
        await _client.rpc(
          'edit_chat_message',
          params: {
            'p_thread_id': threadId,
            'p_message_id': messageId,
            'p_text': trimmed,
          },
        );
      } catch (e) {
        debugPrint('Message edit sync error: $e');
        await _replaceLocalMessage(threadId, original, updateLastPreview: true);
        return false;
      }
    }
    return true;
  }

  Future<bool> deleteMessage(String threadId, String messageId) async {
    if (messageId.isEmpty) return false;
    final actorId = await _resolveChatActor();
    if (actorId == null) return false;
    final thread = threadById(threadId);
    if (thread == null) return false;
    final messageIndex = thread.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (messageIndex == -1) return false;
    final original = thread.messages[messageIndex];
    final canDelete = _hasSupabase
        ? original.senderId == actorId
        : original.isMine || original.senderId == actorId;
    if (!canDelete || original.isDeleted || original.type == 'system') {
      return false;
    }

    final deletedAt = DateTime.now();
    final deleted = original.copyWith(
      text: '',
      type: 'text',
      sharedProduct: null,
      attachment: null,
      deletedAt: deletedAt,
      reactions: const {},
      isPending: false,
      hasError: false,
    );
    await _replaceLocalMessage(threadId, deleted, updateLastPreview: true);

    if (_hasSupabase) {
      try {
        await _client.rpc(
          'delete_chat_message',
          params: {'p_thread_id': threadId, 'p_message_id': messageId},
        );
      } catch (e) {
        debugPrint('Message delete sync error: $e');
        await _replaceLocalMessage(threadId, original, updateLastPreview: true);
        return false;
      }
      final attachment = original.attachment;
      if (attachment?.hasRemoteObject == true) {
        await _removeRemoteChatMedia(
          attachment!.bucket,
          attachment.storagePath,
          logContext: 'Deleted chat media cleanup',
        );
      }
    }
    return true;
  }

  Future<bool> updateThreadPreferences(
    String threadId, {
    bool? isPinned,
    bool? isMuted,
    bool? isArchived,
    String? title,
  }) async {
    final actorId = await _resolveChatActor();
    if (actorId == null) return false;
    final thread = threadById(threadId);
    if (thread == null || (_hasSupabase && !thread.containsUser(actorId))) {
      return false;
    }
    final cleanTitle = title?.trim();
    if (_hasSupabase &&
        cleanTitle != null &&
        (!thread.isGroup || thread.createdBy != actorId)) {
      return false;
    }

    final updated = thread.copyWith(
      isPinned: isPinned,
      isMuted: isMuted,
      isArchived: isArchived,
      title: cleanTitle,
    );
    _upsertLocalThread(updated);
    notifyListeners();
    unawaited(
      _saveThreadsLocal().catchError((Object error) {
        debugPrint('Outgoing chat cache write error: $error');
      }),
    );

    if (_hasSupabase) {
      final params = <String, dynamic>{
        'p_thread_id': threadId,
        'p_is_pinned': ?isPinned,
        'p_is_muted': ?isMuted,
        'p_is_archived': ?isArchived,
        'p_title': ?cleanTitle,
      };
      if (params.length > 1) {
        try {
          await _client.rpc('update_chat_thread_settings', params: params);
        } catch (e) {
          debugPrint('Thread preferences sync error: $e');
          _upsertLocalThread(thread);
          await _saveThreadsLocal();
          notifyListeners();
          return false;
        }
      }
    }
    return true;
  }

  Future<void> saveThreadDraft(String threadId, String draft) async {
    final index = _threads.indexWhere((thread) => thread.id == threadId);
    if (index == -1) return;
    final thread = _threads[index];
    _threads[index] = thread.copyWith(draft: draft);
    await _saveThreadsLocal();
    notifyListeners();

    if (!_hasSupabase || currentUserId.isEmpty) return;
    try {
      await _client.rpc(
        'update_chat_thread_settings',
        params: {'p_thread_id': threadId, 'p_draft': draft},
      );
    } catch (e) {
      debugPrint('Thread draft sync error: $e');
    }
  }

  Future<void> markThreadRead(String threadId) async {
    final index = _threads.indexWhere((thread) => thread.id == threadId);
    if (index == -1) return;
    final actorId = _hasSupabase
        ? (_client.auth.currentUser?.id ?? currentUserId)
        : currentUserId;
    final readActor = actorId.isEmpty ? 'local-user' : actorId;
    final thread = _threads[index];
    final now = DateTime.now();
    final messages = thread.messages
        .map((message) {
          if (message.isMine || message.readBy.contains(readActor)) {
            return message;
          }
          return message.copyWith(readBy: [...message.readBy, readActor]);
        })
        .toList(growable: false);
    _threads[index] = thread.copyWith(
      unreadCount: 0,
      messages: messages,
      lastReadAt: now,
    );
    await _saveThreadsLocal();
    notifyListeners();

    if (!_hasSupabase || actorId.isEmpty) return;
    try {
      await _client.rpc(
        'mark_chat_thread_read',
        params: {'p_thread_id': threadId},
      );
    } catch (e) {
      debugPrint('Thread read state sync error: $e');
    }
  }

  Future<String?> _resolveChatActor({String? message}) async {
    if (!_hasSupabase) return currentUserId;
    final user = await _ensureAuthSession(message: message);
    return user?.id;
  }

  String _replySenderName(MessageThread thread, ChatMessage message) {
    if (message.senderName.trim().isNotEmpty) return message.senderName.trim();
    return message.isMine
        ? _profile.name
        : thread.otherPartyName(currentUserId);
  }

  Future<bool> _appendOutgoingMessage(
    MessageThread thread,
    ChatMessage message,
  ) async {
    final updated = thread.copyWith(
      lastMessage: message.previewText,
      updatedAt: message.createdAt,
      messages: [...thread.messages, message],
      draft: '',
    );
    _upsertLocalThread(updated);
    await _saveThreadsLocal();
    notifyListeners();

    final saved = await _upsertThread(updated, newMessages: [message]);
    if (_hasSupabase) {
      await _replaceLocalMessage(
        thread.id,
        message.copyWith(isPending: false, hasError: !saved),
      );
    }
    final latestThread = threadById(thread.id) ?? updated;
    if (saved) unawaited(_notifyMessageRecipient(latestThread, message));
    if (!saved) {
      _authError = 'Не удалось доставить сообщение. Проверьте интернет.';
      notifyListeners();
    }
    return saved;
  }

  Future<void> _replaceLocalMessage(
    String threadId,
    ChatMessage replacement, {
    bool updateLastPreview = false,
  }) async {
    final threadIndex = _threads.indexWhere((thread) => thread.id == threadId);
    if (threadIndex == -1) return;
    final thread = _threads[threadIndex];
    final messageIndex = thread.messages.indexWhere(
      (message) => message.id == replacement.id,
    );
    if (messageIndex == -1) return;
    final messages = List<ChatMessage>.from(thread.messages);
    messages[messageIndex] = replacement;
    final shouldUpdatePreview =
        updateLastPreview && messageIndex == messages.length - 1;
    _threads[threadIndex] = thread.copyWith(
      messages: messages,
      lastMessage: shouldUpdatePreview
          ? replacement.previewText
          : thread.lastMessage,
    );
    await _saveThreadsLocal();
    notifyListeners();
  }

  Future<void> _markLocalOutgoingMessageFailed(
    String threadId,
    ChatMessage message, {
    required String actorId,
  }) async {
    if (_hasSupabase && currentUserId != actorId) return;
    final threadIndex = _threads.indexWhere((thread) => thread.id == threadId);
    if (threadIndex == -1) return;
    final thread = _threads[threadIndex];
    if (_hasSupabase && !thread.containsUser(actorId)) return;

    final failed = message.copyWith(isPending: false, hasError: true);
    final messages = List<ChatMessage>.from(thread.messages);
    final messageIndex = messages.indexWhere((item) => item.id == failed.id);
    if (messageIndex == -1) {
      messages.add(failed);
    } else {
      messages[messageIndex] = failed;
    }
    final isLatest = messages.isNotEmpty && messages.last.id == failed.id;
    _threads[threadIndex] = thread.copyWith(
      messages: messages,
      lastMessage: isLatest ? failed.previewText : thread.lastMessage,
      updatedAt: isLatest ? failed.createdAt : thread.updatedAt,
    );
    _sortThreads();
    notifyListeners();
    try {
      await _saveThreadsLocal();
    } catch (e) {
      debugPrint('Failed chat message local save error: $e');
    }
  }

  Future<void> _notifyMessageRecipient(
    MessageThread thread,
    ChatMessage message,
  ) async {
    if (!_hasSupabase || currentUserId.isEmpty || message.id.isEmpty) return;
    try {
      await _client.functions.invoke(
        'send-message-push',
        body: {'thread_id': thread.id, 'message_id': message.id},
      );
    } catch (e) {
      debugPrint('Message push invoke error: $e');
    }
  }

  void _upsertLocalThread(MessageThread thread) {
    final index = _threads.indexWhere((item) => item.id == thread.id);
    if (index == -1) {
      _threads.insert(0, thread);
    } else {
      _threads[index] = thread;
    }
    _sortThreads();
  }

  Future<MessageThread?> _fetchThreadFromSupabase(String threadId) async {
    if (!_hasSupabase || currentUserId.isEmpty) return null;

    try {
      final response = await _client
          .from('message_threads')
          .select()
          .eq('id', threadId)
          .limit(1);
      final rows = response as List<dynamic>;
      if (rows.isEmpty) return null;
      final thread = MessageThread.fromSupabase(
        rows.first as Map<String, dynamic>,
        currentUserId: currentUserId,
      );
      _knownRemoteThreadIds.add(thread.id);
      var hydrated = await _hydrateThreadProfiles([thread]);
      hydrated = await _hydrateThreadMemberState(hydrated);
      hydrated = await _hydrateThreadMessages(hydrated);
      return hydrated.first;
    } catch (error, stackTrace) {
      debugPrint(
        'Thread fetch error (thread=$threadId): '
        '${_describeChatRemoteError(error)}',
      );
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<bool> _saveThreadOrShowError(
    MessageThread thread, {
    List<ChatMessage> newMessages = const [],
    bool ensureThreadFirst = false,
  }) async {
    final didSave = await _upsertThread(
      thread,
      newMessages: newMessages,
      ensureThreadFirst: ensureThreadFirst,
    );
    if (!didSave) {
      _authError = 'Не удалось доставить сообщение. Проверьте интернет.';
    }
    return didSave;
  }

  Future<void> _discardFailedThreadCreation(String threadId) async {
    _threads.removeWhere((thread) => thread.id == threadId);
    try {
      await _saveThreadsLocal();
    } catch (error, stackTrace) {
      debugPrint('Failed thread rollback cache error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    notifyListeners();
  }

  Future<bool> _upsertThread(
    MessageThread thread, {
    List<ChatMessage> newMessages = const [],
    bool ensureThreadFirst = false,
  }) async {
    if (!_hasSupabase) return true;

    final result = await _chatRemoteWriteCoordinator.persist(
      hasMessages: newMessages.isNotEmpty,
      threadKnownRemote: _knownRemoteThreadIds.contains(thread.id),
      ensureThreadFirst: ensureThreadFirst,
      ensureThread: () async {
        final payload = thread.toSupabaseJson()
          ..remove('messages')
          ..remove('is_pinned')
          ..remove('is_muted')
          ..remove('is_archived')
          ..remove('draft')
          ..remove('last_read_at')
          ..remove('unread_count');
        await _client
            .from('message_threads')
            .upsert(payload, onConflict: 'id', ignoreDuplicates: true);
      },
      persistMessages: () async {
        if (newMessages.isEmpty) return;
        await _client
            .from('chat_messages')
            .upsert(
              newMessages
                  .map(
                    (message) => {
                      ...message.toSupabaseJson(),
                      'thread_id': thread.id,
                    },
                  )
                  .toList(),
              onConflict: 'id',
              ignoreDuplicates: true,
            );
      },
    );
    if (result.threadConfirmed) {
      _knownRemoteThreadIds.add(thread.id);
    }
    if (result.succeeded) return true;

    final failure = result.failure!;
    final stage = switch (failure.stage) {
      ChatRemoteWriteStage.ensureThread => 'ensure thread',
      ChatRemoteWriteStage.persistMessages => 'persist messages',
    };
    debugPrint(
      'Chat remote write error ($stage, thread=${thread.id}): '
      '${_describeChatRemoteError(failure.error)}',
    );
    debugPrintStack(stackTrace: failure.stackTrace);
    return false;
  }

  String _describeChatRemoteError(Object error) {
    if (error is PostgrestException) {
      final details = error.details?.toString().trim() ?? '';
      final hint = error.hint?.toString().trim() ?? '';
      return [
        'code=${error.code}',
        error.message,
        if (details.isNotEmpty) 'details=$details',
        if (hint.isNotEmpty) 'hint=$hint',
      ].join(', ');
    }
    return error.toString();
  }

  String _messageThreadId({
    required String productId,
    required String buyerId,
    required String sellerId,
  }) {
    return 'product_${productId}_${buyerId}_$sellerId';
  }

  String _directThreadId(String firstUserId, String secondUserId) {
    final ids = [firstUserId, secondUserId]..sort();
    return 'direct_${ids.first}_${ids.last}';
  }

  String _currentAvatarUrl() {
    if (_profile.avatarUrl.trim().isNotEmpty) return _profile.avatarUrl.trim();
    if (!_hasSupabase) return '';
    final metadata = _client.auth.currentUser?.userMetadata ?? const {};
    final value = metadata['avatar_url'] ?? metadata['picture'] ?? '';
    return value.toString();
  }

  ConversationMember _currentConversationMember(String userId) {
    return ConversationMember(
      id: userId,
      name: _profile.name,
      handle: _profile.handle,
      avatarUrl: _currentAvatarUrl(),
    );
  }

  Future<User?> _ensureAuthSession({String? message}) async {
    final currentUser = _client.auth.currentUser;
    final session = _client.auth.currentSession;
    if (currentUser != null &&
        session != null &&
        !_sessionNeedsRefresh(session)) {
      if (_currentUser?.id != currentUser.id) _currentUser = currentUser;
      return currentUser;
    }
    if (currentUser != null && session != null) {
      final existingRefresh = _sessionRefreshInFlight;
      if (existingRefresh != null) return existingRefresh;

      final refresh = _refreshAuthSession();
      _sessionRefreshInFlight = refresh;
      try {
        return await refresh;
      } finally {
        if (identical(_sessionRefreshInFlight, refresh)) {
          _sessionRefreshInFlight = null;
        }
      }
    }
    if (message != null) {
      _authError = message;
      notifyListeners();
      return null;
    }
    _authError = 'Войдите в профиль перед публикацией';
    notifyListeners();
    return null;
  }

  bool _sessionNeedsRefresh(Session session) {
    final expiresAt = session.expiresAt;
    if (expiresAt == null) return false;
    final refreshAt = DateTime.fromMillisecondsSinceEpoch(
      expiresAt * 1000,
      isUtc: true,
    ).subtract(const Duration(seconds: 30));
    return !DateTime.now().toUtc().isBefore(refreshAt);
  }

  Future<User?> _refreshAuthSession() async {
    try {
      final response = await _client.auth.refreshSession();
      final refreshedUser = response.user ?? _client.auth.currentUser;
      if (refreshedUser == null) {
        _authError = 'Сессия истекла. Войдите снова.';
        notifyListeners();
        return null;
      }
      _currentUser = refreshedUser;
      _authError = null;
      return refreshedUser;
    } catch (error, stackTrace) {
      debugPrint('Auth session refresh error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (isTerminalAuthRefreshError(error)) {
        await _clearExpiredLocalSession();
        _authError = 'Сессия истекла. Войдите снова.';
      } else {
        _authError = 'Не удалось проверить сессию. Проверьте подключение.';
      }
      notifyListeners();
      return null;
    }
  }

  @visibleForTesting
  static bool isTerminalAuthRefreshError(Object error) {
    if (error is AuthSessionMissingException ||
        error is AuthInvalidJwtException) {
      return true;
    }
    if (error is AuthRetryableFetchException) return false;
    if (error is! AuthException) return false;
    final code = error.code?.trim().toLowerCase() ?? '';
    if (const {
      'bad_jwt',
      'invalid_jwt',
      'invalid_refresh_token',
      'refresh_token_not_found',
      'refresh_token_already_used',
      'session_not_found',
      'user_not_found',
      'user_banned',
    }.contains(code)) {
      return true;
    }
    return error.statusCode == '401' || error.statusCode == '403';
  }

  Future<void> _clearExpiredLocalSession() async {
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (error, stackTrace) {
      // GoTrue removes the local token before attempting the optional remote
      // invalidation. Keep the app state signed out even if that request fails.
      debugPrint('Expired local session cleanup error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    _currentUser = null;
    _knownRemoteThreadIds.clear();
    _chatMediaUrlCache.clear();
    _loadLocalUserState();
    _isThreadSyncPending = false;
    _threadSyncError = null;
  }

  // ─── Helpers ───

  String _scopedStorageKey(String baseKey, [String? userId]) {
    return userScopedStorageKey(baseKey, userId ?? currentUserId);
  }

  Future<void> _migrateLegacyUserStorage() async {
    if (_prefs.getBool(_scopedStorageMigrationKey) ?? false) return;
    for (final key in _scopedUserStorageKeys) {
      final value = _prefs.getString(key);
      if (value != null && !_prefs.containsKey(_scopedStorageKey(key))) {
        await _prefs.setString(_scopedStorageKey(key), value);
      }
      await _prefs.remove(key);
    }

    final favoriteProductsKey = _scopedStorageKey(_favoriteProductIdsKey);
    if (!_prefs.containsKey(favoriteProductsKey)) {
      await _writeStringList(
        favoriteProductsKey,
        _products.where((item) => item.isLiked).map((item) => item.id),
      );
    }
    final favoriteOutfitsKey = _scopedStorageKey(_favoriteOutfitIdsKey);
    if (!_prefs.containsKey(favoriteOutfitsKey)) {
      await _writeStringList(
        favoriteOutfitsKey,
        _outfits.where((item) => item.isLiked).map((item) => item.id),
      );
    }
    await _prefs.setBool(_scopedStorageMigrationKey, true);
  }

  Future<void> _clearScopedUserStorage(String userId) async {
    for (final key in _scopedUserStorageKeys) {
      await _prefs.remove(_scopedStorageKey(key, userId));
    }
    final checkoutSuffix = ':${userId.trim()}';
    final attemptKeys = _prefs
        .getKeys()
        .where(
          (key) =>
              key.startsWith('$_checkoutAttemptKeyPrefix:') &&
              key.endsWith(checkoutSuffix),
        )
        .toList(growable: false);
    for (final key in attemptKeys) {
      await _prefs.remove(key);
    }
  }

  void _loadLocalUserState() {
    _threads = _readList(
      _scopedStorageKey(_threadsKey),
      MessageThread.fromJson,
    );
    _notifications = _readList(
      _scopedStorageKey(_notificationsKey),
      ProfileNotification.fromJson,
    ).where((notification) => notification.kind != 'message').toList();
    _orders = _readList(_scopedStorageKey(_ordersKey), AppOrder.fromJson);
    _sellerReviews = _readList(
      _scopedStorageKey(_sellerReviewsKey),
      SellerReview.fromJson,
    );

    _notificationPreferences = const NotificationPreferences();
    final notificationPreferencesJson = _prefs.getString(
      _scopedStorageKey(_notificationPreferencesKey),
    );
    if (notificationPreferencesJson != null) {
      _notificationPreferences = NotificationPreferences.fromJson(
        jsonDecode(notificationPreferencesJson) as Map<String, dynamic>,
      );
    }

    _deliveryProfile = const DeliveryProfile();
    final deliveryProfileJson = _prefs.getString(
      _scopedStorageKey(_deliveryProfileKey),
    );
    if (deliveryProfileJson != null) {
      _deliveryProfile = DeliveryProfile.fromJson(
        jsonDecode(deliveryProfileJson) as Map<String, dynamic>,
      );
    }

    _favoriteProductIds = _readStringSet(
      _scopedStorageKey(_favoriteProductIdsKey),
    );
    _favoriteOutfitIds = _readStringSet(
      _scopedStorageKey(_favoriteOutfitIdsKey),
    );
    _followedSellerIds = _readStringSet(
      _scopedStorageKey(_followedSellerIdsKey),
    );
    _recentProductIds = _readStringList(
      _scopedStorageKey(_recentProductIdsKey),
    );
    _recentOutfitIds = _readStringList(_scopedStorageKey(_recentOutfitIdsKey));
    _applyProductFavoriteState();
    _applyOutfitFavoriteState();

    _profile = const AppProfile(
      name: 'Ваш профиль',
      handle: '@seller',
      city: 'Москва',
      rating: 0,
      salesCount: 0,
      followersCount: 0,
    );
    final profileJson = _prefs.getString(_scopedStorageKey(_profileKey));
    if (profileJson != null) {
      _profile = AppProfile.fromJson(
        jsonDecode(profileJson) as Map<String, dynamic>,
      );
    }
    _sortThreads();
  }

  List<T> _readList<T>(
    String key,
    T Function(Map<String, dynamic> json) fromJson,
  ) {
    final value = _prefs.getString(key);
    if (value == null) return [];
    final items = jsonDecode(value) as List<dynamic>;
    return items.map((item) => fromJson(item as Map<String, dynamic>)).toList();
  }

  List<String> _readStringList(String key) {
    final value = _prefs.getString(key);
    if (value == null) return [];
    final items = jsonDecode(value) as List<dynamic>;
    return items.whereType<String>().toList();
  }

  Set<String> _readStringSet(String key) => _readStringList(key).toSet();

  Future<void> _writeList(String key, Iterable<Map<String, dynamic>> items) {
    return _prefs.setString(key, jsonEncode(items.toList()));
  }

  Future<void> _writeStringList(String key, Iterable<String> items) {
    return _prefs.setString(key, jsonEncode(items.toList()));
  }

  Future<void> _saveStringSet(String key, Set<String> items) {
    return _writeStringList(key, items);
  }

  Future<void> _saveCollectionState() async {
    await Future.wait([
      _saveStringSet(
        _scopedStorageKey(_favoriteProductIdsKey),
        _favoriteProductIds,
      ),
      _saveStringSet(
        _scopedStorageKey(_favoriteOutfitIdsKey),
        _favoriteOutfitIds,
      ),
      _saveStringSet(
        _scopedStorageKey(_followedSellerIdsKey),
        _followedSellerIds,
      ),
      _writeStringList(
        _scopedStorageKey(_recentProductIdsKey),
        _recentProductIds,
      ),
      _writeStringList(
        _scopedStorageKey(_recentOutfitIdsKey),
        _recentOutfitIds,
      ),
    ]);
  }

  Future<void> _saveThreadsLocal() {
    return _writeList(
      _scopedStorageKey(_threadsKey),
      _threads.map((item) => item.toJson()),
    );
  }

  Future<void> _saveProducts() {
    return _writeList(_productsKey, _products.map((item) => item.toJson()));
  }

  Future<void> _saveNotificationsLocal() {
    return _writeList(
      _scopedStorageKey(_notificationsKey),
      _notifications.map((item) => item.toJson()),
    );
  }

  Future<void> _saveOrdersLocal() {
    return _writeList(
      _scopedStorageKey(_ordersKey),
      _orders.map((item) => item.toJson()),
    );
  }

  Future<void> _saveSellerReviewsLocal() {
    return _writeList(
      _scopedStorageKey(_sellerReviewsKey),
      _sellerReviews.map((item) => item.toJson()),
    );
  }

  Future<void> _saveNotificationPreferencesLocal() {
    return _prefs.setString(
      _scopedStorageKey(_notificationPreferencesKey),
      jsonEncode(_notificationPreferences.toJson()),
    );
  }

  Future<void> _saveDeliveryProfileLocal() {
    return _prefs.setString(
      _scopedStorageKey(_deliveryProfileKey),
      jsonEncode(_deliveryProfile.toJson()),
    );
  }

  Future<void> _saveAccessories() {
    return _writeList(
      _accessoriesKey,
      _accessories.map((item) => item.toJson()),
    );
  }

  void _sortThreads() {
    _threads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  void _applyProductFavoriteState() {
    _products = _products
        .map(
          (product) => product.copyWith(
            isLiked: _favoriteProductIds.contains(product.id),
          ),
        )
        .toList();
  }

  void _applyOutfitFavoriteState() {
    _outfits = _outfits
        .map(
          (outfit) =>
              outfit.copyWith(isLiked: _favoriteOutfitIds.contains(outfit.id)),
        )
        .toList();
  }

  List<String> _mergeRecentIds(List<String> remote, List<String> local) {
    final result = <String>[];
    for (final id in [...remote, ...local]) {
      if (id.isEmpty || result.contains(id)) continue;
      result.add(id);
      if (result.length == 24) break;
    }
    return result;
  }

  void _activateProductViewIdentity(String userId) {
    if (_countedProductViewsUserId == userId) return;
    _countedProductViewsUserId = userId;
    _countedProductViewIds = userId.isEmpty
        ? <String>{}
        : _readStringSet('${_countedProductViewsKeyPrefix}_$userId');
  }

  Future<void> _saveCountedProductViews() {
    final userId = _countedProductViewsUserId;
    if (userId.isEmpty) return Future<void>.value();
    return _saveStringSet(
      '${_countedProductViewsKeyPrefix}_$userId',
      _countedProductViewIds,
    );
  }

  void _activateOutfitViewIdentity(String userId) {
    if (_countedOutfitViewsUserId == userId) return;
    _countedOutfitViewsUserId = userId;
    _countedOutfitViewIds = userId.isEmpty
        ? <String>{}
        : _readStringSet('${_countedOutfitViewsKeyPrefix}_$userId');
  }

  Future<void> _saveCountedOutfitViews() {
    final userId = _countedOutfitViewsUserId;
    if (userId.isEmpty) return Future<void>.value();
    return _saveStringSet(
      '${_countedOutfitViewsKeyPrefix}_$userId',
      _countedOutfitViewIds,
    );
  }

  void _activateBlockedUserIdentity(String userId) {
    if (_blockedUsersUserId == userId) return;
    _blockedUsersUserId = userId;
    _blockedUserIds = userId.isEmpty
        ? <String>{}
        : _readStringSet('${_blockedUserIdsKeyPrefix}_$userId');
  }

  Future<void> _saveBlockedUsers() {
    final userId = _blockedUsersUserId;
    if (userId.isEmpty) return Future<void>.value();
    return _saveStringSet(
      '${_blockedUserIdsKeyPrefix}_$userId',
      _blockedUserIds,
    );
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _chatMediaUrlCache.clear();
    _chatThreadSync.dispose();
    _messageSubscriptionGeneration++;
    _authSubscription?.cancel();
    _pushTokenSubscription?.cancel();
    final messagesChannel = _messagesChannel;
    if (messagesChannel != null) unawaited(messagesChannel.unsubscribe());
    super.dispose();
  }
}
