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
import '../models/product.dart';

class AppRepository extends ChangeNotifier {
  static const _productsKey = 'products_v4';
  static const _outfitsKey = 'outfits_v2';
  static const _threadsKey = 'threads_v2';
  static const _profileKey = 'profile_v1';
  static const _bucketName = 'product-images';

  late final SharedPreferences _prefs;
  final _uuid = const Uuid();

  bool _isReady = false;
  List<Product> _products = [];
  List<CreatedOutfit> _outfits = [];
  List<MessageThread> _threads = [];
  User? _currentUser;
  bool _isSigningIn = false;
  String? _authError;
  AppProfile _profile = const AppProfile(
    name: 'Ваш профиль',
    handle: '@seller',
    city: 'Москва',
    rating: 4.8,
    salesCount: 0,
  );
  Timer? _syncTimer;
  StreamSubscription<AuthState>? _authSubscription;

  bool get isReady => _isReady;
  List<Product> get products => List.unmodifiable(_products);
  List<CreatedOutfit> get outfits => List.unmodifiable(_outfits);
  List<MessageThread> get threads => List.unmodifiable(_threads);
  AppProfile get profile => _profile;
  User? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;
  bool get isSigningIn => _isSigningIn;
  String? get authError => _authError;
  String get currentUserId => _currentUser?.id ?? '';
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
    _outfits = _readList(_outfitsKey, CreatedOutfit.fromJson);
    _threads = _readList(_threadsKey, MessageThread.fromJson);
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
      _syncOutfitsFromSupabase();
      _syncThreadsFromSupabase();
      _syncTimer ??= Timer.periodic(const Duration(seconds: 12), (_) {
        _syncFromSupabase();
        _syncOutfitsFromSupabase();
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

    try {
      final didOpen = await _client.auth.signInWithOAuth(
        const OAuthProvider(SupabaseConfig.yandexProvider),
        redirectTo: kIsWeb ? null : SupabaseConfig.authRedirectUri,
        scopes: 'login:info login:email',
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
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
    final callbackUri = Uri.parse(
      SupabaseConfig.telegramAuthUrl,
    ).replace(queryParameters: {'redirect_to': redirectTo});
    final uri = Uri.https('oauth.telegram.org', '/auth', {
      'bot_id': SupabaseConfig.telegramBotId,
      'origin': SupabaseConfig.telegramOrigin,
      'return_to': callbackUri.toString(),
      'request_access': 'write',
    });

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

  Future<void> updateProfile({
    required String name,
    required String handle,
  }) async {
    final cleanName = name.trim().isEmpty ? 'Ваш профиль' : name.trim();
    final cleanHandle = _normalizeHandle(handle);

    _profile = _profile.copyWith(name: cleanName, handle: cleanHandle);
    await _prefs.setString(_profileKey, jsonEncode(_profile.toJson()));
    notifyListeners();

    if (_hasSupabase && _client.auth.currentUser != null) {
      try {
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
      } catch (e) {
        debugPrint('Profile update error: $e');
      }
    }
  }

  Future<void> _handleAuthState(User? user) async {
    _currentUser = user;
    _authError = null;
    await _applyUserProfile(user, notify: false);
    if (user != null) {
      unawaited(_syncFromSupabase());
      unawaited(_syncOutfitsFromSupabase());
      unawaited(_syncThreadsFromSupabase());
    }
    notifyListeners();
  }

  Future<void> _applyUserProfile(User? user, {bool notify = true}) async {
    if (user == null) {
      if (notify) notifyListeners();
      return;
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
    final handle = '@${handleSource.toString().replaceAll('@', '').trim()}';

    if (name != null && name.isNotEmpty) {
      _profile = AppProfile(
        name: name,
        handle: handle,
        city: _profile.city,
        rating: _profile.rating,
        salesCount: _profile.salesCount,
      );
      await _prefs.setString(_profileKey, jsonEncode(_profile.toJson()));
    }

    if (notify) notifyListeners();
  }

  String _normalizeHandle(String value) {
    final raw = value
        .trim()
        .replaceAll('@', '')
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();
    if (raw.isEmpty) return '@user';
    return '@$raw';
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
        await _saveProducts();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Supabase sync error: $e');
    }
  }

  Future<void> _syncThreadsFromSupabase() async {
    if (!_hasSupabase) return;

    try {
      final response = await _client
          .from('message_threads')
          .select()
          .order('updated_at', ascending: false);

      final fetched = (response as List<dynamic>)
          .map((item) => MessageThread.fromSupabase(item))
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
    } catch (_) {
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
      await _writeList(_outfitsKey, _outfits.map((item) => item.toJson()));
      notifyListeners();
    } catch (e) {
      debugPrint('Outfits sync error: $e');
    }
  }

  // ─── Image Upload ───

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

      final ownedProduct = product.copyWith(ownerId: user.id);
      final data = ownedProduct.toSupabaseJson(sellerId: user.id);
      await _client.from('products').insert(data);
      _queueBackgroundRemoval(ownedProduct);

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

  Future<void> toggleProductLike(String productId) async {
    final product = _products.firstWhere((item) => item.id == productId);
    product.isLiked = !product.isLiked;
    await _saveProducts();
    notifyListeners();
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
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Outfit publish error: $e');
    }
  }

  // ─── Messages ───

  Future<void> contactSeller(Product product) async {
    final now = DateTime.now();
    final sellerName = product.brand.isEmpty ? 'Продавец' : product.brand;
    const firstMessage = 'Здравствуйте! Вещь ещё доступна?';
    _threads.removeWhere((thread) => thread.id == product.id);
    _threads.insert(
      0,
      MessageThread(
        id: product.id,
        sellerName: sellerName,
        productTitle: product.title,
        lastMessage: firstMessage,
        updatedAt: now,
        unreadCount: 0,
        messages: [
          ChatMessage(
            id: _uuid.v4(),
            text: firstMessage,
            createdAt: now,
            isMine: true,
          ),
        ],
      ),
    );
    _sortThreads();
    await _writeList(_threadsKey, _threads.map((item) => item.toJson()));
    await _upsertThread(_threads.first);
    notifyListeners();
  }

  Future<void> sendMessage(String threadId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final index = _threads.indexWhere((thread) => thread.id == threadId);
    if (index == -1) return;

    final now = DateTime.now();
    final thread = _threads[index];
    final message = ChatMessage(
      id: _uuid.v4(),
      text: trimmed,
      createdAt: now,
      isMine: true,
    );

    _threads[index] = thread.copyWith(
      lastMessage: trimmed,
      updatedAt: now,
      messages: [...thread.messages, message],
    );
    _sortThreads();
    await _writeList(_threadsKey, _threads.map((item) => item.toJson()));
    await _upsertThread(_threads.firstWhere((thread) => thread.id == threadId));
    notifyListeners();
  }

  Future<void> _upsertThread(MessageThread thread) async {
    if (!_hasSupabase) return;

    try {
      await _client
          .from('message_threads')
          .upsert(thread.toSupabaseJson(), onConflict: 'id');
    } catch (_) {
      // Optional table. Keep local chat flow responsive if it is absent.
    }
  }

  Future<User?> _ensureAuthSession() async {
    final currentUser = _client.auth.currentUser;
    if (currentUser != null) return currentUser;
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

  Future<void> _writeList(String key, Iterable<Map<String, dynamic>> items) {
    return _prefs.setString(key, jsonEncode(items.toList()));
  }

  Future<void> _saveProducts() {
    return _writeList(_productsKey, _products.map((item) => item.toJson()));
  }

  void _sortThreads() {
    _threads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}
