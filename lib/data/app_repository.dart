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
  static const _bucketName = 'product-images';

  late final SharedPreferences _prefs;
  final _uuid = const Uuid();

  bool _isReady = false;
  List<Product> _products = [];
  List<OutfitAccessory> _accessories = [];
  List<CreatedOutfit> _outfits = [];
  List<MessageThread> _threads = [];
  Set<String> _favoriteProductIds = {};
  Set<String> _favoriteOutfitIds = {};
  List<String> _recentProductIds = [];
  List<String> _recentOutfitIds = [];
  User? _currentUser;
  bool _isSigningIn = false;
  String? _authError;
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
  User? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;
  bool get isSigningIn => _isSigningIn;
  String? get authError => _authError;
  String get currentUserId => _currentUser?.id ?? '';
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

  List<CreatedOutfit> get myOutfits {
    if (currentUserId.isEmpty) return [];
    return _outfits.where((outfit) => outfit.ownerId == currentUserId).toList();
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
      _syncThreadsFromSupabase();
      _syncTimer ??= Timer.periodic(const Duration(seconds: 4), (timer) {
        if (timer.tick % 3 == 0) {
          _syncFromSupabase();
          _syncAccessoriesFromSupabase();
          _syncOutfitsFromSupabase();
          _syncUserCollectionsFromSupabase();
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
      unawaited(_syncFromSupabase());
      unawaited(_syncAccessoriesFromSupabase());
      unawaited(_syncOutfitsFromSupabase());
      unawaited(_syncUserCollectionsFromSupabase());
      unawaited(_syncThreadsFromSupabase());
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
      debugPrint('Threads sync error: $e');
      // Optional table. Local chats remain fully usable without it.
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

  Future<MessageThread?> contactSeller(Product product) async {
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
    if (existing != null) return existing;
    final remoteExisting = await _fetchThreadFromSupabase(threadId);
    if (remoteExisting != null) {
      _upsertLocalThread(remoteExisting);
      await _writeList(_threadsKey, _threads.map((item) => item.toJson()));
      notifyListeners();
      return remoteExisting;
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
        productTitle: product.title,
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
    await _saveThreadOrShowError(threadById(threadId) ?? _threads.first);
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
    await _saveThreadOrShowError(
      _threads.firstWhere((thread) => thread.id == threadId),
    );
    notifyListeners();
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
    super.dispose();
  }
}
