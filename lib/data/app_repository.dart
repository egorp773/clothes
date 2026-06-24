import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../core/supabase_config.dart';
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
  static const _recentProductIdsKey = 'recent_product_ids_v1';
  static const _recentOutfitIdsKey = 'recent_outfit_ids_v1';
  static const _notificationsKey = 'profile_notifications_v1';
  static const _notificationPreferencesKey = 'notification_preferences_v1';
  static const _deliveryProfileKey = 'delivery_profile_v1';
  static const _ordersKey = 'orders_v1';
  static const _sellerReviewsKey = 'seller_reviews_v1';
  static const _bucketName = 'product-images';

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
  List<String> _recentProductIds = [];
  List<String> _recentOutfitIds = [];
  User? _currentUser;
  bool _isSigningIn = false;
  String? _authError;
  MessageNotification? _latestMessageNotification;
  NotificationPreferences _notificationPreferences =
      const NotificationPreferences();
  DeliveryProfile _deliveryProfile = const DeliveryProfile();
  bool _hasCompletedThreadSync = false;
  final Map<String, DateTime> _lastSeenByUserId = {};
  AppProfile _profile = const AppProfile(
    name: 'Ваш профиль',
    handle: '@seller',
    city: 'Москва',
    rating: 4.8,
    salesCount: 0,
    followersCount: 0,
  );
  Timer? _syncTimer;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<String>? _pushTokenSubscription;
  String? _registeredPushToken;

  bool get isReady => _isReady;
  List<Product> get products => List.unmodifiable(_products);
  List<Product> get likedProducts {
    return List.unmodifiable(
      _products
          .where(
            (product) =>
                _favoriteProductIds.contains(product.id) && !product.isHidden,
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
          .where((product) => !product.isHidden)
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

  List<CreatedOutfit> get outfits => List.unmodifiable(_outfits);
  List<CreatedOutfit> get likedOutfits {
    return List.unmodifiable(
      _outfits
          .where((outfit) => _favoriteOutfitIds.contains(outfit.id))
          .toList(),
    );
  }

  List<CreatedOutfit> get recentlyViewedOutfits {
    final outfitsById = {for (final outfit in _outfits) outfit.id: outfit};
    return List.unmodifiable(
      _recentOutfitIds
          .map((id) => outfitsById[id])
          .whereType<CreatedOutfit>()
          .toList(),
    );
  }

  List<MessageThread> get threads {
    if (!_hasSupabase || currentUserId.isEmpty) {
      return List.unmodifiable(_threads);
    }
    return List.unmodifiable(
      _threads.where(
        (thread) =>
            thread.buyerId == currentUserId || thread.sellerId == currentUserId,
      ),
    );
  }

  AppProfile get profile => _profile;
  List<ProfileNotification> get notifications =>
      List.unmodifiable(_notifications);
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
  String get currentUserId => _currentUser?.id ?? '';
  DateTime? lastSeenForUser(String userId) => _lastSeenByUserId[userId];

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
          thread.buyerId != currentUserId &&
          thread.sellerId != currentUserId) {
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
    if (sellerId.isEmpty) return const [];
    return _products.where((product) => product.ownerId == sellerId).toList();
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
      final remoteProducts = (response as List<dynamic>)
          .map((item) => Product.fromSupabase(item as Map<String, dynamic>))
          .toList();
      if (remoteProducts.isEmpty) return localProducts;

      final remoteIds = remoteProducts.map((product) => product.id).toSet();
      _products = [
        ...remoteProducts,
        ..._products.where(
          (product) =>
              product.ownerId != sellerId || !remoteIds.contains(product.id),
        ),
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
        final remote = (response as List<dynamic>)
            .map((item) => SellerReview.fromJson(item as Map<String, dynamic>))
            .toList();
        final remoteIds = remote.map((review) => review.id).toSet();
        _sellerReviews
          ..removeWhere(
            (review) =>
                review.sellerId == sellerId && remoteIds.contains(review.id),
          )
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
    final user = _hasSupabase
        ? await _ensureAuthSession(
            message: 'Войдите в профиль, чтобы оставить отзыв',
          )
        : null;
    if (_hasSupabase && user == null) return;
    final buyerId = user?.id ?? currentUserId;
    if (sellerId.isEmpty || buyerId.isEmpty || sellerId == buyerId) return;

    final review = SellerReview(
      id: _uuid.v4(),
      sellerId: sellerId,
      buyerId: buyerId,
      buyerName: _profile.name,
      buyerAvatar: _currentAvatarUrl(),
      productId: productId,
      productTitle: productTitle,
      productImage: productImage,
      rating: rating.clamp(1, 5),
      text: text.trim(),
      hasPhoto: hasPhoto,
      createdAt: DateTime.now(),
    );
    _sellerReviews.removeWhere((item) => item.id == review.id);
    _sellerReviews.insert(0, review);
    await _saveSellerReviewsLocal();
    await _recalculateSellerRating(sellerId);
    notifyListeners();

    if (!_hasSupabase) return;
    try {
      await _client.from('seller_reviews').insert(review.toSupabaseJson());
      await _pushSellerRatingToSupabase(sellerId);
    } catch (e) {
      debugPrint('Seller review save error: $e');
    }
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
    final rating = _profile.rating <= 0 ? 5.0 : _profile.rating;
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

    // Load from local cache first for instant UI
    _products = _readList(_productsKey, Product.fromJson);
    _accessories = _readList(_accessoriesKey, OutfitAccessory.fromJson);
    _outfits = _readList(_outfitsKey, CreatedOutfit.fromJson);
    _threads = _readList(_threadsKey, MessageThread.fromJson);
    _notifications = _readList(_notificationsKey, ProfileNotification.fromJson);
    _orders = _readList(_ordersKey, AppOrder.fromJson);
    _sellerReviews = _readList(_sellerReviewsKey, SellerReview.fromJson);
    final notificationPreferencesJson = _prefs.getString(
      _notificationPreferencesKey,
    );
    if (notificationPreferencesJson != null) {
      _notificationPreferences = NotificationPreferences.fromJson(
        jsonDecode(notificationPreferencesJson) as Map<String, dynamic>,
      );
    }
    final deliveryProfileJson = _prefs.getString(_deliveryProfileKey);
    if (deliveryProfileJson != null) {
      _deliveryProfile = DeliveryProfile.fromJson(
        jsonDecode(deliveryProfileJson) as Map<String, dynamic>,
      );
    }
    _favoriteProductIds = _readStringSet(_favoriteProductIdsKey);
    if (_favoriteProductIds.isEmpty) {
      _favoriteProductIds = _products
          .where((product) => product.isLiked)
          .map((product) => product.id)
          .toSet();
    }
    _favoriteOutfitIds = _readStringSet(_favoriteOutfitIdsKey);
    if (_favoriteOutfitIds.isEmpty) {
      _favoriteOutfitIds = _outfits
          .where((outfit) => outfit.isLiked)
          .map((outfit) => outfit.id)
          .toSet();
    }
    _recentProductIds = _readStringList(_recentProductIdsKey);
    _recentOutfitIds = _readStringList(_recentOutfitIdsKey);
    _applyProductFavoriteState();
    _applyOutfitFavoriteState();
    final profileJson = _prefs.getString(_profileKey);
    if (profileJson != null) {
      _profile = AppProfile.fromJson(
        jsonDecode(profileJson) as Map<String, dynamic>,
      );
    }
    if (_hasSupabase) {
      _currentUser = _client.auth.currentUser;
      await _applyUserProfile(_currentUser, notify: false);
      if (_currentUser != null) {
        unawaited(_registerPushToken(_currentUser!.id));
      }
      _authSubscription = _client.auth.onAuthStateChange.listen((state) {
        unawaited(_handleAuthState(state.session?.user));
      });
    }

    _sortThreads();
    _isReady = true;
    notifyListeners();

    if (_hasSupabase) {
      // Then sync from Supabase in background.
      _syncFromSupabase();
      _syncAccessoriesFromSupabase();
      _syncOutfitsFromSupabase();
      _syncUserCollectionsFromSupabase();
      _syncProfileFeaturesFromSupabase();
      _updatePresence();
      _syncThreadsFromSupabase();
      _syncTimer ??= Timer.periodic(const Duration(seconds: 4), (timer) {
        if (timer.tick % 3 == 0) {
          _syncFromSupabase();
          _syncAccessoriesFromSupabase();
          _syncOutfitsFromSupabase();
          _syncUserCollectionsFromSupabase();
          _syncProfileFeaturesFromSupabase();
          _updatePresence();
        }
        _syncThreadsFromSupabase();
      });
    }
  }

  Future<void> signInWithYandex() async {
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
      SupabaseConfig.yandexAuthUrl,
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
        _authError = 'Не удалось открыть вход через Яндекс ID';
      }
    } catch (e) {
      _authError = 'Не удалось начать вход через Яндекс ID: $e';
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  Future<void> signInWithVk() async {
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
      SupabaseConfig.vkAuthUrl,
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
        _authError = 'Не удалось открыть вход через VK ID';
      }
    } catch (e) {
      _authError = 'Не удалось начать вход через VK ID: $e';
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
    await _client.auth.signOut();
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
    await _prefs.setString(_profileKey, jsonEncode(_profile.toJson()));
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

  Future<void> _handleAuthState(User? user) async {
    _currentUser = user;
    _authError = null;
    await _applyUserProfile(user, notify: false);
    if (user != null) {
      unawaited(_registerPushToken(user.id));
      unawaited(_updatePresence());
      unawaited(_syncFromSupabase());
      unawaited(_syncAccessoriesFromSupabase());
      unawaited(_syncOutfitsFromSupabase());
      unawaited(_syncUserCollectionsFromSupabase());
      unawaited(_syncProfileFeaturesFromSupabase());
      unawaited(_syncThreadsFromSupabase());
    } else {
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
        _profile = AppProfile(
          name: row['name'] as String? ?? _profile.name,
          handle: row['handle'] as String? ?? _profile.handle,
          city: row['city'] as String? ?? _profile.city,
          rating: (row['rating'] as num?)?.toDouble() ?? _profile.rating,
          salesCount:
              (row['sales_count'] as num?)?.toInt() ?? _profile.salesCount,
          followersCount:
              (row['followers_count'] as num?)?.toInt() ??
              _profile.followersCount,
        );
        await _prefs.setString(_profileKey, jsonEncode(_profile.toJson()));
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
      _profile = AppProfile(
        name: name,
        handle: handle,
        city: _profile.city,
        rating: _profile.rating,
        salesCount: _profile.salesCount,
        followersCount: _profile.followersCount,
      );
      await _prefs.setString(_profileKey, jsonEncode(_profile.toJson()));
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
      'rating': profile.rating,
      'sales_count': profile.salesCount,
      'followers_count': profile.followersCount,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'id');
  }

  Future<void> _registerPushToken(String userId) async {
    if (!_notificationPreferences.pushEnabled ||
        !_hasSupabase ||
        userId.isEmpty ||
        !PushNotificationService.isEnabled) {
      return;
    }

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
        'updated_at': DateTime.now().toIso8601String(),
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
    await PushNotificationService.deleteToken();
  }

  Future<void> _updatePresence() async {
    if (!_hasSupabase || currentUserId.isEmpty) return;
    final now = DateTime.now();
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
        .map((thread) => thread.otherPartyId(currentUserId))
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
  }

  Future<void> _syncFromSupabase() async {
    if (!_hasSupabase) return;
    try {
      final response = await _client
          .from('products')
          .select()
          .order('created_at', ascending: false);

      final fetched = (response as List<dynamic>)
          .map((e) => Product.fromSupabase(e))
          .toList();

      if (fetched.isNotEmpty) {
        final merged = <String, Product>{
          for (final product in fetched) product.id: product,
        };
        for (final product in _products) {
          merged.putIfAbsent(product.id, () => product);
        }
        _products = merged.values.toList();
        _applyProductFavoriteState();
        await _saveProducts();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Supabase sync error: $e');
    }
  }

  Future<void> _syncThreadsFromSupabase() async {
    if (!_hasSupabase || currentUserId.isEmpty) return;

    try {
      final previousById = {for (final thread in _threads) thread.id: thread};
      final response = await _client
          .from('message_threads')
          .select()
          .or('buyer_id.eq.$currentUserId,seller_id.eq.$currentUserId')
          .order('updated_at', ascending: false);

      final fetched = (response as List<dynamic>)
          .map(
            (item) => MessageThread.fromSupabase(
              item as Map<String, dynamic>,
              currentUserId: currentUserId,
            ),
          )
          .toList();

      await _syncThreadPresence(fetched);

      if (_hasCompletedThreadSync) {
        final notification = _incomingNotification(fetched, previousById);
        if (notification != null) {
          _latestMessageNotification = notification;
          await _addProfileNotification(
            title: notification.senderName,
            body: notification.text,
            kind: 'message',
            targetId: notification.threadId,
          );
        }
      }
      _hasCompletedThreadSync = true;

      if (fetched.isEmpty) return;
      final merged = <String, MessageThread>{
        for (final thread in fetched) thread.id: thread,
      };
      for (final thread in _threads) {
        merged.putIfAbsent(thread.id, () => thread);
      }
      _threads = merged.values.toList();
      _sortThreads();
      await _writeList(_threadsKey, _threads.map((item) => item.toJson()));
      notifyListeners();
    } catch (e) {
      _hasCompletedThreadSync = true;
      debugPrint('Threads sync error: $e');
      // Optional table. Local chats remain fully usable without it.
    }
  }

  MessageNotification? _incomingNotification(
    List<MessageThread> fetched,
    Map<String, MessageThread> previousById,
  ) {
    ChatMessage? newestMessage;
    MessageThread? newestThread;

    for (final thread in fetched) {
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
      text: newestMessage.text,
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

    try {
      final orders = await _client
          .from('orders')
          .select()
          .or('buyer_id.eq.$currentUserId,seller_id.eq.$currentUserId')
          .order('updated_at', ascending: false);
      _orders = (orders as List<dynamic>)
          .map((item) => AppOrder.fromJson(item as Map<String, dynamic>))
          .toList();
      await _saveOrdersLocal();
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
            preferences.toSupabaseJson(currentUserId),
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

  Future<void> createDeliveryOrder(
    Product product, {
    String deliveryService = 'Почта России',
    int deliveryPrice = 122,
  }) async {
    final user = _hasSupabase
        ? await _ensureAuthSession(message: 'Войдите в профиль, чтобы купить')
        : null;
    if (_hasSupabase && user == null) return;

    final buyerId = user?.id ?? currentUserId;
    if (buyerId.isEmpty) {
      _authError = 'Войдите в профиль, чтобы купить';
      notifyListeners();
      return;
    }
    if (product.ownerId.isNotEmpty && product.ownerId == buyerId) {
      _authError = 'Это ваше объявление';
      notifyListeners();
      return;
    }

    final order = AppOrder.fromProduct(
      product: product,
      buyerId: buyerId,
      status: AppOrderStatus.pendingConfirmation,
      deliveryProfile: deliveryProfile,
      deliveryService: deliveryService,
      deliveryPrice: deliveryPrice,
    );
    _orders.removeWhere((item) => item.id == order.id);
    _orders.insert(0, order);
    await _saveOrdersLocal();
    await _addProfileNotification(
      title: 'Заказ создан',
      body: product.title,
      kind: 'order',
      targetId: order.id,
    );
    notifyListeners();

    if (!_hasSupabase) return;
    try {
      await _client.from('orders').insert(order.toSupabaseJson());
    } catch (e) {
      debugPrint('Order create error: $e');
    }
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
    if (!changed) return;
    await _saveNotificationsLocal();
    notifyListeners();

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
      createdAt: DateTime.now(),
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

      if (fetched.isEmpty) return;
      final merged = <String, CreatedOutfit>{
        for (final outfit in fetched) outfit.id: outfit,
      };
      for (final outfit in _outfits) {
        merged.putIfAbsent(outfit.id, () => outfit);
      }
      _outfits = merged.values.toList();
      _applyOutfitFavoriteState();
      await _writeList(_outfitsKey, _outfits.map((item) => item.toJson()));
      notifyListeners();
    } catch (e) {
      debugPrint('Outfits sync error: $e');
    }
  }

  // ─── Image Upload ───

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
      final recentProducts = await _client
          .from('recent_products')
          .select('product_id')
          .eq('user_id', currentUserId)
          .order('viewed_at', ascending: false)
          .limit(24);
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

      _favoriteProductIds = {
        ..._favoriteProductIds,
        ...remoteFavoriteProductIds,
      };
      _favoriteOutfitIds = {..._favoriteOutfitIds, ...remoteFavoriteOutfitIds};
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
      if (_recentOutfitIds.isNotEmpty) {
        await _client
            .from('recent_outfits')
            .upsert(
              _recentOutfitIds
                  .asMap()
                  .entries
                  .map(
                    (entry) => {
                      'user_id': currentUserId,
                      'outfit_id': entry.value,
                      'viewed_at': DateTime.now()
                          .subtract(Duration(milliseconds: entry.key))
                          .toIso8601String(),
                    },
                  )
                  .toList(),
              onConflict: 'user_id,outfit_id',
            );
      }
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
      try {
        final bytes = await imageFile.readAsBytes();
        final mimeType = _mimeTypeForImage(imageFile.name, imageFile.path);
        return 'data:$mimeType;base64,${base64Encode(bytes)}';
      } catch (fallbackError) {
        debugPrint('Inline image fallback error: $fallbackError');
        return null;
      }
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
      );
      final data = ownedProduct.toSupabaseJson(sellerId: user.id);
      await _client.from('products').insert(data);
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

  void _queueBackgroundRemoval(Product product) {
    if (!_hasSupabase || product.image.isEmpty) return;

    unawaited(
      _client.functions
          .invoke(
            'process-product-image',
            body: {'product_id': product.id, 'image_url': product.image},
          )
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
      scope: isDefault ? 'default' : 'private',
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
        folder: isDefault ? 'accessories/default' : 'accessories/${user!.id}',
      );
      if (imageUrl == null) return fallback;

      final accessory = fallback.copyWith(
        image: imageUrl,
        ownerId: isDefault ? '' : user!.id,
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
            body: {'accessory_id': accessory.id, 'image_url': accessory.image},
          )
          .then((_) => _syncAccessoriesFromSupabase())
          .catchError((e) {
            debugPrint('Accessory background queue error: $e');
          }),
    );
  }

  Future<void> toggleProductLike(String productId) async {
    final willLike = !_favoriteProductIds.contains(productId);
    if (willLike) {
      _favoriteProductIds.add(productId);
    } else {
      _favoriteProductIds.remove(productId);
    }
    _applyProductFavoriteState();
    await _saveStringSet(_favoriteProductIdsKey, _favoriteProductIds);
    await _saveProducts();
    notifyListeners();

    if (!_hasSupabase || currentUserId.isEmpty) return;
    try {
      if (willLike) {
        await _client.from('product_favorites').upsert({
          'user_id': currentUserId,
          'product_id': productId,
          'created_at': DateTime.now().toIso8601String(),
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
    }
  }

  Future<void> toggleOutfitLike(String outfitId) async {
    final willLike = !_favoriteOutfitIds.contains(outfitId);
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
    await _saveStringSet(_favoriteOutfitIdsKey, _favoriteOutfitIds);
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
    }
  }

  Future<void> recordProductView(String productId) async {
    if (productId.isEmpty) return;
    _recentProductIds.remove(productId);
    _recentProductIds.insert(0, productId);
    if (_recentProductIds.length > 24) {
      _recentProductIds.removeRange(24, _recentProductIds.length);
    }
    await _writeStringList(_recentProductIdsKey, _recentProductIds);
    notifyListeners();

    if (!_hasSupabase || currentUserId.isEmpty) return;
    try {
      await _client.from('recent_products').upsert({
        'user_id': currentUserId,
        'product_id': productId,
        'viewed_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,product_id');
    } catch (e) {
      debugPrint('Recent product sync error: $e');
    }
  }

  Future<void> recordOutfitView(String outfitId) async {
    if (outfitId.isEmpty) return;
    _recentOutfitIds.remove(outfitId);
    _recentOutfitIds.insert(0, outfitId);
    if (_recentOutfitIds.length > 24) {
      _recentOutfitIds.removeRange(24, _recentOutfitIds.length);
    }
    await _writeStringList(_recentOutfitIdsKey, _recentOutfitIds);
    notifyListeners();

    if (!_hasSupabase || currentUserId.isEmpty) return;
    try {
      await _client.from('recent_outfits').upsert({
        'user_id': currentUserId,
        'outfit_id': outfitId,
        'viewed_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,outfit_id');
    } catch (e) {
      debugPrint('Recent outfit sync error: $e');
    }
  }

  Future<void> hideProduct(String productId) async {
    final product = _products.firstWhere((item) => item.id == productId);
    product.isHidden = true;
    await _saveProducts();
    notifyListeners();
  }

  Future<void> deleteProduct(String productId) async {
    _products.removeWhere((item) => item.id == productId);
    _favoriteProductIds.remove(productId);
    _recentProductIds.remove(productId);
    await _saveProducts();
    await _saveStringSet(_favoriteProductIdsKey, _favoriteProductIds);
    await _writeStringList(_recentProductIdsKey, _recentProductIds);
    notifyListeners();

    if (!_hasSupabase) return;
    try {
      await _client.from('products').delete().eq('id', productId);
    } catch (e) {
      debugPrint('Product delete error: $e');
    }
  }

  // ─── Outfits ───

  Future<void> publishOutfit(CreatedOutfit outfit) async {
    final user = _hasSupabase ? await _ensureAuthSession() : null;
    if (_hasSupabase && user == null) return;

    final ownedOutfit = outfit.copyWith(
      ownerId: user?.id ?? currentUserId,
      authorName: _profile.name,
      authorHandle: _profile.handle,
    );

    _outfits.insert(0, ownedOutfit);
    await _writeList(_outfitsKey, _outfits.map((item) => item.toJson()));
    notifyListeners();

    if (!_hasSupabase) return;

    try {
      await _client.from('outfits').insert({
        'id': ownedOutfit.id,
        'owner_id': ownedOutfit.ownerId,
        'author_name': ownedOutfit.authorName,
        'author_handle': ownedOutfit.authorHandle,
        'photos': ownedOutfit.photos,
        'items': ownedOutfit.items.map((i) => i.toJson()).toList(),
        'preview_layout': {
          'backgroundColor': ownedOutfit.previewBackgroundColor,
          'items': ownedOutfit.layoutItems.map((i) => i.toJson()).toList(),
        },
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Outfit publish error: $e');
    }
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
      await _writeList(_threadsKey, _threads.map((item) => item.toJson()));
      await _saveThreadOrShowError(updated);
      notifyListeners();
      return updated;
    }
    final remoteExisting = await _fetchThreadFromSupabase(threadId);
    if (remoteExisting != null) {
      final thread = imageOnly
          ? remoteExisting.copyWith(
              productTitle: '',
              productImage: product.image,
            )
          : remoteExisting;
      _upsertLocalThread(thread);
      await _writeList(_threadsKey, _threads.map((item) => item.toJson()));
      if (imageOnly) {
        await _saveThreadOrShowError(thread);
      }
      notifyListeners();
      return thread;
    }

    final now = DateTime.now();
    final sellerName = product.sellerName.trim().isEmpty
        ? 'Продавец'
        : product.sellerName;
    const firstMessage = 'Здравствуйте! Вещь ещё доступна?';
    _threads.removeWhere((thread) => thread.id == threadId);
    _threads.insert(
      0,
      MessageThread(
        id: threadId,
        sellerName: sellerName,
        buyerName: _profile.name,
        sellerHandle: product.sellerHandle,
        buyerHandle: _profile.handle,
        buyerAvatar: _currentAvatarUrl(),
        productTitle: imageOnly ? '' : product.title,
        lastMessage: firstMessage,
        updatedAt: now,
        productId: product.id,
        productImage: product.image,
        buyerId: buyerId,
        sellerId: sellerId,
        unreadCount: 0,
        messages: [
          ChatMessage(
            id: _uuid.v4(),
            text: firstMessage,
            createdAt: now,
            isMine: true,
            senderId: buyerId,
            senderName: _profile.name,
          ),
        ],
      ),
    );
    _sortThreads();
    await _writeList(_threadsKey, _threads.map((item) => item.toJson()));
    final createdThread = threadById(threadId) ?? _threads.first;
    await _saveThreadOrShowError(createdThread);
    unawaited(
      _notifyMessageRecipient(createdThread, createdThread.messages.last),
    );
    notifyListeners();
    return _threads.firstWhere((thread) => thread.id == threadId);
  }

  Future<List<AppUserProfile>> searchUserProfiles(String query) async {
    final normalized = _normalizeHandle(query);
    final plainQuery = query.trim().replaceAll('@', '');
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

    final remoteExisting = await _fetchThreadFromSupabase(threadId);
    if (remoteExisting != null) {
      _upsertLocalThread(remoteExisting);
      await _writeList(_threadsKey, _threads.map((item) => item.toJson()));
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
      messages: const [],
    );

    _threads.removeWhere((item) => item.id == threadId);
    _threads.insert(0, thread);
    _sortThreads();
    await _writeList(_threadsKey, _threads.map((item) => item.toJson()));
    await _saveThreadOrShowError(thread);
    notifyListeners();
    return thread;
  }

  Future<void> sendMessage(String threadId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final user = _hasSupabase
        ? await _ensureAuthSession(
            message: 'Войдите в профиль, чтобы отправить сообщение',
          )
        : null;
    if (_hasSupabase && user == null) return;

    if (_hasSupabase) {
      final remoteThread = await _fetchThreadFromSupabase(threadId);
      if (remoteThread != null) {
        _upsertLocalThread(remoteThread);
      }
    }

    final index = _threads.indexWhere((thread) => thread.id == threadId);
    if (index == -1) return;

    final now = DateTime.now();
    final thread = _threads[index];
    final senderId = user?.id ?? currentUserId;
    if (_hasSupabase &&
        senderId != thread.buyerId &&
        senderId != thread.sellerId) {
      return;
    }

    final message = ChatMessage(
      id: _uuid.v4(),
      text: trimmed,
      createdAt: now,
      isMine: true,
      senderId: senderId,
      senderName: _profile.name,
    );

    _threads[index] = thread.copyWith(
      lastMessage: trimmed,
      updatedAt: now,
      messages: [...thread.messages, message],
    );
    _sortThreads();
    await _writeList(_threadsKey, _threads.map((item) => item.toJson()));
    final updatedThread = _threads.firstWhere(
      (thread) => thread.id == threadId,
    );
    await _saveThreadOrShowError(updatedThread);
    unawaited(_notifyMessageRecipient(updatedThread, message));
    notifyListeners();
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
      return MessageThread.fromSupabase(
        rows.first as Map<String, dynamic>,
        currentUserId: currentUserId,
      );
    } catch (e) {
      debugPrint('Thread fetch error: $e');
      return null;
    }
  }

  Future<void> _saveThreadOrShowError(MessageThread thread) async {
    final didSave = await _upsertThread(thread);
    if (didSave) return;
    _authError = 'Не удалось доставить сообщение. Проверьте интернет.';
  }

  Future<bool> _upsertThread(MessageThread thread) async {
    if (!_hasSupabase) return true;

    try {
      await _client
          .from('message_threads')
          .upsert(thread.toSupabaseJson(), onConflict: 'id');
      return true;
    } catch (e) {
      debugPrint('Thread upsert error: $e');
      return false;
    }
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
    final metadata = _client.auth.currentUser?.userMetadata ?? const {};
    final value = metadata['avatar_url'] ?? metadata['picture'] ?? '';
    return value.toString();
  }

  Future<User?> _ensureAuthSession({String? message}) async {
    final currentUser = _client.auth.currentUser;
    if (currentUser != null) return currentUser;
    if (message != null) {
      _authError = message;
      notifyListeners();
      return null;
    }
    _authError = 'Войдите в профиль перед публикацией';
    notifyListeners();
    return null;
  }

  // ─── Helpers ───

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
      _saveStringSet(_favoriteProductIdsKey, _favoriteProductIds),
      _saveStringSet(_favoriteOutfitIdsKey, _favoriteOutfitIds),
      _writeStringList(_recentProductIdsKey, _recentProductIds),
      _writeStringList(_recentOutfitIdsKey, _recentOutfitIds),
    ]);
  }

  Future<void> _saveProducts() {
    return _writeList(_productsKey, _products.map((item) => item.toJson()));
  }

  Future<void> _saveNotificationsLocal() {
    return _writeList(
      _notificationsKey,
      _notifications.map((item) => item.toJson()),
    );
  }

  Future<void> _saveOrdersLocal() {
    return _writeList(_ordersKey, _orders.map((item) => item.toJson()));
  }

  Future<void> _saveSellerReviewsLocal() {
    return _writeList(
      _sellerReviewsKey,
      _sellerReviews.map((item) => item.toJson()),
    );
  }

  Future<void> _saveNotificationPreferencesLocal() {
    return _prefs.setString(
      _notificationPreferencesKey,
      jsonEncode(_notificationPreferences.toJson()),
    );
  }

  Future<void> _recalculateSellerRating(String sellerId) async {
    final reviews = _sellerReviews
        .where((review) => review.sellerId == sellerId)
        .toList();
    if (reviews.isEmpty) return;
    final rating =
        reviews.fold<int>(0, (sum, review) => sum + review.rating) /
        reviews.length;
    if (sellerId == currentUserId) {
      _profile = _profile.copyWith(rating: rating, salesCount: reviews.length);
      await _prefs.setString(_profileKey, jsonEncode(_profile.toJson()));
    }
  }

  Future<void> _pushSellerRatingToSupabase(String sellerId) async {
    if (!_hasSupabase || sellerId.isEmpty) return;
    final reviews = _sellerReviews
        .where((review) => review.sellerId == sellerId)
        .toList();
    if (reviews.isEmpty) return;
    final rating =
        reviews.fold<int>(0, (sum, review) => sum + review.rating) /
        reviews.length;
    try {
      await _client
          .from('profiles')
          .update({
            'rating': rating,
            'sales_count': reviews.length,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', sellerId);
    } catch (e) {
      debugPrint('Seller rating update error: $e');
    }
  }

  Future<void> _saveDeliveryProfileLocal() {
    return _prefs.setString(
      _deliveryProfileKey,
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

  @override
  void dispose() {
    _syncTimer?.cancel();
    _authSubscription?.cancel();
    _pushTokenSubscription?.cancel();
    super.dispose();
  }
}
