import 'package:flutter/material.dart';

import '../core/app_typography.dart';
import '../features/chat/chat_actions.dart';
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
  final Future<void> Function(Product product) onCreateDeliveryOrder;
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

  const CatalogScreen({
    super.key,
    required this.scale,
    required this.sidePadding,
    required this.products,
    required this.onToggleLike,
    required this.onHideProduct,
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
        image: 'assets/products/try_photo.png',
        title: '',
        subtitle: '',
        buttonText: 'ПОПРОБОВАТЬ',
        onTap: _openVisualSearch,
      ),
      PromoBanner(
        image: 'assets/mock/outfit_hero.jpg',
        title: 'РОПНО',
        subtitle: 'тататататат та тата тата\nтаа, та та тата?',
        buttonText: 'ПЕРЕЙТИ',
        onTap: () => _showSnackBar('Переход по промо-баннеру'),
      ),
      PromoBanner(
        image: 'assets/mock/post_8.jpg',
        title: 'ДЕНИМ',
        subtitle: 'Свободные силуэты, винтажные оттенки и чистые линии',
        buttonText: 'ПЕРЕЙТИ',
        onTap: () => _showSnackBar('Переход по промо-баннеру'),
      ),
    ];
  }

  List<Product> get _visibleProducts {
    final products = widget.products
        .where((product) => !product.isHidden)
        .toList();
    switch (_selectedSort) {
      case 'Сначала дешёвые':
        products.sort((a, b) => a.priceValue.compareTo(b.priceValue));
        break;
      case 'Сначала дорогие':
        products.sort((a, b) => b.priceValue.compareTo(a.priceValue));
        break;
      case 'Сначала новые':
        products.sort((a, b) => b.id.compareTo(a.id));
        break;
      case 'Популярные':
        products.sort((a, b) => a.title.compareTo(b.title));
        break;
      case 'По рекомендациям':
      default:
        break;
    }
    return products;
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
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
    return (screenWidth * 1.32).clamp(500.0, 540.0).toDouble();
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
    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.08),
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
    return Material(
      color: const Color(0xFFF2F2F3),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _showSnackBar('Поиск'),
              child: Padding(
                padding: const EdgeInsets.only(left: 14, right: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search_rounded,
                      size: 21,
                      color: Color(0xFF0B0B0C),
                    ),
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
                          color: const Color(0xFF74747C),
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
              color: const Color(0xFF0B0B0C),
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _openVisualSearch,
                child: const SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(
                    Icons.center_focus_strong_rounded,
                    size: 20,
                    color: Colors.white,
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
                        color: isActive
                            ? const Color(0xFF050505)
                            : const Color(0xFF706E82),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      height: 2,
                      width: isActive ? _tabs[index].length * 7.1 * scale : 0,
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF050505)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Container(height: 1, color: const Color(0xFFE7E7EA)),
      ],
    );
  }

  Widget _buildFilterRow(double scale) {
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
                    'Фильтр',
                    style: TextStyle(
                      fontSize: 14.5 * scale,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF0B0B0B),
                    ),
                  ),
                  SizedBox(width: 10 * scale),
                  Icon(
                    Icons.tune,
                    size: 21 * scale,
                    color: const Color(0xFF111111),
                  ),
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
                      color: const Color(0xFF0B0B0B),
                    ),
                  ),
                  SizedBox(width: 4 * scale),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 17 * scale,
                    color: const Color(0xFF111111),
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
          onProductTap: _showProductDetails,
          onToggleLike: widget.onToggleLike,
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
    widget.onProductViewed(product);
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
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
            ),
            onLike: () => _toggleLike(product.id),
            onAddToCart: () => _showSnackBar('Добавлено в корзину'),
            onOpenSeller: () => _openSellerProfile(product),
            onOpenReviews: () => _openReviewsForProduct(product),
            loadSellerProfile: widget.onLoadSellerProfile,
            loadReviews: widget.onLoadReviews,
            onToggleRelatedLike: widget.onToggleLike,
            relatedProducts: _relatedProductsFor(product),
            onRelatedProductTap: _showProductDetails,
            deliveryProfile: widget.deliveryProfile,
            onSaveDeliveryProfile: widget.onSaveDeliveryProfile,
            onCreateDeliveryOrder: () => widget.onCreateDeliveryOrder(product),
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
      ),
    );
  }

  List<Product> _relatedProductsFor(Product product) {
    return widget.products
        .where(
          (item) =>
              item.id != product.id &&
              !item.isHidden &&
              item.category == product.category,
        )
        .take(8)
        .toList();
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

  void _showFilterSheet() {
    _showAppSheet(
      title: 'Фильтр',
      child: Column(
        children: [
          const _FilterRow(title: 'Категория', value: 'Все'),
          const _FilterRow(title: 'Размер', value: 'Любой'),
          const _FilterRow(title: 'Цена', value: 'Любая'),
          const _FilterRow(title: 'Бренд', value: 'Все'),
          const _FilterRow(title: 'Цвет', value: 'Любой'),
          const _FilterRow(title: 'Состояние', value: 'Любое'),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _SheetButton(
                  label: 'Сбросить',
                  isPrimary: false,
                  onTap: () {
                    Navigator.pop(context);
                    _showSnackBar('Фильтры сброшены');
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SheetButton(
                  label: 'Применить',
                  isPrimary: true,
                  onTap: () {
                    Navigator.pop(context);
                    _showSnackBar('Фильтры применены');
                  },
                ),
              ),
            ],
          ),
        ],
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
            label: 'Не рекомендовать такие вещи',
            icon: Icons.visibility_off_outlined,
            onTap: () {
              Navigator.pop(context);
              _showSnackBar('Будем показывать меньше похожих товаров');
            },
          ),
          _SheetOption(
            label: 'Скрыть товар',
            icon: Icons.block_outlined,
            onTap: () {
              Navigator.pop(context);
              _hideProduct(product.id);
              _showSnackBar('Товар скрыт');
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
                onTap: () {
                  Navigator.pop(context);
                  _showSnackBar('Жалоба отправлена');
                },
              ),
            ],
          );
        },
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
          ),
          deliveryProfile: widget.deliveryProfile,
          onSaveProfile: widget.onSaveDeliveryProfile,
          onSubmitOrder: () => widget.onCreateDeliveryOrder(product),
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
            _buildImage(),
            SizedBox(height: 2 * scale),
            Padding(
              padding: EdgeInsets.only(left: 2 * scale),
              child: SizedBox(height: 50 * scale, child: _buildInfo()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    return SizedBox(
      width: double.infinity,
      height: 266 * scale,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8F9),
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

  Widget _buildInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          product.title,
          style: TextStyle(
            fontSize: 13.5 * scale,
            height: 1.08,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF070707),
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
                  color: const Color(0xFF070707),
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

  const ProductDetailsSheet({
    super.key,
    required this.product,
    required this.onLike,
    required this.onAddToCart,
    required this.onContactSeller,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      height: screenHeight * 0.93,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
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
                  _buildTitleRow(),

                  // Price
                  _buildPrice(),

                  // Seller Card
                  _buildSellerCard(),

                  // CTA Button
                  _buildCTAButton(bottomInset),
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

  Widget _buildTitleRow() {
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
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111111),
              ),
            ),
          ),

          // Send
          GestureDetector(onTap: () {}, child: _PaperPlaneIcon(size: 26)),
        ],
      ),
    );
  }

  Widget _buildPrice() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Text(
        product.price,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Color(0xFF111111),
        ),
      ),
    );
  }

  Widget _buildSellerCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE7E7EA)),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFF2F2F7),
              ),
              child: const Icon(
                Icons.person_outline,
                size: 24,
                color: Color(0xFF8E8E93),
              ),
            ),
            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Продавец',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111111),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(
                        Icons.star,
                        size: 12,
                        color: Color(0xFF111111),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        '4.8',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111111),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '126 отзывов',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF8F8F94),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${product.brand.toLowerCase().replaceAll(' ', '')}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF8F8F94),
                    ),
                  ),
                ],
              ),
            ),

            // Chevron
            const Icon(Icons.chevron_right, size: 22, color: Color(0xFFC7C7CC)),
          ],
        ),
      ),
    );
  }

  Widget _buildCTAButton(double bottomInset) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 22, 20, 24 + bottomInset),
      child: GestureDetector(
        onTap: onContactSeller,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Center(
            child: Text(
              'НАПИСАТЬ ПРОДАВЦУ',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: 2.5,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppActionSheet extends StatelessWidget {
  final String title;
  final Widget child;

  const _AppActionSheet({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0B0B0B),
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

class _FilterRow extends StatelessWidget {
  final String title;
  final String value;

  const _FilterRow({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 51,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE7E7EA))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFF0B0B0B),
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13.5, color: Color(0xFF8F8F94)),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, size: 16, color: Color(0xFFC7C7CC)),
        ],
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
                child: Icon(icon, size: 21, color: const Color(0xFF0B0B0B)),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF0B0B0B),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected)
              const Icon(Icons.check, size: 20, color: Color(0xFF0B0B0B)),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: isPrimary ? Colors.black : Colors.white,
          border: Border.all(
            color: isPrimary ? Colors.black : const Color(0xFFE7E7EA),
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isPrimary ? Colors.white : const Color(0xFF0B0B0B),
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
      child: CustomPaint(painter: _HeartPainter(isFilled: isFilled)),
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
      child: CustomPaint(painter: _PaperPlanePainter()),
    );
  }
}

class _HeartPainter extends CustomPainter {
  final bool isFilled;

  _HeartPainter({required this.isFilled});

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
      ..color = const Color(0xFF050505)
      ..style = isFilled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HeartPainter oldDelegate) {
    return oldDelegate.isFilled != isFilled;
  }
}

class _PaperPlanePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF050505)
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
