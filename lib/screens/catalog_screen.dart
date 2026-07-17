import 'package:flutter/material.dart';

import '../core/app_appearance.dart';
import '../core/app_typography.dart';
import '../features/catalog_search/catalog_search_engine.dart';
import '../features/catalog_search/catalog_search_history.dart';
import '../features/catalog_search/catalog_search_screen.dart';
import '../features/chat/chat_actions.dart';
import '../features/listing_publish/data/listing_catalogs.dart';
import '../features/visual_search/visual_search_camera_screen.dart';
import '../models/app_profile.dart';
import '../models/message_thread.dart';
import '../models/product.dart';
import '../models/profile_feature.dart';
import '../widgets/app_image.dart';
import '../widgets/promo_banner_carousel.dart';
import 'messages_screen.dart';
import 'product_screen.dart';
import 'reviews_screen.dart';
import 'seller_profile_screen.dart';

class CatalogScreen extends StatefulWidget {
  final double scale;
  final double sidePadding;
  final List<Product> products;
  final Future<void> Function(String productId) onToggleLike;
  final Future<void> Function(String productId) onHideProduct;
  final Future<bool> Function({
    required String targetType,
    required String targetId,
    required String reason,
    String details,
  })
  onSubmitContentReport;
  final Future<bool> Function(String userId) onBlockUser;
  final ValueChanged<Product> onShareProduct;
  final Future<MessageThread?> Function(Product product) onContactSeller;
  final Future<SellerProfile?> Function(Product product) onLoadSellerProfile;
  final Future<List<Product>> Function(String sellerId) onLoadSellerProducts;
  final Future<MessageThread?> Function(AppUserProfile recipient)
  onStartDirectChat;
  final Future<void> Function(String threadId, String text) onSendMessage;
  final void Function(Product product) onProductViewed;
  final DeliveryProfile deliveryProfile;
  final Future<void> Function(DeliveryProfile profile) onSaveDeliveryProfile;
  final Future<AppOrder?> Function(
    Product product, {
    required String deliveryService,
    required int deliveryPrice,
  })
  onCreateDeliveryOrder;
  final Future<List<SellerReview>> Function(String sellerId) onLoadReviews;
  final Future<void> Function({
    required String sellerId,
    required String productId,
    required String productTitle,
    required String productImage,
    required int rating,
    required String text,
    bool hasPhoto,
  })
  onCreateReview;
  final String currentUserId;
  final Listenable threadsListenable;
  final MessageThread? Function(String threadId) resolveThread;
  final DateTime? Function(String userId) lastSeenForUser;
  final ChatActions? chatActions;
  final Listenable? sellerFollowListenable;
  final bool Function(String sellerId)? canFollowSeller;
  final bool Function(String sellerId)? isFollowingSeller;
  final Future<bool> Function(String sellerId)? onToggleSellerFollow;
  final VoidCallback? onOpenAppearance;

  const CatalogScreen({
    super.key,
    required this.scale,
    required this.sidePadding,
    required this.products,
    required this.onToggleLike,
    required this.onHideProduct,
    required this.onSubmitContentReport,
    required this.onBlockUser,
    required this.onShareProduct,
    required this.onContactSeller,
    required this.onLoadSellerProfile,
    required this.onLoadSellerProducts,
    required this.onStartDirectChat,
    required this.onSendMessage,
    required this.onProductViewed,
    required this.deliveryProfile,
    required this.onSaveDeliveryProfile,
    required this.onCreateDeliveryOrder,
    required this.onLoadReviews,
    required this.onCreateReview,
    required this.currentUserId,
    required this.threadsListenable,
    required this.resolveThread,
    required this.lastSeenForUser,
    this.chatActions,
    this.sellerFollowListenable,
    this.canFollowSeller,
    this.isFollowingSeller,
    this.onToggleSellerFollow,
    this.onOpenAppearance,
  });

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen>
    with SingleTickerProviderStateMixin {
  int _selectedTabIndex = 1;
  String _selectedSort = 'По рекомендациям';
  final ScrollController _scrollController = ScrollController();
  bool _showFloatingSearch = false;
  double _lastScrollOffset = 0;
  final _filters = _CatalogFilters();
  final _searchHistory = CatalogSearchHistory();
  late CatalogSearchIndex _searchIndex;
  late int _indexedProductCount;

  final List<String> _tabs = [
    'Новинки',
    'Рекомендации',
    'Женское',
    'Мужское',
    'Деним',
    'Топы',
    'Низ',
  ];

  List<PromoBanner> get _promoBanners {
    return [
      PromoBanner(
        image: 'assets/products/try_theme.jpg',
        title: '',
        subtitle: '',
        buttonText: 'НАСТРОИТЬ ТЕМУ',
        onTap: widget.onOpenAppearance,
      ),
      PromoBanner(
        image: 'assets/products/try_photo.png',
        title: '',
        subtitle: '',
        buttonText: 'ПОПРОБОВАТЬ',
        onTap: _openVisualSearch,
      ),
    ];
  }

  List<Product> get _visibleProducts {
    final products = widget.products
        .where((product) => !product.isHidden)
        .where(_matchesSelectedTab)
        .where(_matchesHardFilters)
        .toList();
    products.sort(_compareSelectedSort);
    return products;
  }

  int _compareSelectedSort(Product a, Product b) {
    switch (_selectedSort) {
      case 'Сначала дешёвые':
        return a.priceValue.compareTo(b.priceValue);
      case 'Сначала дорогие':
        return b.priceValue.compareTo(a.priceValue);
      case 'Сначала новые':
        return _comparePublicationDate(a, b);
      case 'Популярные':
        final popularityOrder = (b.likesCount * 4 + b.viewsCount).compareTo(
          a.likesCount * 4 + a.viewsCount,
        );
        return popularityOrder != 0
            ? popularityOrder
            : _comparePublicationDate(a, b);
      case 'По рекомендациям':
      default:
        return _softScore(b).compareTo(_softScore(a));
    }
  }

  bool _matchesHardFilters(Product product) {
    final category = product.normalizedCategory.isNotEmpty
        ? product.normalizedCategory
        : ListingCatalogs.normalizeCategory(product.itemType);
    if (_filters.category.isNotEmpty && category != _filters.category) {
      return false;
    }
    if (_filters.size.isNotEmpty &&
        !_sameOption(product.size, _filters.size, field: 'size')) {
      return false;
    }
    if (_filters.minPrice != null && product.priceValue < _filters.minPrice!) {
      return false;
    }
    if (_filters.maxPrice != null && product.priceValue > _filters.maxPrice!) {
      return false;
    }
    if (_filters.brand.isNotEmpty &&
        _normalizedText(
              product.normalizedBrand.isNotEmpty
                  ? product.normalizedBrand
                  : product.brand,
            ) !=
            _normalizedText(_filters.brand)) {
      return false;
    }
    if (_filters.condition.isNotEmpty &&
        !_sameOption(
          product.condition,
          _filters.condition,
          field: 'condition',
        )) {
      return false;
    }
    final audience = product.audience.isNotEmpty
        ? product.audience
        : product.gender;
    if (_filters.audience.isNotEmpty && audience != _filters.audience) {
      return false;
    }
    if (_filters.delivery.isNotEmpty &&
        !product.deliveryMethods.contains(_filters.delivery)) {
      return false;
    }
    if (_filters.color.isNotEmpty &&
        !_sameOption(
          product.primaryColor.isEmpty ? product.color : product.primaryColor,
          _filters.color,
          field: 'color',
        )) {
      return false;
    }
    if (_filters.material.isNotEmpty &&
        !_sameOption(product.material, _filters.material, field: 'material')) {
      return false;
    }
    if (_filters.pattern.isNotEmpty &&
        !_sameOption(product.pattern, _filters.pattern, field: 'pattern')) {
      return false;
    }
    if (_filters.fit.isNotEmpty &&
        !_sameOption(product.fit, _filters.fit, field: 'fit')) {
      return false;
    }
    if (_filters.style.isNotEmpty &&
        !_sameOption(product.style, _filters.style, field: 'style')) {
      return false;
    }
    return true;
  }

  int _comparePublicationDate(Product left, Product right) {
    final leftDate = left.publishedAt?.microsecondsSinceEpoch ?? -1;
    final rightDate = right.publishedAt?.microsecondsSinceEpoch ?? -1;
    final dateOrder = rightDate.compareTo(leftDate);
    if (dateOrder != 0) return dateOrder;
    return right.id.compareTo(left.id);
  }

  bool _matchesSelectedTab(Product product) {
    final audience = product.audience.isNotEmpty
        ? product.audience
        : product.gender;
    final category = product.normalizedCategory.isNotEmpty
        ? product.normalizedCategory
        : ListingCatalogs.normalizeCategory(product.itemType);
    return switch (_selectedTabIndex) {
      2 => audience == 'female',
      3 => audience == 'male',
      4 => category == 'jeans' || product.material == 'denim',
      5 => ListingCatalogs.isTopCategory(category),
      6 => ListingCatalogs.isBottomCategory(category),
      _ => true,
    };
  }

  int _softScore(Product product) {
    var score = 0;
    if (_filters.color.isNotEmpty &&
        _sameOption(
          product.primaryColor.isEmpty ? product.color : product.primaryColor,
          _filters.color,
          field: 'color',
        )) {
      score += 5;
    }
    if (_filters.material.isNotEmpty &&
        _sameOption(product.material, _filters.material, field: 'material')) {
      score += 4;
    }
    if (_filters.pattern.isNotEmpty &&
        _sameOption(product.pattern, _filters.pattern, field: 'pattern')) {
      score += 3;
    }
    if (_filters.fit.isNotEmpty &&
        _sameOption(product.fit, _filters.fit, field: 'fit')) {
      score += 3;
    }
    if (_filters.style.isNotEmpty &&
        _sameOption(product.style, _filters.style, field: 'style')) {
      score += 2;
    }
    return score;
  }

  bool _sameOption(String actual, String selected, {required String field}) {
    if (_normalizedText(actual) == _normalizedText(selected)) return true;
    final display = switch (field) {
      'size' => ListingCatalogs.sizeName(selected, fallback: selected),
      'condition' => ListingCatalogs.conditionName(
        selected,
        fallback: selected,
      ),
      'color' => ListingCatalogs.colorName(selected, fallback: selected),
      _ => ListingCatalogs.attributeValueName(
        field,
        selected,
        fallback: selected,
      ),
    };
    return _normalizedText(actual) == _normalizedText(display);
  }

  String _normalizedText(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+'), '');

  @override
  void initState() {
    super.initState();
    _searchIndex = CatalogSearchIndex(widget.products);
    _indexedProductCount = widget.products.length;
    _scrollController.addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(covariant CatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.products, widget.products) ||
        _indexedProductCount != widget.products.length) {
      _searchIndex = CatalogSearchIndex(widget.products);
      _indexedProductCount = widget.products.length;
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    final offset = _scrollController.offset;
    final searchHiddenOffset = _promoBannerHeight(context) + 16 + 42;
    final delta = offset - _lastScrollOffset;
    final isSearchHidden = offset > searchHiddenOffset;

    if (!isSearchHidden) {
      if (_showFloatingSearch) {
        setState(() => _showFloatingSearch = false);
      }
      _lastScrollOffset = offset;
      return;
    }

    if (delta < -1.5 && !_showFloatingSearch) {
      setState(() => _showFloatingSearch = true);
    } else if (delta > 1.5 && _showFloatingSearch) {
      setState(() => _showFloatingSearch = false);
    }

    _lastScrollOffset = offset;
  }

  double _promoBannerHeight(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return (screenWidth * 1.40).clamp(525.0, 570.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.only(bottom: 138),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PromoBannerCarousel(
                banners: _promoBanners,
                height: _promoBannerHeight(context),
              ),
              const SizedBox(height: 16),
              _buildHeader(widget.scale),
              _buildTabs(widget.scale),
              _buildFilterRow(widget.scale),
              _buildProductGrid(widget.scale),
            ],
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 460),
          curve: Curves.easeInOutCubic,
          top: _showFloatingSearch ? 0 : -140,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !_showFloatingSearch,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeInOut,
              opacity: _showFloatingSearch ? 1 : 0,
              child: _buildFloatingSearch(widget.scale),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingSearch(double scale) {
    final palette = context.appPalette;
    return Material(
      color: palette.surfaceRaised,
      elevation: 8,
      shadowColor: palette.shadow,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          widget.sidePadding,
          MediaQuery.of(context).viewPadding.top + 8,
          widget.sidePadding,
          10,
        ),
        child: SizedBox(height: 42, child: _buildSearchActions(scale)),
      ),
    );
  }

  Widget _buildHeader(double scale) {
    return Padding(
      padding: EdgeInsets.only(
        top: 0,
        left: widget.sidePadding,
        right: widget.sidePadding,
        bottom: 18,
      ),
      child: SizedBox(height: 42, child: _buildSearchActions(scale)),
    );
  }

  Widget _buildSearchActions(double scale) {
    final palette = context.appPalette;
    return Material(
      color: palette.surfaceMuted,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: _showTextSearch,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.only(left: 14, right: 8),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, size: 21, color: palette.ink),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Найти вещь или бренд',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 13.5 * scale,
                          fontWeight: AppTypography.medium,
                          color: palette.muted,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(5),
            child: Material(
              color: palette.ink,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _openVisualSearch,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(
                    Icons.center_focus_strong_rounded,
                    size: 20,
                    color: palette.surface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(double scale) {
    final palette = context.appPalette;
    return Column(
      children: [
        SizedBox(
          height: 31 * scale,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: widget.sidePadding),
            itemCount: _tabs.length,
            separatorBuilder: (context, index) => SizedBox(width: 27 * scale),
            itemBuilder: (context, index) {
              final isActive = index == _selectedTabIndex;
              return GestureDetector(
                onTap: () => setState(() => _selectedTabIndex = index),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(
                      _tabs[index],
                      style: TextStyle(
                        fontSize: 13.5 * scale,
                        fontWeight: isActive
                            ? FontWeight.w500
                            : FontWeight.w500,
                        color: isActive ? palette.ink : palette.muted,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      height: 2,
                      width: isActive ? _tabs[index].length * 7.1 * scale : 0,
                      decoration: BoxDecoration(
                        color: isActive ? palette.ink : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Container(height: 1, color: palette.border),
      ],
    );
  }

  Widget _buildFilterRow(double scale) {
    final palette = context.appPalette;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.sidePadding),
      child: SizedBox(
        height: 52 * scale,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _showFilterSheet,
              child: Row(
                children: [
                  Text(
                    _filters.activeCount == 0
                        ? 'Фильтр'
                        : 'Фильтр ${_filters.activeCount}',
                    style: TextStyle(
                      fontSize: 14.5 * scale,
                      fontWeight: FontWeight.w500,
                      color: palette.ink,
                    ),
                  ),
                  SizedBox(width: 10 * scale),
                  Icon(Icons.tune, size: 21 * scale, color: palette.ink),
                ],
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _showSortSheet,
              child: Row(
                children: [
                  Text(
                    'Сорт',
                    style: TextStyle(
                      fontSize: 14.5 * scale,
                      fontWeight: FontWeight.w500,
                      color: palette.ink,
                    ),
                  ),
                  SizedBox(width: 4 * scale),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 17 * scale,
                    color: palette.ink,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductGrid(double scale) {
    final products = _visibleProducts;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8 * scale),
      child: GridView.builder(
        padding: EdgeInsets.only(top: 7 * scale, bottom: 132 * scale),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: products.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 7 * scale,
          mainAxisSpacing: 4 * scale,
          mainAxisExtent: 320 * scale,
        ),
        itemBuilder: (context, index) {
          final product = products[index];
          return ProductCard(
            product: product,
            scale: scale,
            onTap: () => _showProductDetails(product),
            onLike: () => _toggleLike(product.id),
            onMenu: () => _showProductMenu(product),
            onShare: () => _showShareSheet(product),
          );
        },
      ),
    );
  }

  Future<void> _toggleLike(String productId) async {
    await widget.onToggleLike(productId);
  }

  Future<void> _hideProduct(String productId) async {
    await widget.onHideProduct(productId);
  }

  Future<void> _openVisualSearch() async {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (context) => VisualSearchCameraScreen(
          catalogProducts: widget.products,
          onProductTap: _showProductDetails,
          onToggleLike: widget.onToggleLike,
          onProductMenu: _showProductMenu,
          onShareProduct: widget.onShareProduct,
        ),
      ),
    );
  }

  void _openSellerProfile(Product product) {
    final initialProducts = widget.products
        .where((item) => item.ownerId == product.ownerId)
        .toList();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (context) => SellerProfileScreen(
          sourceProduct: product,
          initialProducts: initialProducts,
          loadProfile: widget.onLoadSellerProfile,
          loadProducts: widget.onLoadSellerProducts,
          onToggleLike: widget.onToggleLike,
          onShare: _showShareSheet,
          onProductTap: _showProductDetails,
          loadReviews: widget.onLoadReviews,
          onCreateReview: widget.onCreateReview,
          canCreateReview: widget.currentUserId.isNotEmpty,
          sellerFollowListenable: widget.sellerFollowListenable,
          canFollowSeller: widget.canFollowSeller,
          isFollowingSeller: widget.isFollowingSeller,
          onToggleSellerFollow: widget.onToggleSellerFollow,
          onReportSeller: (seller, reason) async {
            final submitted = await widget.onSubmitContentReport(
              targetType: 'user',
              targetId: seller.id,
              reason: reason,
            );
            return submitted ? null : 'Не удалось отправить жалобу';
          },
          onBlockSeller: (seller) async {
            final blocked = await widget.onBlockUser(seller.id);
            return blocked ? null : 'Не удалось заблокировать пользователя';
          },
          onMessage: (seller) async {
            final navigator = Navigator.of(context, rootNavigator: true);
            final thread = await widget.onStartDirectChat(
              seller.toUserProfile(),
            );
            if (!mounted) return;
            if (thread == null) {
              _showSnackBar('Не удалось открыть чат');
              return;
            }
            navigator.push(
              MaterialPageRoute<void>(
                builder: (context) => ChatScreen(
                  thread: thread,
                  onSendMessage: widget.onSendMessage,
                  onOpenProduct: _openProductFromChat,
                  currentUserId: widget.currentUserId,
                  threadsListenable: widget.threadsListenable,
                  resolveThread: widget.resolveThread,
                  lastSeenForUser: widget.lastSeenForUser,
                  actions: widget.chatActions,
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

  void _showProductDetails(Product product) {
    final route = PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
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
                : [product.image],
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
          onLike: () => _toggleLike(product.id),
          onOpenSeller: () => _openSellerProfile(product),
          onOpenReviews: () => _openReviewsForProduct(product),
          loadSellerProfile: widget.onLoadSellerProfile,
          loadReviews: widget.onLoadReviews,
          onToggleRelatedLike: widget.onToggleLike,
          sellerFollowListenable: widget.sellerFollowListenable,
          canFollowSeller: widget.canFollowSeller,
          isFollowingSeller: widget.isFollowingSeller,
          onToggleSellerFollow: widget.onToggleSellerFollow,
          relatedProducts: _relatedProductsFor(product),
          onRelatedProductTap: _showProductDetails,
          deliveryProfile: widget.deliveryProfile,
          onSaveDeliveryProfile: widget.onSaveDeliveryProfile,
          onCreateDeliveryOrder:
              ({required deliveryService, required deliveryPrice}) =>
                  widget.onCreateDeliveryOrder(
                    product,
                    deliveryService: deliveryService,
                    deliveryPrice: deliveryPrice,
                  ),
          onContactSeller: () async {
            final navigator = Navigator.of(context, rootNavigator: true);
            final thread = await widget.onContactSeller(product);
            if (!mounted) return;
            if (thread == null) {
              _showSnackBar('Не удалось открыть чат');
              return;
            }
            await navigator.maybePop();
            if (!mounted) return;
            navigator.push(
              MaterialPageRoute<void>(
                builder: (context) => ChatScreen(
                  thread: thread,
                  onSendMessage: widget.onSendMessage,
                  onOpenProduct: _openProductFromChat,
                  currentUserId: widget.currentUserId,
                  threadsListenable: widget.threadsListenable,
                  resolveThread: widget.resolveThread,
                  lastSeenForUser: widget.lastSeenForUser,
                  actions: widget.chatActions,
                  onOpenSellerProfile: () => _openSellerFromChat(thread),
                  onBuyProduct: () => _buyFromChat(thread),
                ),
              ),
            );
          },
          onShare: () => widget.onShareProduct(product),
        );
      },
    );
    Navigator.of(context, rootNavigator: true).push(route);
    // Recording happens only after Navigator accepted the detail route. The
    // repository updates the local product synchronously before its first
    // await, so the detail screen can render the new optimistic count.
    widget.onProductViewed(product);
  }

  List<Product> _relatedProductsFor(Product product) {
    return rankRelatedCatalogProducts(product, widget.products);
  }

  Future<void> _openReviewsForProduct(Product product) async {
    final seller =
        await widget.onLoadSellerProfile(product) ??
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
          loadReviews: widget.onLoadReviews,
          onCreateReview: widget.onCreateReview,
          canCreateReview: widget.currentUserId.isNotEmpty,
        ),
      ),
    );
  }

  void _showTextSearch() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (context) => CatalogSearchScreen(
          products: widget.products,
          index: _searchIndex,
          history: _searchHistory,
          onProductTap: _showProductDetails,
          onToggleLike: widget.onToggleLike,
          onProductMenu: _showProductMenu,
          onShareProduct: widget.onShareProduct,
        ),
      ),
    );
  }

  void _showFilterSheet() {
    _showAppSheet(
      title: 'Фильтр',
      child: _CatalogFilterSheet(
        initial: _filters,
        products: widget.products,
        onApply: (filters) {
          setState(() => _filters.replaceWith(filters));
          Navigator.pop(context);
        },
        onReset: () {
          setState(_filters.clear);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showSortSheet() {
    const options = [
      'Сначала новые',
      'Сначала дешёвые',
      'Сначала дорогие',
      'Популярные',
      'По рекомендациям',
    ];
    _showAppSheet(
      title: 'Сортировка',
      child: Column(
        children: options.map((option) {
          final isSelected = option == _selectedSort;
          return _SheetOption(
            label: option,
            isSelected: isSelected,
            onTap: () {
              setState(() => _selectedSort = option);
              Navigator.pop(context);
            },
          );
        }).toList(),
      ),
    );
  }

  void _showProductMenu(Product product) {
    _showAppSheet(
      title: 'Действия с товаром',
      child: Column(
        children: [
          _SheetOption(
            label: 'Пожаловаться',
            icon: Icons.flag_outlined,
            onTap: () {
              Navigator.pop(context);
              _showReportSheet(product);
            },
          ),
          _SheetOption(
            label: 'Скрыть товар',
            icon: Icons.block_outlined,
            onTap: () async {
              Navigator.pop(context);
              try {
                await _hideProduct(product.id);
                if (!mounted) return;
                _showSnackBar('Товар скрыт');
              } catch (_) {
                if (!mounted) return;
                _showSnackBar('Не удалось скрыть товар');
              }
            },
          ),
          if (product.ownerId.trim().isNotEmpty &&
              product.ownerId != widget.currentUserId)
            _SheetOption(
              label: 'Заблокировать продавца',
              icon: Icons.person_off_outlined,
              onTap: () {
                Navigator.pop(context);
                _confirmBlockSeller(product);
              },
            ),
          _SheetOption(
            label: 'Поделиться ссылкой',
            icon: Icons.link,
            onTap: () {
              Navigator.pop(context);
              _showShareSheet(product);
            },
          ),
        ],
      ),
    );
  }

  void _showReportSheet(Product product) {
    const reasons = [
      'Подделка',
      'Спам',
      'Неподходящий контент',
      'Обман',
      'Другое',
    ];
    String selectedReason = reasons.first;
    _showAppSheet(
      title: 'Пожаловаться',
      child: StatefulBuilder(
        builder: (context, setSheetState) {
          return Column(
            children: [
              ...reasons.map((reason) {
                return _SheetOption(
                  label: reason,
                  isSelected: reason == selectedReason,
                  onTap: () => setSheetState(() => selectedReason = reason),
                );
              }),
              const SizedBox(height: 20),
              _SheetButton(
                label: 'Отправить',
                isPrimary: true,
                onTap: () async {
                  Navigator.pop(context);
                  final submitted = await widget.onSubmitContentReport(
                    targetType: 'product',
                    targetId: product.id,
                    reason: selectedReason,
                  );
                  if (!mounted) return;
                  _showSnackBar(
                    submitted
                        ? 'Жалоба отправлена'
                        : 'Не удалось отправить жалобу',
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmBlockSeller(Product product) {
    _showAppSheet(
      title: 'Заблокировать продавца?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Объявления и сообщения ${product.sellerName.trim().isEmpty ? 'этого пользователя' : product.sellerName} будут скрыты.',
            style: const TextStyle(fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 20),
          _SheetButton(
            label: 'Заблокировать',
            isPrimary: true,
            onTap: () async {
              Navigator.pop(context);
              final blocked = await widget.onBlockUser(product.ownerId);
              if (!mounted) return;
              _showSnackBar(
                blocked
                    ? 'Продавец заблокирован'
                    : 'Не удалось заблокировать продавца',
              );
            },
          ),
        ],
      ),
    );
  }

  void _showShareSheet(Product product) {
    widget.onShareProduct(product);
  }

  void _openProductFromChat(String productId) {
    for (final product in widget.products) {
      if (product.id == productId) {
        _showProductDetails(product);
        return;
      }
    }
    _showSnackBar('Объявление больше недоступно');
  }

  Product? _productForThread(MessageThread thread) {
    for (final product in widget.products) {
      if (thread.productId.isNotEmpty && product.id == thread.productId) {
        return product;
      }
    }
    final sellerId = thread.otherPartyId(widget.currentUserId);
    for (final product in widget.products) {
      if (sellerId.isNotEmpty && product.ownerId == sellerId) return product;
    }
    return null;
  }

  void _openSellerFromChat(MessageThread thread) {
    final product = _productForThread(thread);
    if (product == null) {
      _showSnackBar('Профиль продавца не найден');
      return;
    }
    _openSellerProfile(product);
  }

  void _buyFromChat(MessageThread thread) {
    final product = _productForThread(thread);
    if (product == null || product.isHidden) {
      _showSnackBar('Товар больше недоступен');
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
            deliveryMethods: product.deliveryMethods,
          ),
          deliveryProfile: widget.deliveryProfile,
          onSaveProfile: widget.onSaveDeliveryProfile,
          onSubmitOrder: ({required deliveryService, required deliveryPrice}) =>
              widget.onCreateDeliveryOrder(
                product,
                deliveryService: deliveryService,
                deliveryPrice: deliveryPrice,
              ),
        ),
      ),
    );
  }

  void _showAppSheet({required String title, required Widget child}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (context) {
        return _AppActionSheet(title: title, child: child);
      },
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class ProductCard extends StatelessWidget {
  final Product product;
  final double scale;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onMenu;
  final VoidCallback onShare;

  const ProductCard({
    super.key,
    required this.product,
    required this.scale,
    required this.onTap,
    required this.onLike,
    required this.onMenu,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 320 * scale,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildImage(context),
            SizedBox(height: 2 * scale),
            Padding(
              padding: EdgeInsets.only(left: 2 * scale),
              child: SizedBox(height: 50 * scale, child: _buildInfo(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    final palette = context.appPalette;
    return SizedBox(
      width: double.infinity,
      height: 266 * scale,
      child: Container(
        decoration: BoxDecoration(
          color: palette.surfaceMuted,
          borderRadius: BorderRadius.circular(5 * scale),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5 * scale),
                child: AppImage(
                  imageUrl: product.image,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.fill,
                  alignment: Alignment.center,
                ),
              ),
            ),
            Positioned(
              right: 12 * scale,
              top: 12 * scale,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onMenu,
                child: Padding(
                  padding: EdgeInsets.all(6 * scale),
                  child: AdaptiveDotsMenu(
                    dotSize: 3.8 * scale,
                    dotsOnDark: product.dotsOnDark,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfo(BuildContext context) {
    final palette = context.appPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          product.title,
          style: TextStyle(
            fontSize: 13.5 * scale,
            height: 1.08,
            fontWeight: FontWeight.w500,
            color: palette.ink,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: 1 * scale),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                product.price,
                style: TextStyle(
                  fontSize: 13.5 * scale,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                ),
              ),
            ),
            SizedBox(width: 6 * scale),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _IconTapTarget(
                  onTap: onLike,
                  child: _OutlineHeartIcon(
                    size: 23 * scale,
                    isFilled: product.isLiked,
                  ),
                ),
                SizedBox(width: 4 * scale),
                _IconTapTarget(
                  onTap: onShare,
                  child: _PaperPlaneIcon(size: 23 * scale),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _IconTapTarget extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  const _IconTapTarget({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(width: 28, height: 28, child: Center(child: child)),
    );
  }
}

// ============================================================================
// PRODUCT DETAILS SHEET
// ============================================================================

class ProductDetailsSheet extends StatelessWidget {
  final Product product;
  final VoidCallback onLike;
  final VoidCallback onAddToCart;
  final VoidCallback onContactSeller;
  final VoidCallback onShare;

  const ProductDetailsSheet({
    super.key,
    required this.product,
    required this.onLike,
    required this.onAddToCart,
    required this.onContactSeller,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final palette = context.appPalette;

    return Container(
      height: screenHeight * 0.93,
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          // Content
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Hero Image
                  _buildHeroImage(context),

                  // Title Row: heart + title + send
                  _buildTitleRow(context),

                  // Price
                  _buildPrice(context),

                  // Seller Card
                  _buildSellerCard(context),

                  // CTA Button
                  _buildCTAButton(context, bottomInset),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroImage(BuildContext context) {
    return Stack(
      children: [
        // Image
        SizedBox(
          width: double.infinity,
          height: 410,
          child: AppImage(
            imageUrl: product.image,
            fit: BoxFit.fill,
            alignment: Alignment.center,
          ),
        ),

        // Back button
        Positioned(
          left: 18,
          top: 18,
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                size: 18,
                color: Color(0xFF111111),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTitleRow(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          // Heart
          GestureDetector(
            onTap: onLike,
            child: _OutlineHeartIcon(size: 26, isFilled: product.isLiked),
          ),

          // Title
          Expanded(
            child: Text(
              product.detailTitle.isNotEmpty
                  ? product.detailTitle
                  : product.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: palette.ink,
              ),
            ),
          ),

          // Send
          GestureDetector(onTap: onShare, child: _PaperPlaneIcon(size: 26)),
        ],
      ),
    );
  }

  Widget _buildPrice(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Text(
        product.price,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: context.appPalette.ink,
        ),
      ),
    );
  }

  Widget _buildSellerCard(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.surfaceMuted,
              ),
              child: Icon(Icons.person_outline, size: 24, color: palette.muted),
            ),
            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Продавец',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.star, size: 12, color: palette.ink),
                      const SizedBox(width: 4),
                      Text(
                        '4.8',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: palette.ink,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '126 отзывов',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: palette.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${product.brand.toLowerCase().replaceAll(' ', '')}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: palette.muted,
                    ),
                  ),
                ],
              ),
            ),

            // Chevron
            Icon(Icons.chevron_right, size: 22, color: palette.muted),
          ],
        ),
      ),
    );
  }

  Widget _buildCTAButton(BuildContext context, double bottomInset) {
    final palette = context.appPalette;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 22, 20, 24 + bottomInset),
      child: GestureDetector(
        onTap: onContactSeller,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: palette.ink,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              'НАПИСАТЬ ПРОДАВЦУ',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: 2.5,
                color: palette.surface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogFilters {
  String category = '';
  String size = '';
  int? minPrice;
  int? maxPrice;
  String brand = '';
  String condition = '';
  String audience = '';
  String delivery = '';
  String color = '';
  String material = '';
  String pattern = '';
  String fit = '';
  String style = '';

  int get activeCount => <Object?>[
    category,
    size,
    minPrice,
    maxPrice,
    brand,
    condition,
    audience,
    delivery,
    color,
    material,
    pattern,
    fit,
    style,
  ].where((value) => value != null && value.toString().isNotEmpty).length;

  _CatalogFilters clone() => _CatalogFilters()..replaceWith(this);

  void replaceWith(_CatalogFilters other) {
    category = other.category;
    size = other.size;
    minPrice = other.minPrice;
    maxPrice = other.maxPrice;
    brand = other.brand;
    condition = other.condition;
    audience = other.audience;
    delivery = other.delivery;
    color = other.color;
    material = other.material;
    pattern = other.pattern;
    fit = other.fit;
    style = other.style;
  }

  void clear() => replaceWith(_CatalogFilters());
}

class _CatalogFilterSheet extends StatefulWidget {
  const _CatalogFilterSheet({
    required this.initial,
    required this.products,
    required this.onApply,
    required this.onReset,
  });

  final _CatalogFilters initial;
  final List<Product> products;
  final ValueChanged<_CatalogFilters> onApply;
  final VoidCallback onReset;

  @override
  State<_CatalogFilterSheet> createState() => _CatalogFilterSheetState();
}

class _CatalogFilterSheetState extends State<_CatalogFilterSheet> {
  late final _CatalogFilters _value = widget.initial.clone();
  late final TextEditingController _minPrice = TextEditingController(
    text: _value.minPrice?.toString() ?? '',
  );
  late final TextEditingController _maxPrice = TextEditingController(
    text: _value.maxPrice?.toString() ?? '',
  );

  @override
  void dispose() {
    _minPrice.dispose();
    _maxPrice.dispose();
    super.dispose();
  }

  List<CatalogOption> get _sizes {
    final values =
        widget.products
            .map((product) => product.size.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return values.map((value) => CatalogOption(value, value)).toList();
  }

  List<CatalogOption> get _brands {
    final values =
        widget.products
            .map((product) => product.brand.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return values.map((value) => CatalogOption(value, value)).toList();
  }

  String _optionName(
    String value,
    List<CatalogOption> options, {
    required String emptyLabel,
  }) {
    if (value.isEmpty) return emptyLabel;
    for (final option in options) {
      if (option.id == value) return option.name;
    }
    return value;
  }

  Future<void> _selectOption({
    required String title,
    required String current,
    required List<CatalogOption> options,
    required ValueChanged<String> onSelected,
    String emptyLabel = 'Любой',
  }) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (context) => _AppActionSheet(
        title: title,
        child: Column(
          children: [
            _SheetOption(
              label: emptyLabel,
              isSelected: current.isEmpty,
              onTap: () => Navigator.pop(context, ''),
            ),
            for (final option in options)
              _SheetOption(
                label: option.name,
                isSelected: current == option.id,
                onTap: () => Navigator.pop(context, option.id),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => onSelected(selected));
  }

  Future<void> _editPrice() async {
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (context) => AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _AppActionSheet(
          title: 'Цена',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _PriceField(label: 'От', controller: _minPrice),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PriceField(label: 'До', controller: _maxPrice),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _SheetButton(
                      label: 'Очистить',
                      isPrimary: false,
                      onTap: () {
                        _minPrice.clear();
                        _maxPrice.clear();
                        Navigator.pop(context, true);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SheetButton(
                      label: 'Готово',
                      isPrimary: true,
                      onTap: () => Navigator.pop(context, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || applied != true) return;
    setState(() {});
  }

  String get _priceLabel {
    final min = int.tryParse(_minPrice.text);
    final max = int.tryParse(_maxPrice.text);
    if (min == null && max == null) return 'Любая';
    if (min != null && max != null) return '$min–$max ₽';
    if (min != null) return 'от $min ₽';
    return 'до $max ₽';
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _CompactFilterRow(
        title: 'Категория',
        value: _optionName(
          _value.category,
          ListingCatalogs.finalCategories,
          emptyLabel: 'Все',
        ),
        onTap: () => _selectOption(
          title: 'Категория',
          current: _value.category,
          options: ListingCatalogs.finalCategories,
          emptyLabel: 'Все',
          onSelected: (value) => _value.category = value,
        ),
      ),
      _CompactFilterRow(
        title: 'Размер',
        value: _optionName(_value.size, _sizes, emptyLabel: 'Любой'),
        onTap: () => _selectOption(
          title: 'Размер',
          current: _value.size,
          options: _sizes,
          onSelected: (value) => _value.size = value,
        ),
      ),
      _CompactFilterRow(title: 'Цена', value: _priceLabel, onTap: _editPrice),
      _CompactFilterRow(
        title: 'Бренд',
        value: _optionName(_value.brand, _brands, emptyLabel: 'Все'),
        onTap: () => _selectOption(
          title: 'Бренд',
          current: _value.brand,
          options: _brands,
          emptyLabel: 'Все',
          onSelected: (value) => _value.brand = value,
        ),
      ),
      _CompactFilterRow(
        title: 'Цвет',
        value: _optionName(
          _value.color,
          ListingCatalogs.colors,
          emptyLabel: 'Любой',
        ),
        onTap: () => _selectOption(
          title: 'Цвет',
          current: _value.color,
          options: ListingCatalogs.colors,
          onSelected: (value) => _value.color = value,
        ),
      ),
      _CompactFilterRow(
        title: 'Состояние',
        value: _optionName(
          _value.condition,
          ListingCatalogs.conditions,
          emptyLabel: 'Любое',
        ),
        onTap: () => _selectOption(
          title: 'Состояние',
          current: _value.condition,
          options: ListingCatalogs.conditions,
          emptyLabel: 'Любое',
          onSelected: (value) => _value.condition = value,
        ),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: _SheetButton(
              label: 'Сбросить',
              isPrimary: false,
              onTap: widget.onReset,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SheetButton(
              label: 'Применить',
              isPrimary: true,
              onTap: () {
                var minPrice = int.tryParse(_minPrice.text);
                var maxPrice = int.tryParse(_maxPrice.text);
                if (minPrice != null &&
                    maxPrice != null &&
                    minPrice > maxPrice) {
                  final swap = minPrice;
                  minPrice = maxPrice;
                  maxPrice = swap;
                }
                _value
                  ..minPrice = minPrice
                  ..maxPrice = maxPrice
                  ..audience = ''
                  ..delivery = ''
                  ..material = ''
                  ..pattern = ''
                  ..fit = ''
                  ..style = '';
                widget.onApply(_value);
              },
            ),
          ),
        ],
      ),
    ],
  );
}

class _CompactFilterRow extends StatelessWidget {
  const _CompactFilterRow({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return InkWell(
      onTap: onTap,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: palette.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: palette.ink,
                ),
              ),
            ),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: palette.muted),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 17, color: palette.muted),
          ],
        ),
      ),
    );
  }
}

class _PriceField extends StatelessWidget {
  const _PriceField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label, suffixText: '₽'),
  );
}

class _AppActionSheet extends StatelessWidget {
  final String title;
  final Widget child;

  const _AppActionSheet({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final palette = context.appPalette;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: 16),
              child,
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final IconData? icon;
  final VoidCallback onTap;

  const _SheetOption({
    required this.label,
    required this.onTap,
    this.isSelected = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 53,
        child: Row(
          children: [
            if (icon != null) ...[
              SizedBox(
                width: 22,
                child: Icon(icon, size: 21, color: palette.ink),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: palette.ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected) Icon(Icons.check, size: 20, color: palette.ink),
          ],
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  final String label;
  final bool isPrimary;
  final VoidCallback onTap;

  const _SheetButton({
    required this.label,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: isPrimary ? palette.ink : palette.surface,
          border: Border.all(color: isPrimary ? palette.ink : palette.border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isPrimary ? palette.surface : palette.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineHeartIcon extends StatelessWidget {
  final double size;
  final bool isFilled;

  const _OutlineHeartIcon({required this.size, required this.isFilled});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _HeartPainter(
          isFilled: isFilled,
          color: context.appPalette.ink,
        ),
      ),
    );
  }
}

class AdaptiveDotsMenu extends StatelessWidget {
  final double dotSize;
  final bool dotsOnDark;

  const AdaptiveDotsMenu({
    super.key,
    required this.dotSize,
    required this.dotsOnDark,
  });

  @override
  Widget build(BuildContext context) {
    final height = dotSize * 3 + dotSize * 0.95 * 2;
    return SizedBox(
      width: dotSize,
      height: height,
      child: CustomPaint(
        painter: _InvertingDotsPainter(
          dotSize: dotSize,
          sourceHint: dotsOnDark,
        ),
      ),
    );
  }
}

class _InvertingDotsPainter extends CustomPainter {
  const _InvertingDotsPainter({
    required this.dotSize,
    required this.sourceHint,
  });

  final double dotSize;
  final bool sourceHint;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.saveLayer(rect, Paint()..blendMode = BlendMode.difference);

    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final radius = dotSize / 2;
    final step = dotSize * 1.95;
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(size.width / 2, radius + step * i),
        radius,
        paint,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _InvertingDotsPainter oldDelegate) {
    return oldDelegate.dotSize != dotSize ||
        oldDelegate.sourceHint != sourceHint;
  }
}

class _PaperPlaneIcon extends StatelessWidget {
  final double size;

  const _PaperPlaneIcon({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PaperPlanePainter(color: context.appPalette.ink),
      ),
    );
  }
}

class _HeartPainter extends CustomPainter {
  final bool isFilled;
  final Color color;

  _HeartPainter({required this.isFilled, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.50, size.height * 0.82)
      ..cubicTo(
        size.width * 0.18,
        size.height * 0.62,
        size.width * 0.10,
        size.height * 0.43,
        size.width * 0.16,
        size.height * 0.29,
      )
      ..cubicTo(
        size.width * 0.22,
        size.height * 0.15,
        size.width * 0.40,
        size.height * 0.13,
        size.width * 0.50,
        size.height * 0.29,
      )
      ..cubicTo(
        size.width * 0.60,
        size.height * 0.13,
        size.width * 0.78,
        size.height * 0.15,
        size.width * 0.84,
        size.height * 0.29,
      )
      ..cubicTo(
        size.width * 0.90,
        size.height * 0.43,
        size.width * 0.82,
        size.height * 0.62,
        size.width * 0.50,
        size.height * 0.82,
      );

    final paint = Paint()
      ..color = color
      ..style = isFilled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HeartPainter oldDelegate) {
    return oldDelegate.isFilled != isFilled || oldDelegate.color != color;
  }
}

class _PaperPlanePainter extends CustomPainter {
  const _PaperPlanePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.13, size.height * 0.50)
      ..lineTo(size.width * 0.86, size.height * 0.17)
      ..lineTo(size.width * 0.68, size.height * 0.84)
      ..lineTo(size.width * 0.48, size.height * 0.58)
      ..lineTo(size.width * 0.13, size.height * 0.50)
      ..lineTo(size.width * 0.48, size.height * 0.58)
      ..lineTo(size.width * 0.86, size.height * 0.17);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PaperPlanePainter oldDelegate) =>
      oldDelegate.color != color;
}
