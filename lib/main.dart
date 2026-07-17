import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_typography.dart';
import 'core/supabase_config.dart';
import 'data/app_repository.dart';
import 'features/catalog_search/catalog_search_engine.dart';
import 'features/chat/chat_actions.dart';
import 'features/chat/product_share_sheet.dart';
import 'features/listing_publish/screens/listing_publish_flow_screen.dart';
import 'models/app_profile.dart';
import 'models/created_outfit.dart';
import 'models/message_thread.dart';
import 'models/product.dart';
import 'models/profile_feature.dart';
import 'screens/catalog_screen.dart';
import 'screens/login_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/outfit_create_screen.dart';
import 'screens/outfits_screen.dart';
import 'screens/outfit_only_item_screen.dart';
import 'screens/phone_login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/publish_outfit_screen.dart';
import 'screens/product_screen.dart';
import 'screens/reviews_screen.dart';
import 'screens/seller_profile_screen.dart';
import 'services/push_notification_service.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/create_entry_sheet.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PushNotificationService.initialize();
  await SupabaseConfig.initialize();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const FashionApp());
}

class FashionApp extends StatelessWidget {
  const FashionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fashion App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Montserrat',
        textTheme: _montserratMediumTextTheme(ThemeData.light().textTheme),
        primaryTextTheme: _montserratMediumTextTheme(
          ThemeData.light().primaryTextTheme,
        ),
        scaffoldBackgroundColor: Colors.white,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF070707),
          surface: Colors.white,
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Color(0xFF070707),
          selectionColor: Color(0x22070707),
          selectionHandleColor: Color(0xFF070707),
        ),
      ),
      home: const AppShell(),
    );
  }
}

TextTheme _montserratMediumTextTheme(TextTheme base) {
  TextStyle? medium(TextStyle? style) => style?.copyWith(
    fontFamily: AppTypography.fontFamily,
    fontWeight: AppTypography.medium,
    letterSpacing: 0,
  );

  return base.copyWith(
    displayLarge: medium(base.displayLarge),
    displayMedium: medium(base.displayMedium),
    displaySmall: medium(base.displaySmall),
    headlineLarge: medium(base.headlineLarge),
    headlineMedium: medium(base.headlineMedium),
    headlineSmall: medium(base.headlineSmall),
    titleLarge: medium(base.titleLarge),
    titleMedium: medium(base.titleMedium),
    titleSmall: medium(base.titleSmall),
    bodyLarge: medium(base.bodyLarge),
    bodyMedium: medium(base.bodyMedium),
    bodySmall: medium(base.bodySmall),
    labelLarge: medium(base.labelLarge),
    labelMedium: medium(base.labelMedium),
    labelSmall: medium(base.labelSmall),
  );
}

enum _CreateMode {
  none,
  createOutfit,
  publishOutfit,
  createItem,
  outfitOnlyItem,
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  static const double _sidePadding = 18.0;

  int _currentIndex = 0;
  _CreateMode _createMode = _CreateMode.none;
  bool _returnToPublishOutfitAfterItem = false;
  bool _createItemForOutfitOnly = false;
  bool _isAppActive = true;
  MessageNotification? _visibleMessageNotification;
  String? _handledMessageNotificationId;
  Timer? _messageNotificationTimer;
  Timer? _messageNotificationRemoveTimer;
  StreamSubscription<PushNotificationTap>? _pushTapSubscription;
  OverlayEntry? _messageNotificationEntry;
  final List<Product> _draftOutfitProducts = [];
  final AppRepository _repository = AppRepository();

  ChatActions get _chatActions => ChatActions(
    sendText: _repository.sendChatText,
    sendReply: _repository.sendReply,
    sendImage: _repository.sendChatImage,
    sendMedia: _repository.sendChatMedia,
    editMessage: _repository.editMessage,
    deleteMessage: _repository.deleteMessage,
    updateThread: _repository.updateThreadPreferences,
    saveDraft: _repository.saveThreadDraft,
    markRead: _repository.markThreadRead,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pushTapSubscription = PushNotificationService.onNotificationTap.listen(
      (tap) => unawaited(_handlePushNotificationTap(tap)),
    );
    _repository.load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initialTap = PushNotificationService.takeInitialTap();
      if (initialTap != null) {
        unawaited(_handlePushNotificationTap(initialTap));
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageNotificationTimer?.cancel();
    _messageNotificationRemoveTimer?.cancel();
    _pushTapSubscription?.cancel();
    _messageNotificationEntry?.remove();
    _repository.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isActive = state == AppLifecycleState.resumed;
    if (_isAppActive == isActive) return;
    _isAppActive = isActive;
    if (!isActive) {
      _hideMessageNotification();
    }
  }

  void _handleMessageNotification(MessageNotification? notification) {
    if (notification == null ||
        notification.id == _handledMessageNotificationId) {
      return;
    }
    _handledMessageNotificationId = notification.id;
    if (!_isAppActive) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(HapticFeedback.lightImpact());
      _messageNotificationRemoveTimer?.cancel();
      setState(() => _visibleMessageNotification = notification);
      _ensureMessageNotificationOverlay();
      _messageNotificationEntry?.markNeedsBuild();
      _messageNotificationTimer?.cancel();
      _messageNotificationTimer = Timer(const Duration(seconds: 4), () {
        if (!mounted || _visibleMessageNotification?.id != notification.id) {
          return;
        }
        _hideMessageNotification();
      });
    });
  }

  void _ensureMessageNotificationOverlay() {
    if (_messageNotificationEntry != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _messageNotificationEntry = OverlayEntry(
      builder: (context) => _MessageNotificationOverlay(
        notification: _visibleMessageNotification,
        onDismiss: _hideMessageNotification,
        onTap: _openMessageNotification,
      ),
    );
    overlay.insert(_messageNotificationEntry!);
  }

  void _hideMessageNotification() {
    _messageNotificationTimer?.cancel();
    if (!mounted) return;
    setState(() => _visibleMessageNotification = null);
    _messageNotificationEntry?.markNeedsBuild();
    _messageNotificationRemoveTimer?.cancel();
    _messageNotificationRemoveTimer = Timer(
      const Duration(milliseconds: 260),
      () {
        if (_visibleMessageNotification != null) return;
        _messageNotificationEntry?.remove();
        _messageNotificationEntry = null;
      },
    );
  }

  void _openMessageNotification(MessageNotification notification) {
    final thread = _repository.threadById(notification.threadId);
    if (thread == null) {
      _hideMessageNotification();
      return;
    }
    _hideMessageNotification();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (context) => ChatScreen(
          thread: thread,
          onSendMessage: _repository.sendMessage,
          onOpenProduct: _openProductFromChat,
          currentUserId: _repository.currentUserId,
          threadsListenable: _repository,
          resolveThread: _repository.threadById,
          lastSeenForUser: _repository.lastSeenForUser,
          actions: _chatActions,
          onOpenSellerProfile: () => _openSellerFromChat(thread),
          onBuyProduct: () => _buyFromChat(thread),
        ),
      ),
    );
  }

  Future<void> _openProfileNotification(
    ProfileNotification notification,
  ) async {
    if (notification.kind == 'message') {
      final threadId = notification.data['thread_id'] ?? notification.targetId;
      if (threadId.isNotEmpty) {
        final thread = _repository.threadById(threadId);
        if (thread != null) {
          _openMessageNotification(
            MessageNotification(
              id: notification.id,
              threadId: threadId,
              senderName: notification.title,
              text: notification.body,
            ),
          );
          return;
        }
      }
    }

    if (!mounted) return;
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
    setState(() {
      _currentIndex = 4;
      _createMode = _CreateMode.none;
    });
  }

  Future<void> _handlePushNotificationTap(PushNotificationTap tap) async {
    for (var attempt = 0; attempt < 25 && !_repository.isReady; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
    }
    if (!mounted) return;

    final data = {
      for (final entry in tap.data.entries)
        entry.key: entry.value?.toString() ?? '',
    };
    final notificationId = data['notification_id'] ?? '';
    if (notificationId.isNotEmpty) {
      await _repository.markNotificationRead(notificationId);
    }

    final kind = (data['kind'] ?? data['type'] ?? 'general').toLowerCase();
    final threadId = data['thread_id'] ?? '';
    if (kind == 'message' && threadId.isNotEmpty) {
      for (var attempt = 0; attempt < 20; attempt++) {
        if (!mounted) return;
        final thread = _repository.threadById(threadId);
        if (thread != null) {
          _openMessageNotification(
            MessageNotification(
              id: tap.messageId ?? notificationId,
              threadId: threadId,
              senderName: tap.title ?? data['title'] ?? '',
              text: tap.body ?? data['body'] ?? '',
            ),
          );
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    await _openProfileNotification(
      ProfileNotification(
        id: notificationId.isNotEmpty
            ? notificationId
            : (tap.messageId ??
                  'push-${DateTime.now().microsecondsSinceEpoch}'),
        title: tap.title ?? data['title'] ?? 'Уведомление',
        body: tap.body ?? data['body'] ?? '',
        kind: kind,
        targetId: data['target_id'] ?? '',
        data: data,
        isRead: true,
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _contactSellerFromProduct(
    Product product, {
    bool imageOnly = false,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final thread = await _repository.contactSeller(
      product,
      imageOnly: imageOnly,
    );
    if (!mounted) return;
    if (thread == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось открыть чат'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await navigator.maybePop();
    if (!mounted) return;
    navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => ChatScreen(
          thread: thread,
          onSendMessage: _repository.sendMessage,
          onOpenProduct: _openProductFromChat,
          currentUserId: _repository.currentUserId,
          threadsListenable: _repository,
          resolveThread: _repository.threadById,
          lastSeenForUser: _repository.lastSeenForUser,
          actions: _chatActions,
          onOpenSellerProfile: () => _openSellerFromChat(thread),
          onBuyProduct: () => _buyFromChat(thread),
        ),
      ),
    );
  }

  void _openProductDetails(Product product) {
    final route = PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.24),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (context, animation, secondaryAnimation) {
        return ProductScreen(
          sourceProduct: product,
          product: ProductDetailData(
            id: product.id,
            title: product.title,
            description: product.description,
            price: product.price,
            priceValue: product.priceValue,
            image: product.image,
            images: product.images.isNotEmpty
                ? product.images
                : [if (product.image.isNotEmpty) product.image],
            category: product.category,
            brand: product.brand,
            color: product.color,
            sellerName: product.sellerName,
            sellerHandle: product.sellerHandle,
            size: product.size,
            condition: product.condition,
            location: product.location,
            isLiked: product.isLiked,
            shippingAddress: product.shippingAddress,
            canPurchase: !product.isHidden,
            publishedAt: product.publishedAt,
            viewsCount: product.viewsCount,
            likesCount: product.likesCount,
            deliveryMethods: product.deliveryMethods,
          ),
          onLike: () => _repository.toggleProductLike(product.id),
          onOpenSeller: () => _openSellerProfile(product),
          onOpenReviews: () => _openReviewsForProduct(product),
          loadSellerProfile: _repository.fetchSellerProfile,
          loadReviews: _repository.fetchSellerReviews,
          onToggleRelatedLike: _repository.toggleProductLike,
          sellerFollowListenable: _repository,
          canFollowSeller: _repository.canFollowSeller,
          isFollowingSeller: _repository.isFollowingSeller,
          onToggleSellerFollow: _repository.toggleSellerFollow,
          onContactSeller: () => _contactSellerFromProduct(product),
          onShare: () => _shareProduct(product),
          relatedProducts: _relatedProductsFor(product),
          onRelatedProductTap: _openProductDetails,
          deliveryProfile: _repository.deliveryProfile,
          onSaveDeliveryProfile: _repository.updateDeliveryProfile,
          onCreateDeliveryOrder:
              ({required deliveryService, required deliveryPrice}) =>
                  _repository.createDeliveryOrder(
                    product,
                    deliveryService: deliveryService,
                    deliveryPrice: deliveryPrice,
                  ),
        );
      },
    );
    Navigator.of(context, rootNavigator: true).push(route);
    // Count only an accepted detail navigation. The repository applies the
    // optimistic unique-view update before its first await, so every entry
    // point (profile, chat, notification) renders the same current value.
    unawaited(_repository.recordProductView(product.id));
  }

  void _openProductFromChat(String productId) {
    if (productId.isEmpty) return;
    for (final product in _repository.products) {
      if (product.id == productId) {
        _openProductDetails(product);
        return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Товар не найден'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Product? _productForThread(MessageThread thread) {
    for (final product in _repository.products) {
      if (thread.productId.isNotEmpty && product.id == thread.productId) {
        return product;
      }
    }
    final sellerId = thread.otherPartyId(_repository.currentUserId);
    for (final product in _repository.products) {
      if (sellerId.isNotEmpty && product.ownerId == sellerId) return product;
    }
    return null;
  }

  void _openSellerFromChat(MessageThread thread) {
    final product = _productForThread(thread);
    if (product != null) {
      _openSellerProfile(product);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Профиль продавца не найден'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _buyFromChat(MessageThread thread) {
    final product = _productForThread(thread);
    if (product == null || product.isHidden) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Товар больше недоступен'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (context) => DeliveryCheckoutScreen(
          product: ProductDetailData(
            id: product.id,
            title: product.title,
            description: product.description,
            price: product.price,
            priceValue: product.priceValue,
            image: product.image,
            images: product.images,
            category: product.category,
            brand: product.brand,
            color: product.color,
            sellerName: product.sellerName,
            sellerHandle: product.sellerHandle,
            size: product.size,
            condition: product.condition,
            location: product.location,
            isLiked: product.isLiked,
            shippingAddress: product.shippingAddress,
            canPurchase: true,
            deliveryMethods: product.deliveryMethods,
          ),
          deliveryProfile: _repository.deliveryProfile,
          onSaveProfile: _repository.updateDeliveryProfile,
          onSubmitOrder: ({required deliveryService, required deliveryPrice}) =>
              _repository.createDeliveryOrder(
                product,
                deliveryService: deliveryService,
                deliveryPrice: deliveryPrice,
              ),
        ),
      ),
    );
  }

  Future<void> _openReviewsForProduct(Product product) async {
    final seller =
        await _repository.fetchSellerProfile(product) ??
        SellerProfile(
          id: product.ownerId,
          name: product.sellerName,
          handle: product.sellerHandle,
        );
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (context) => ReviewsScreen(
          seller: seller,
          sourceProduct: product,
          loadReviews: _repository.fetchSellerReviews,
          onCreateReview: _repository.createSellerReview,
          canCreateReview: _repository.isSignedIn,
        ),
      ),
    );
  }

  List<Product> _relatedProductsFor(Product product) {
    return rankRelatedCatalogProducts(product, _repository.products);
  }

  void _openSellerProfile(Product product) {
    final initialProducts = _repository.products.where((item) {
      if (product.ownerId.isNotEmpty) {
        return item.ownerId == product.ownerId;
      }
      final handle = product.sellerHandle.trim().toLowerCase();
      return handle.isNotEmpty &&
          item.sellerHandle.trim().toLowerCase() == handle;
    }).toList();

    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (context) => SellerProfileScreen(
          sourceProduct: product,
          initialProducts: initialProducts,
          loadProfile: _repository.fetchSellerProfile,
          loadProducts: _repository.fetchSellerProducts,
          onProductTap: _openProductDetails,
          onToggleLike: _repository.toggleProductLike,
          onShare: _shareProduct,
          loadReviews: _repository.fetchSellerReviews,
          onCreateReview: _repository.createSellerReview,
          canCreateReview: _repository.isSignedIn,
          sellerFollowListenable: _repository,
          canFollowSeller: _repository.canFollowSeller,
          isFollowingSeller: _repository.isFollowingSeller,
          onToggleSellerFollow: _repository.toggleSellerFollow,
          onReportSeller: (seller, reason) async {
            final submitted = await _repository.submitContentReport(
              targetType: 'user',
              targetId: seller.id,
              reason: reason,
            );
            return submitted ? null : 'Не удалось отправить жалобу';
          },
          onBlockSeller: (seller) async {
            final blocked = await _repository.blockUser(seller.id);
            return blocked ? null : 'Не удалось заблокировать пользователя';
          },
          onMessage: (seller) async {
            final navigator = Navigator.of(context, rootNavigator: true);
            final messenger = ScaffoldMessenger.of(context);
            final thread = await _repository.startDirectChat(
              seller.toUserProfile(),
            );
            if (!mounted) return;
            if (thread == null) {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Не удалось открыть чат'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              return;
            }
            navigator.push(
              MaterialPageRoute<void>(
                builder: (context) => ChatScreen(
                  thread: thread,
                  onSendMessage: _repository.sendMessage,
                  onOpenProduct: _openProductFromChat,
                  currentUserId: _repository.currentUserId,
                  threadsListenable: _repository,
                  resolveThread: _repository.threadById,
                  lastSeenForUser: _repository.lastSeenForUser,
                  actions: _chatActions,
                  onOpenSellerProfile: () => _openSellerFromChat(thread),
                  onBuyProduct: () => _buyFromChat(thread),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openOutfitAuthorProfile(CreatedOutfit outfit) {
    _openSellerProfile(_sellerProductForOutfit(outfit));
  }

  Product _sellerProductForOutfit(CreatedOutfit outfit) {
    final ownerId = outfit.ownerId.trim();
    if (ownerId.isNotEmpty) {
      for (final product in _repository.products) {
        if (product.ownerId == ownerId) return product;
      }
    }

    final authorHandle = outfit.authorHandle.trim().toLowerCase();
    if (authorHandle.isNotEmpty) {
      for (final product in _repository.products) {
        if (product.sellerHandle.trim().toLowerCase() == authorHandle) {
          return product;
        }
      }
    }

    final authorName = outfit.authorName.trim().toLowerCase();
    if (authorName.isNotEmpty) {
      for (final product in _repository.products) {
        if (product.sellerName.trim().toLowerCase() == authorName) {
          return product;
        }
      }
    }

    final displayName = outfit.authorName.trim().isEmpty
        ? 'Автор'
        : outfit.authorName.trim();
    final handle = outfit.authorHandle.trim().isEmpty
        ? '@user'
        : outfit.authorHandle.trim();
    final image = outfit.photos.isNotEmpty
        ? outfit.photos.first
        : outfit.items.isNotEmpty
        ? outfit.items.first.image
        : '';

    return Product(
      id: 'outfit_author_${outfit.id}',
      title: displayName,
      detailTitle: displayName,
      description: '',
      price: '',
      detailPrice: '',
      priceValue: 0,
      image: image,
      category: '',
      brand: '',
      size: '',
      color: '',
      condition: '',
      ownerId: ownerId,
      sellerName: displayName,
      sellerHandle: handle,
      dotsOnDark: false,
      isHidden: true,
    );
  }

  void _shareProduct(Product product) {
    unawaited(
      showProductShareSheet(
        context,
        product: product,
        threads: _repository.threads,
        currentUserId: _repository.currentUserId,
        searchUsers: _repository.searchUserProfiles,
        shareToThread: _repository.shareProductToThread,
        shareToUser: _repository.shareProductToUser,
      ),
    );
  }

  void _changeTab(int index) {
    if (!_repository.isSignedIn && (index == 3 || index == 4)) {
      _openLoginScreen(onSignedIn: () => _changeTab(index));
      return;
    }
    setState(() {
      _currentIndex = index;
      _createMode = _CreateMode.none;
      _returnToPublishOutfitAfterItem = false;
      _createItemForOutfitOnly = false;
    });
  }

  void _openCreateOutfit() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (routeContext) => OutfitCreateScreen(
          myProducts: _repository.myProducts,
          likedProducts: _repository.likedProducts,
          defaultAccessories: _repository.defaultAccessories,
          myAccessories: _repository.myAccessories,
          authorName: _repository.profile.name,
          authorHandle: _repository.profile.handle,
          authorAvatarUrl: _repository.profile.avatarUrl,
          onPublish: (outfit) =>
              _publishOutfitFromCreateRoute(routeContext, outfit),
          onCreateAccessory:
              (imageFile, {required bool isDefault, required String title}) {
                return _repository.createOutfitAccessory(
                  imageFile: imageFile,
                  isDefault: isDefault,
                  title: title,
                );
              },
        ),
      ),
    );
  }

  void _openPublishOutfit() {
    if (!_repository.isSignedIn) {
      _openLoginScreen(onSignedIn: _openPublishOutfit);
      return;
    }
    setState(() {
      _createMode = _CreateMode.publishOutfit;
      _currentIndex = 2;
      _returnToPublishOutfitAfterItem = false;
      _createItemForOutfitOnly = false;
    });
  }

  void _openCreateItem() {
    if (!_repository.isSignedIn) {
      _openLoginScreen(onSignedIn: _openCreateItem);
      return;
    }
    setState(() {
      _createMode = _CreateMode.createItem;
      _currentIndex = 2;
      _returnToPublishOutfitAfterItem = false;
      _createItemForOutfitOnly = false;
    });
  }

  Future<void> _publishOutfit(CreatedOutfit outfit) async {
    await _repository.publishOutfit(outfit);
    setState(() {
      _currentIndex = 1;
      _createMode = _CreateMode.none;
      _draftOutfitProducts.clear();
      _returnToPublishOutfitAfterItem = false;
      _createItemForOutfitOnly = false;
    });
  }

  Future<void> _publishOutfitFromCreateRoute(
    BuildContext routeContext,
    CreatedOutfit outfit,
  ) async {
    final navigator = Navigator.of(routeContext, rootNavigator: true);
    await _repository.publishOutfit(outfit);
    if (!mounted) return;
    navigator.popUntil((route) => route.isFirst);
    setState(() {
      _currentIndex = 1;
      _createMode = _CreateMode.none;
      _draftOutfitProducts.clear();
      _returnToPublishOutfitAfterItem = false;
      _createItemForOutfitOnly = false;
    });
  }

  Future<bool> _publishProduct(Product product) async {
    final didPublish = await _repository.publishProduct(product);
    if (didPublish) {
      setState(() {
        if (_returnToPublishOutfitAfterItem) {
          _currentIndex = 2;
          _createMode = _CreateMode.publishOutfit;
        } else {
          _currentIndex = 0;
          _createMode = _CreateMode.none;
        }
        _returnToPublishOutfitAfterItem = false;
        _createItemForOutfitOnly = false;
      });
    }
    return didPublish;
  }

  Future<void> _completeAutomatedListing(Product product) async {
    final adoptedProduct = await _repository.adoptPublishedProduct(product);
    if (!mounted) return;
    final shouldReturnToOutfit = _returnToPublishOutfitAfterItem;
    setState(() {
      if (shouldReturnToOutfit) {
        _currentIndex = 2;
        _createMode = _CreateMode.publishOutfit;
      } else {
        _currentIndex = 0;
        _createMode = _CreateMode.none;
      }
      _returnToPublishOutfitAfterItem = false;
      _createItemForOutfitOnly = false;
    });
    if (!shouldReturnToOutfit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openProductDetails(adoptedProduct);
      });
    }
  }

  Future<bool> _addProductToOutfitOnly(Product product) async {
    final draftProduct = product.copyWith(
      isHidden: true,
      ownerId: _repository.currentUserId,
    );
    final didPublish = await _repository.publishProduct(draftProduct);
    if (!didPublish) return false;
    setState(() {
      _draftOutfitProducts.insert(0, draftProduct);
      _currentIndex = 2;
      _createMode = _CreateMode.publishOutfit;
      _returnToPublishOutfitAfterItem = false;
      _createItemForOutfitOnly = false;
    });
    return true;
  }

  Future<void> _addOutfitOnlyProduct(Product product) async {
    await _addProductToOutfitOnly(product);
  }

  void _closeCreateItem() {
    if (_returnToPublishOutfitAfterItem || _createItemForOutfitOnly) {
      setState(() {
        _currentIndex = 2;
        _createMode = _CreateMode.publishOutfit;
        _returnToPublishOutfitAfterItem = false;
        _createItemForOutfitOnly = false;
      });
      return;
    }
    _changeTab(0);
  }

  void _showCreateSheet() {
    if (!_repository.isSignedIn) {
      _openLoginScreen(onSignedIn: _showCreateSheet);
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) => CreateEntrySheet(
        onCreateOutfit: () {
          Navigator.pop(ctx);
          _openCreateOutfit();
        },
        onPublishOutfit: () {
          Navigator.pop(ctx);
          _openPublishOutfit();
        },
        onCreateItem: () {
          Navigator.pop(ctx);
          _openCreateItem();
        },
      ),
    );
  }

  void _showOutfitItemChoiceSheet() {
    if (!_repository.isSignedIn) {
      _openLoginScreen(onSignedIn: _showOutfitItemChoiceSheet);
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      isScrollControlled: true,
      useSafeArea: false,
      builder: (ctx) => _OutfitItemChoiceSheet(
        onPublishItem: () {
          Navigator.pop(ctx);
          setState(() {
            _returnToPublishOutfitAfterItem = true;
            _createItemForOutfitOnly = false;
            _createMode = _CreateMode.createItem;
            _currentIndex = 2;
          });
        },
        onOutfitOnlyItem: () {
          Navigator.pop(ctx);
          setState(() {
            _returnToPublishOutfitAfterItem = true;
            _createItemForOutfitOnly = true;
            _createMode = _CreateMode.outfitOnlyItem;
            _currentIndex = 2;
          });
        },
      ),
    );
  }

  void _openLoginScreen({VoidCallback? onSignedIn}) {
    var didComplete = false;

    void closeLoginFlow(BuildContext loginContext) {
      if (!loginContext.mounted) return;
      final loginRoute = ModalRoute.of(loginContext);
      final navigator = Navigator.of(loginContext);
      if (loginRoute == null) {
        if (navigator.canPop()) navigator.pop();
        return;
      }
      navigator.popUntil((route) => identical(route, loginRoute));
      if (loginRoute.isCurrent) navigator.pop();
    }

    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (loginContext) => AnimatedBuilder(
          animation: _repository,
          builder: (context, _) {
            if (_repository.isSignedIn && !didComplete) {
              didComplete = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                closeLoginFlow(loginContext);
                onSignedIn?.call();
              });
            }
            return LoginScreen(
              onClose: () => Navigator.of(loginContext).pop(),
              onYandexTap: _repository.signInWithYandex,
              onVkTap: _repository.signInWithVk,
              isSigningIn: _repository.isSigningIn,
              authError: _repository.authError,
              onPhoneTap: () {
                Navigator.of(loginContext).push(
                  MaterialPageRoute<void>(
                    builder: (phoneContext) => PhoneLoginScreen(
                      onBack: () => Navigator.of(phoneContext).pop(),
                      onClose: () => closeLoginFlow(loginContext),
                      onRequestCode: _repository.requestPhoneOtp,
                      onVerifyCode: _repository.verifyPhoneOtp,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _repository,
      builder: (context, _) {
        _handleMessageNotification(_repository.latestMessageNotification);

        if (!_repository.isReady) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF070707),
                ),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: _currentIndex == 1
              ? const Color(0xFFF4F4F4)
              : Colors.white,
          body: SafeArea(
            top: false,
            bottom: false,
            child: IndexedStack(
              index: _currentIndex,
              children: [
                CatalogScreen(
                  scale: 1.0,
                  sidePadding: _sidePadding,
                  products: _repository.products,
                  onToggleLike: _repository.toggleProductLike,
                  onHideProduct: _repository.hideProduct,
                  onSubmitContentReport: _repository.submitContentReport,
                  onBlockUser: _repository.blockUser,
                  onShareProduct: _shareProduct,
                  onContactSeller: _repository.contactSeller,
                  onLoadSellerProfile: _repository.fetchSellerProfile,
                  onLoadSellerProducts: _repository.fetchSellerProducts,
                  onStartDirectChat: _repository.startDirectChat,
                  onSendMessage: _repository.sendMessage,
                  onProductViewed: (product) =>
                      _repository.recordProductView(product.id),
                  deliveryProfile: _repository.deliveryProfile,
                  onSaveDeliveryProfile: _repository.updateDeliveryProfile,
                  onCreateDeliveryOrder: _repository.createDeliveryOrder,
                  onLoadReviews: _repository.fetchSellerReviews,
                  onCreateReview: _repository.createSellerReview,
                  currentUserId: _repository.currentUserId,
                  threadsListenable: _repository,
                  resolveThread: _repository.threadById,
                  lastSeenForUser: _repository.lastSeenForUser,
                  chatActions: _chatActions,
                  sellerFollowListenable: _repository,
                  canFollowSeller: _repository.canFollowSeller,
                  isFollowingSeller: _repository.isFollowingSeller,
                  onToggleSellerFollow: _repository.toggleSellerFollow,
                ),
                OutfitsScreen(
                  scale: 1.0,
                  sidePadding: _sidePadding,
                  createdOutfits: _repository.outfits,
                  products: _repository.products,
                  onCreateTap: _openPublishOutfit,
                  onToggleProductLike: _repository.toggleProductLike,
                  onToggleOutfitLike: _repository.toggleOutfitLike,
                  onProductViewed: _repository.recordProductView,
                  onOutfitViewed: _repository.recordOutfitView,
                  onContactSeller: _contactSellerFromProduct,
                  onOpenSellerProfile: _openSellerProfile,
                  onSubmitContentReport: _repository.submitContentReport,
                  deliveryProfile: _repository.deliveryProfile,
                  onSaveDeliveryProfile: _repository.updateDeliveryProfile,
                  onCreateDeliveryOrder: _repository.createDeliveryOrder,
                  sellerFollowListenable: _repository,
                  canFollowSeller: _repository.canFollowSeller,
                  isFollowingSeller: _repository.isFollowingSeller,
                  onToggleSellerFollow: _repository.toggleSellerFollow,
                ),
                _buildCreateScreen(),
                MessagesScreen(
                  threads: _repository.threads,
                  onSendMessage: _repository.sendMessage,
                  onSearchUsers: _repository.searchUserProfiles,
                  onStartDirectChat: _repository.startDirectChat,
                  onCreateConversation: _repository.createConversation,
                  onOpenProduct: _openProductFromChat,
                  currentUserId: _repository.currentUserId,
                  threadsListenable: _repository,
                  resolveThread: _repository.threadById,
                  lastSeenForUser: _repository.lastSeenForUser,
                  actions: _chatActions,
                  onOpenSellerProfile: _openSellerFromChat,
                  onBuyProduct: _buyFromChat,
                ),
                ProfileScreen(
                  profile: _repository.profile,
                  products: _repository.myProducts,
                  likedProducts: _repository.likedProducts,
                  likedOutfits: _repository.likedOutfits,
                  recentlyViewedProducts: _repository.recentlyViewedProducts,
                  recentlyViewedOutfits: _repository.recentlyViewedOutfits,
                  outfits: _repository.myOutfits,
                  allProducts: _repository.products,
                  isSignedIn: _repository.isSignedIn,
                  isSigningIn: _repository.isSigningIn,
                  currentUserId: _repository.currentUserId,
                  accountLabel:
                      (_repository.currentUser?.email?.endsWith(
                            '@telegram.local',
                          ) ??
                          false)
                      ? _repository.profile.handle
                      : _repository.currentUser?.email,
                  authError: _repository.authError,
                  notifications: _repository.notifications,
                  notificationPreferences: _repository.notificationPreferences,
                  orders: _repository.orders,
                  sellerDashboardStats: _repository.sellerDashboardStats(),
                  deliveryProfile: _repository.deliveryProfile,
                  onSaveDeliveryProfile: _repository.updateDeliveryProfile,
                  onSignInWithYandex: _repository.signInWithYandex,
                  onSignInWithTelegram: _repository.signInWithTelegram,
                  onSignOut: _repository.signOut,
                  onUpdateProfile: _repository.updateProfile,
                  onSavePersonalProfile: _repository.savePersonalProfile,
                  onConfirmEmail: _repository.requestEmailConfirmation,
                  onDeleteAccount: _repository.deleteAccount,
                  onToggleProductLike: _repository.toggleProductLike,
                  onToggleOutfitLike: _repository.toggleOutfitLike,
                  onClearRecentlyViewed: _repository.clearRecentlyViewed,
                  onDeleteProduct: _repository.deleteProduct,
                  onProductTap: _openProductDetails,
                  onShareProduct: _shareProduct,
                  onOutfitAuthorTap: _openOutfitAuthorProfile,
                  onMarkNotificationRead: _repository.markNotificationRead,
                  onMarkAllNotificationsRead:
                      _repository.markAllNotificationsRead,
                  onNotificationTap: _openProfileNotification,
                  onUpdateNotificationPreferences:
                      _repository.updateNotificationPreferences,
                  onLoadReviews: _repository.fetchSellerReviews,
                  onOpenCatalog: () => _changeTab(0),
                ),
              ],
            ),
          ),
          bottomNavigationBar:
              _currentIndex == 2 && _createMode != _CreateMode.none
              ? null
              : AppBottomNav(
                  currentIndex: _currentIndex,
                  onTabSelected: _changeTab,
                  onCreateTap: _showCreateSheet,
                ),
        );
      },
    );
  }

  Widget _buildCreateScreen() {
    switch (_createMode) {
      case _CreateMode.createOutfit:
        return OutfitCreateScreen(
          onClose: () => _changeTab(0),
          myProducts: _repository.myProducts,
          likedProducts: _repository.likedProducts,
          defaultAccessories: _repository.defaultAccessories,
          myAccessories: _repository.myAccessories,
          authorName: _repository.profile.name,
          authorHandle: _repository.profile.handle,
          authorAvatarUrl: _repository.profile.avatarUrl,
          onPublish: _publishOutfit,
          onCreateAccessory:
              (imageFile, {required bool isDefault, required String title}) {
                return _repository.createOutfitAccessory(
                  imageFile: imageFile,
                  isDefault: isDefault,
                  title: title,
                );
              },
        );
      case _CreateMode.publishOutfit:
        return _buildPublishOutfitScreen();
      case _CreateMode.createItem:
        return ListingPublishFlowScreen(
          scale: 1.0,
          sidePadding: _sidePadding,
          sellerName: _repository.profile.name,
          sellerHandle: _repository.profile.handle,
          initialCity: _repository.profile.city,
          onPublished: _completeAutomatedListing,
          onClose: _closeCreateItem,
          onTabChange: _changeTab,
          onPublish: _createItemForOutfitOnly
              ? _addProductToOutfitOnly
              : _publishProduct,
          onUploadImage: _repository.uploadImage,
          publishButtonText: _createItemForOutfitOnly
              ? 'Добавить в образ'
              : 'Опубликовать вещь',
          successMessage: _createItemForOutfitOnly
              ? 'Вещь добавлена в образ'
              : 'Вещь опубликована',
          failureMessage: _createItemForOutfitOnly
              ? 'Не удалось добавить вещь в образ'
              : 'Не удалось сохранить вещь в базе',
        );
      case _CreateMode.outfitOnlyItem:
        return OutfitOnlyItemScreen(
          sidePadding: _sidePadding,
          onClose: _closeCreateItem,
          onAdd: _addOutfitOnlyProduct,
          onUploadImage: _repository.uploadImage,
        );
      case _CreateMode.none:
        return const SizedBox();
    }
  }

  Widget _buildPublishOutfitScreen() {
    return PublishOutfitScreen(
      sidePadding: _sidePadding,
      onClose: () => _changeTab(0),
      onPublish: _publishOutfit,
      products: [..._draftOutfitProducts, ..._repository.myProducts],
      currentUserId: _repository.currentUserId,
      onUploadImage: _repository.uploadImage,
      onAddItem: _showOutfitItemChoiceSheet,
    );
  }
}

class _MessageNotificationOverlay extends StatelessWidget {
  const _MessageNotificationOverlay({
    required this.notification,
    required this.onDismiss,
    required this.onTap,
  });

  final MessageNotification? notification;
  final VoidCallback onDismiss;
  final ValueChanged<MessageNotification> onTap;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).viewPadding.top;
    final current = notification;
    final isVisible = current != null;

    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: IgnorePointer(
        ignoring: !isVisible,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: -1.2, end: isVisible ? 0 : -1.2),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          builder: (context, offset, child) {
            final opacity = ((offset + 1.2) / 1.2).clamp(0.0, 1.0);
            return FractionalTranslation(
              translation: Offset(0, offset),
              child: Opacity(opacity: opacity, child: child),
            );
          },
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, topInset + 8, 12, 0),
            child: current == null
                ? const SizedBox(height: 68)
                : GestureDetector(
                    onTap: () => onTap(current),
                    behavior: HitTestBehavior.opaque,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE8E8EA)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.14),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: const BoxDecoration(
                                color: Color(0xFF070707),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  _notificationInitial(current.senderName),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    current.senderName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      height: 1.15,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF070707),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    current.text,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      height: 1.2,
                                      color: Color(0xFF6F6F76),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: onDismiss,
                              icon: const Icon(
                                Icons.close,
                                size: 18,
                                color: Color(0xFF8F8F94),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

String _notificationInitial(String value) {
  final clean = value.trim();
  if (clean.isEmpty) return '?';
  return clean.characters.first.toUpperCase();
}

class _OutfitItemChoiceSheet extends StatelessWidget {
  const _OutfitItemChoiceSheet({
    required this.onPublishItem,
    required this.onOutfitOnlyItem,
  });

  final VoidCallback onPublishItem;
  final VoidCallback onOutfitOnlyItem;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFE0E0E4),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          _OutfitItemChoiceTile(
            icon: Icons.storefront_outlined,
            title: 'Добавить для публикации',
            subtitle: 'Вещь появится в каталоге и будет доступна в образе',
            onTap: onPublishItem,
          ),
          const SizedBox(height: 10),
          _OutfitItemChoiceTile(
            icon: Icons.checkroom_outlined,
            title: 'Только для образа',
            subtitle: 'Вещь попадет только в текущий образ, без каталога',
            onTap: onOutfitOnlyItem,
          ),
        ],
      ),
    );
  }
}

class _OutfitItemChoiceTile extends StatelessWidget {
  const _OutfitItemChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8F9),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEDEDF0)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 22, color: const Color(0xFF111111)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF111111),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.15,
                      color: Color(0xFF8F8F94),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 22, color: Color(0xFFB8B8BE)),
          ],
        ),
      ),
    );
  }
}

class CreateOutfitComingSoonScreen extends StatelessWidget {
  const CreateOutfitComingSoonScreen({
    super.key,
    required this.sidePadding,
    required this.onClose,
  });

  final double sidePadding;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).viewPadding.top;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        sidePadding,
        topInset + 14,
        sidePadding,
        110,
      ),
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                GestureDetector(
                  onTap: onClose,
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.close,
                      size: 26,
                      color: Color(0xFF0B0B0B),
                    ),
                  ),
                ),
                const Expanded(
                  child: Center(
                    child: Text(
                      'Создать образ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF0B0B0B),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 44),
              ],
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Будет доступно потом',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF111111),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
