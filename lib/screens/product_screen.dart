import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/app_profile.dart';
import '../models/product.dart';
import '../models/profile_feature.dart';
import '../services/image_download_service.dart';
import '../features/listing_publish/data/listing_catalogs.dart';
import '../widgets/app_image.dart';

class ProductDetailData {
  const ProductDetailData({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.priceValue,
    required this.image,
    required this.images,
    required this.category,
    required this.brand,
    required this.color,
    required this.sellerName,
    required this.sellerHandle,
    required this.size,
    required this.condition,
    required this.location,
    required this.isLiked,
    this.shippingAddress = '',
    this.canPurchase = true,
  });

  final String id;
  final String title;
  final String description;
  final String price;
  final int priceValue;
  final String image;
  final List<String> images;
  final String category;
  final String brand;
  final String color;
  final String sellerName;
  final String sellerHandle;
  final String size;
  final String condition;
  final String location;
  final bool isLiked;
  final String shippingAddress;
  final bool canPurchase;
}

class ProductScreen extends StatefulWidget {
  const ProductScreen({
    super.key,
    required this.product,
    required this.onLike,
    required this.onAddToCart,
    required this.onContactSeller,
    this.onShare,
    required this.onOpenSeller,
    required this.onOpenReviews,
    required this.relatedProducts,
    required this.onRelatedProductTap,
    required this.deliveryProfile,
    required this.onSaveDeliveryProfile,
    required this.onCreateDeliveryOrder,
    this.sourceProduct,
    this.loadSellerProfile,
    this.loadReviews,
    this.onToggleRelatedLike,
    this.isPreview = false,
  });

  final Product? sourceProduct;
  final ProductDetailData product;
  final VoidCallback onLike;
  final VoidCallback onAddToCart;
  final VoidCallback onContactSeller;
  final VoidCallback? onShare;
  final VoidCallback onOpenSeller;
  final VoidCallback onOpenReviews;
  final Future<SellerProfile?> Function(Product product)? loadSellerProfile;
  final Future<List<SellerReview>> Function(String sellerId)? loadReviews;
  final Future<void> Function(String productId)? onToggleRelatedLike;
  final bool isPreview;
  final List<Product> relatedProducts;
  final ValueChanged<Product> onRelatedProductTap;
  final DeliveryProfile deliveryProfile;
  final Future<void> Function(DeliveryProfile profile) onSaveDeliveryProfile;
  final Future<void> Function() onCreateDeliveryOrder;

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen>
    with TickerProviderStateMixin {
  static const _openDuration = Duration(milliseconds: 500);
  static const _expandDuration = Duration(milliseconds: 280);
  static const _scrollRange = 180.0;
  static const _spacingMin = 16.0;
  static const _spacingMax = 30.0;
  static const _topGapCard = 16.0;
  static const _topRadiusCard = 28.0;
  static const _bottomRadiusCard = 24.0;

  late final AnimationController _openController;
  late final AnimationController _expandController;
  late final Animation<Offset> _slide;
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0;
  bool _isClosing = false;
  bool _isLiked = false;
  bool _isSellerSubscribed = false;
  SellerProfile? _sellerProfile;
  int _reviewCount = 0;
  double _reviewRating = 0;
  int _followersDelta = 0;
  bool _didShowUnavailableSheet = false;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.product.isLiked;
    _openController = AnimationController(duration: _openDuration, vsync: this);
    _expandController = AnimationController(
      duration: _expandDuration,
      vsync: this,
    );
    _expandController.addListener(_onExpandTick);
    _slide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_openController);
    _openController.forward();
    _scrollController.addListener(_onScroll);
    _openController.addStatusListener(_onProductOpenStatus);
    _loadSellerStats();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.product.canPurchase) return;
      _showUnavailablePurchaseSheet();
    });
  }

  void _onExpandTick() => setState(() {});

  void _onScroll() {
    final offset = _scrollController.offset;
    if ((offset - _scrollOffset).abs() > 1) {
      setState(() => _scrollOffset = offset);
    }
  }

  void _onProductOpenStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && _isClosing && mounted) {
      _isClosing = false;
      Navigator.of(context, rootNavigator: true).maybePop();
    }
  }

  void _closeWithAnimation() {
    if (_isClosing) return;
    _isClosing = true;
    _openController.reverse();
  }

  Future<void> _openImageViewer(int initialPage) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (context) => _ProductImageViewer(
            images: widget.product.images.isNotEmpty
                ? widget.product.images
                : [widget.product.image],
            initialPage: initialPage,
          ),
        ),
      );

  void _toggleWishlist() {
    setState(() => _isLiked = !_isLiked);
    widget.onLike();
  }

  Future<void> _loadSellerStats() async {
    final sourceProduct = widget.sourceProduct;
    final loadSellerProfile = widget.loadSellerProfile;
    final loadReviews = widget.loadReviews;
    if (sourceProduct == null ||
        loadSellerProfile == null ||
        loadReviews == null) {
      return;
    }
    final profile = await loadSellerProfile(sourceProduct);
    final sellerId = profile?.id.trim().isNotEmpty == true
        ? profile!.id
        : sourceProduct.ownerId;
    final reviews = sellerId.trim().isEmpty
        ? const <SellerReview>[]
        : await loadReviews(sellerId);
    if (!mounted) return;
    setState(() {
      _sellerProfile = profile;
      _reviewCount = reviews.length;
      _reviewRating = reviews.isEmpty
          ? 0
          : reviews.fold<int>(0, (sum, review) => sum + review.rating) /
                reviews.length;
    });
  }

  void _toggleSellerSubscription() {
    setState(() {
      _isSellerSubscribed = !_isSellerSubscribed;
      _followersDelta += _isSellerSubscribed ? 1 : -1;
    });
  }

  Future<void> _openDeliveryCheckout() async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (context) => DeliveryCheckoutScreen(
          product: widget.product,
          deliveryProfile: widget.deliveryProfile,
          onSaveProfile: widget.onSaveDeliveryProfile,
          onSubmitOrder: widget.onCreateDeliveryOrder,
        ),
      ),
    );
  }

  void _showUnavailablePurchaseSheet() {
    if (_didShowUnavailableSheet) return;
    _didShowUnavailableSheet = true;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewPadding.bottom;
        return Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + bottomInset),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E4),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Упс, этот товар не продается',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111111),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Но вы можете написать продавцу и уточнить, готов ли он продать эту вещь.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: Colors.black.withValues(alpha: 0.62),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(sheetContext, rootNavigator: true).pop();
                    widget.onContactSeller();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  child: const Text(
                    'Написать продавцу',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ).whenComplete(() => _didShowUnavailableSheet = false);
  }

  double get _spacing {
    final t = (_scrollOffset / _scrollRange).clamp(0.0, 1.0);
    return _spacingMin + (_spacingMax - _spacingMin) * (1 - t);
  }

  @override
  void dispose() {
    _expandController.removeListener(_onExpandTick);
    _openController.removeStatusListener(_onProductOpenStatus);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _expandController.dispose();
    _openController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final hairline = 1 / MediaQuery.of(context).devicePixelRatio;
    final tExpand = _expandController.value;
    final topGap = widget.isPreview
        ? 0.0
        : (MediaQuery.of(context).viewPadding.top + _topGapCard) *
              (1 - tExpand);
    final topRadius = widget.isPreview ? 0.0 : _topRadiusCard * (1 - tExpand);
    final bottomRadius = widget.isPreview
        ? 0.0
        : _bottomRadiusCard * (1 - tExpand);
    final spacing = _spacing;
    final t = (_scrollOffset / _scrollRange).clamp(0.0, 1.0);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final detailsStartOffset = screenHeight * 0.34;
    final sellerTopExtra = detailsStartOffset * (1 - t);
    final titlePriceSpacing = spacing + 28.0 * (1 - t);
    final canPurchase = product.canPurchase;
    final sellerRating = _reviewCount == 0 ? 0.0 : _reviewRating;
    final sellerFollowers =
        ((_sellerProfile?.followersCount ?? 0) + _followersDelta)
            .clamp(0, 1 << 31)
            .toInt();
    final priceText = canPurchase ? product.price : 'Не продается';
    final messageButtonText = canPurchase
        ? 'Написать сообщение'
        : 'Уточнить у продавца';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SlideTransition(
        position: _slide,
        child: Padding(
          padding: EdgeInsets.only(top: topGap),
          child: ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(topRadius),
              topRight: Radius.circular(topRadius),
              bottomLeft: Radius.circular(bottomRadius),
              bottomRight: Radius.circular(bottomRadius),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.white],
                        stops: [0.0, 0.12],
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      bottom: false,
                      child: CustomScrollView(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        slivers: [
                          SliverToBoxAdapter(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(28),
                              ),
                              child: _HeroImageGallery(
                                gallery: product.images.isNotEmpty
                                    ? product.images
                                    : [product.image],
                                onOpen: _openImageViewer,
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Container(
                              padding: EdgeInsets.fromLTRB(
                                18,
                                spacing,
                                18,
                                spacing,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border(
                                  top: BorderSide(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    width: hairline,
                                  ),
                                ),
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 54,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          product.title,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            letterSpacing: 0.15,
                                            height: 1.2,
                                          ),
                                        ),
                                        SizedBox(height: titlePriceSpacing),
                                        Text(
                                          priceText,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.15,
                                            height: 1.0,
                                            fontFeatures: [
                                              FontFeature.tabularFigures(),
                                              FontFeature.liningFigures(),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Positioned(
                                          left: 18,
                                          child: _InlineIcon(
                                            icon: _isLiked
                                                ? CupertinoIcons.heart_fill
                                                : CupertinoIcons.heart,
                                            onTap: _toggleWishlist,
                                            isWishlist: true,
                                          ),
                                        ),
                                        Positioned(
                                          right: 18,
                                          child: _InlineIcon(
                                            icon: CupertinoIcons.paperplane,
                                            onTap:
                                                widget.onShare ??
                                                widget.onContactSeller,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Container(
                              color: Colors.white,
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  18,
                                  (spacing * 0.5).clamp(12.0, 28.0) +
                                      sellerTopExtra,
                                  18,
                                  spacing,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    _ProductDatabaseDescription(
                                      product: product,
                                      sourceProduct: widget.sourceProduct,
                                      hairline: hairline,
                                    ),
                                    _DeliveryAddress(
                                      address: product.shippingAddress,
                                      fallbackCity: product.location,
                                    ),
                                    SizedBox(height: spacing),
                                    _BuyDeliveryBlock(
                                      onTap: _openDeliveryCheckout,
                                    ),
                                    SizedBox(height: spacing),
                                    _SellerCard(
                                      hairline: hairline,
                                      name: product.sellerName,
                                      handle: product.sellerHandle,
                                      rating: sellerRating.toDouble(),
                                      reviews: _reviewCount,
                                      followers: sellerFollowers,
                                      isSubscribed: _isSellerSubscribed,
                                      onSubscribe: _toggleSellerSubscription,
                                      onTap: widget.onOpenSeller,
                                      onReviewsTap: widget.onOpenReviews,
                                    ),
                                    SizedBox(height: spacing),
                                    _RelatedProductsSection(
                                      products: widget.relatedProducts,
                                      onProductTap: widget.onRelatedProductTap,
                                      onToggleLike: widget.onToggleRelatedLike,
                                    ),
                                    SizedBox(height: spacing),
                                    const SafeArea(
                                      top: false,
                                      child: SizedBox(height: 2),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height: widget.isPreview
                                  ? 16
                                  : 52 +
                                        16 +
                                        MediaQuery.of(context).padding.bottom,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!widget.isPreview)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      top: false,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                        color: Colors.transparent,
                        child: SizedBox(
                          height: 52,
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: canPurchase
                                ? widget.onContactSeller
                                : _showUnavailablePurchaseSheet,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            child: Text(
                              messageButtonText.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!widget.isPreview)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: SafeArea(
                      top: false,
                      bottom: false,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          10,
                          MediaQuery.of(context).viewPadding.top + 8,
                          10,
                          8,
                        ),
                        child: Row(
                          children: [
                            _TopIcon(
                              icon: CupertinoIcons.back,
                              onTap: _closeWithAnimation,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroImageGallery extends StatefulWidget {
  const _HeroImageGallery({required this.gallery, required this.onOpen});

  final List<String> gallery;
  final ValueChanged<int> onOpen;

  @override
  State<_HeroImageGallery> createState() => _HeroImageGalleryState();
}

class _HeroImageGalleryState extends State<_HeroImageGallery> {
  int _currentPage = 0;
  late final PageController _pageController;
  late final List<String> _gallery;

  @override
  void initState() {
    super.initState();
    _gallery = List.unmodifiable(widget.gallery);
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemCount: _gallery.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onOpen(index),
                child: Container(
                  color: const Color(0xFFD9D9DB),
                  child: AppImage(
                    key: ValueKey(_gallery[index]),
                    imageUrl: _gallery[index],
                    fit: BoxFit.fill,
                    alignment: Alignment.center,
                  ),
                ),
              );
            },
          ),
          if (_gallery.length > 1)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _gallery.length,
                  (index) => Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentPage == index
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProductImageViewer extends StatefulWidget {
  const _ProductImageViewer({required this.images, required this.initialPage});

  final List<String> images;
  final int initialPage;

  @override
  State<_ProductImageViewer> createState() => _ProductImageViewerState();
}

class _ProductImageViewerState extends State<_ProductImageViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialPage,
  );
  late int _currentPage = widget.initialPage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    try {
      await ImageDownloadService.save(
        widget.images[_currentPage],
        name: 'clothes_product_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Фото сохранено в галерею')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить фото')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: widget.images.length,
          onPageChanged: (index) => setState(() => _currentPage = index),
          itemBuilder: (context, index) => InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: AppImage(
                imageUrl: widget.images[index],
                fit: BoxFit.contain,
                alignment: Alignment.center,
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(CupertinoIcons.back, color: Colors.white),
                  ),
                  Expanded(
                    child: Center(
                      child: widget.images.length > 1
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 6,
                                ),
                                child: Text(
                                  '${_currentPage + 1} / ${widget.images.length}',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Скачать фото',
                    onPressed: _download,
                    icon: const Icon(
                      CupertinoIcons.arrow_down_to_line,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _TopIcon extends StatelessWidget {
  const _TopIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 54,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        child: Center(
          child: Icon(
            icon,
            size: 26,
            color: Colors.black.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}

class _InlineIcon extends StatelessWidget {
  const _InlineIcon({
    required this.icon,
    required this.onTap,
    this.isWishlist = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isWishlist;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        child: Center(
          child: Icon(
            icon,
            size: 32,
            color: isWishlist && icon == CupertinoIcons.heart_fill
                ? Colors.red
                : Colors.black.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}

class _SellerCard extends StatelessWidget {
  const _SellerCard({
    required this.hairline,
    required this.name,
    required this.handle,
    required this.rating,
    required this.reviews,
    required this.followers,
    required this.isSubscribed,
    required this.onSubscribe,
    required this.onTap,
    required this.onReviewsTap,
  });

  final double hairline;
  final String name;
  final String handle;
  final double rating;
  final int reviews;
  final int followers;
  final bool isSubscribed;
  final VoidCallback onSubscribe;
  final VoidCallback onTap;
  final VoidCallback onReviewsTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            InkWell(
              onTap: onTap,
              splashFactory: NoSplash.splashFactory,
              highlightColor: Colors.transparent,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            height: 1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: InkWell(
                          onTap: onReviewsTap,
                          splashFactory: NoSplash.splashFactory,
                          highlightColor: Colors.transparent,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                CupertinoIcons.star_fill,
                                size: 14,
                                color: Color(0xFFFFB31A),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                rating.toStringAsFixed(1).replaceAll('.', ','),
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _reviewCountLabel(reviews),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black.withValues(alpha: 0.56),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: null,
                    splashFactory: NoSplash.splashFactory,
                    highlightColor: Colors.transparent,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Expanded(
                          child: Text(
                            handle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1,
                              fontWeight: FontWeight.w600,
                              color: Colors.black.withValues(alpha: 0.58),
                            ),
                          ),
                        ),
                        const SizedBox(width: 0),
                        const Icon(
                          CupertinoIcons.star_fill,
                          size: 0,
                          color: Color(0xFFFFB31A),
                        ),
                        const SizedBox(width: 0),
                        Text(
                          rating.toStringAsFixed(1).replaceAll('.', ','),
                          style: const TextStyle(
                            fontSize: 0,
                            height: 1,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(width: 0),
                        Text(
                          '$reviews отзыва',
                          style: TextStyle(
                            fontSize: 0,
                            height: 1,
                            fontWeight: FontWeight.w700,
                            color: Colors.black.withValues(alpha: 0.56),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      InkWell(
                        onTap: onSubscribe,
                        splashFactory: NoSplash.splashFactory,
                        highlightColor: Colors.transparent,
                        child: Container(
                          height: 20,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            isSubscribed ? 'ВЫ ПОДПИСАНЫ' : 'ПОДПИСАТЬСЯ',
                            style: const TextStyle(
                              fontSize: 9,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 4,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        '$followers подписчика',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.black.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BuyDeliveryBlock extends StatelessWidget {
  const _BuyDeliveryBlock({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        ),
        child: const Text(
          'КУПИТЬ С ДОСТАВКОЙ',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _DeliveryAddress extends StatelessWidget {
  const _DeliveryAddress({required this.address, required this.fallbackCity});

  final String address;
  final String fallbackCity;

  @override
  Widget build(BuildContext context) {
    final city = fallbackCity.trim();
    final savedAddress = address.trim();
    final value = savedAddress.isEmpty
        ? city
        : city.isEmpty ||
              savedAddress.toLowerCase().startsWith('${city.toLowerCase()},')
        ? savedAddress
        : '$city, $savedAddress';
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          const Icon(CupertinoIcons.location_solid, size: 15),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Адрес: $value',
              style: const TextStyle(
                fontSize: 15,
                height: 1.2,
                fontWeight: FontWeight.w500,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _ProductLocationSection extends StatelessWidget {
  const _ProductLocationSection({
    required this.product,
    required this.hairline,
    required this.onLocationDetails,
  });

  final ProductDetailData product;
  final double hairline;
  final VoidCallback onLocationDetails;

  @override
  Widget build(BuildContext context) {
    final location = product.location.trim();
    if (location.isEmpty) return const SizedBox.shrink();
    return _ProductInfoSection(
      title: 'Местоположение',
      hairline: hairline,
      showTopBorder: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            location,
            style: const TextStyle(
              fontSize: 14,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: onLocationDetails,
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            child: Text(
              'Узнать подробности >',
              style: TextStyle(
                fontSize: 14,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
                color: Colors.black.withValues(alpha: 0.48),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductDatabaseDescription extends StatefulWidget {
  const _ProductDatabaseDescription({
    required this.product,
    required this.sourceProduct,
    required this.hairline,
  });

  final ProductDetailData product;
  final Product? sourceProduct;
  final double hairline;

  @override
  State<_ProductDatabaseDescription> createState() =>
      _ProductDatabaseDescriptionState();
}

class _ProductDatabaseDescriptionState
    extends State<_ProductDatabaseDescription> {
  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final source = widget.sourceProduct;
    final description = product.description.trim();
    final schema = source == null
        ? const <ListingAttributeDefinition>[]
        : ListingCatalogs.attributesFor(
            source.normalizedCategory.isNotEmpty
                ? source.normalizedCategory
                : source.itemType,
          );
    final relevantDefinitions = schema.isNotEmpty
        ? schema
        : const <ListingAttributeDefinition>[
            ListingAttributeDefinition(
              id: 'material',
              label: 'Материал',
              options: ListingCatalogs.materials,
            ),
            ListingAttributeDefinition(
              id: 'pattern',
              label: 'Рисунок',
              options: ListingCatalogs.patterns,
            ),
            ListingAttributeDefinition(
              id: 'fit',
              label: 'Крой',
              options: ListingCatalogs.fits,
            ),
            ListingAttributeDefinition(
              id: 'style',
              label: 'Стиль',
              options: ListingCatalogs.styles,
            ),
            ListingAttributeDefinition(
              id: 'season',
              label: 'Сезон',
              options: ListingCatalogs.seasons,
            ),
            ListingAttributeDefinition(
              id: 'closure',
              label: 'Тип застёжки',
              options: ListingCatalogs.closures,
            ),
          ];
    final relevantAttributes = source == null
        ? const <ListingAttributeDefinition>[]
        : relevantDefinitions
              .where(
                (definition) =>
                    _attributeValue(source, definition.id).isNotEmpty,
              )
              .toList(growable: false);
    final category = _categoryName(product, source);
    final brand = product.brand.trim().isNotEmpty
        ? product.brand.trim()
        : ListingCatalogs.nameOf(source?.normalizedBrand ?? '', fallback: '');
    final audienceId = source?.audience.trim().isNotEmpty == true
        ? source!.audience.trim()
        : source?.gender.trim() ?? '';
    final audience = ListingCatalogs.nameOf(audienceId, fallback: audienceId);
    final primaryColorId = source?.primaryColor.trim() ?? '';
    final primaryColor = primaryColorId.isNotEmpty
        ? ListingCatalogs.nameOf(primaryColorId, fallback: product.color.trim())
        : product.color.trim();
    final additionalColors =
        source?.secondaryColors
            .map(
              (color) => ListingCatalogs.nameOf(color.trim(), fallback: color),
            )
            .where(
              (color) =>
                  color.trim().isNotEmpty &&
                  color.trim().toLowerCase() != primaryColor.toLowerCase(),
            )
            .toSet()
            .join(', ') ??
        '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProductInfoSection(
          title: 'Характеристики',
          hairline: widget.hairline,
          showTopBorder: false,
          compact: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CharacteristicLine(label: 'Категория', value: category),
              _CharacteristicLine(label: 'Бренд', value: brand),
              _CharacteristicLine(label: 'Размер', value: product.size),
              _CharacteristicLine(label: 'Состояние', value: product.condition),
              _CharacteristicLine(label: 'Аудитория', value: audience),
              _CharacteristicLine(label: 'Основной цвет', value: primaryColor),
              _CharacteristicLine(
                label: 'Дополнительные цвета',
                value: additionalColors,
              ),
              for (final definition in relevantAttributes)
                _CharacteristicLine(
                  label: definition.label,
                  value: ListingCatalogs.nameOf(
                    _attributeValue(source!, definition.id),
                    fallback: _attributeValue(source, definition.id),
                  ),
                ),
            ],
          ),
        ),
        if (description.isNotEmpty)
          _ProductInfoSection(
            title: 'Описание',
            hairline: widget.hairline,
            showTopBorder: false,
            compact: true,
            child: Text(
              description,
              style: const TextStyle(
                fontSize: 15,
                height: 1.24,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
                color: Colors.black,
              ),
            ),
          ),
        if (source?.hasDefects == true &&
            source!.defectsDescription.trim().isNotEmpty)
          _ProductInfoSection(
            title: 'Дефекты',
            hairline: widget.hairline,
            showTopBorder: false,
            compact: true,
            child: Text(
              source.defectsDescription.trim(),
              style: const TextStyle(
                fontSize: 15,
                height: 1.24,
                fontWeight: FontWeight.w500,
                color: Colors.black,
              ),
            ),
          ),
      ],
    );
  }

  String _categoryName(ProductDetailData product, Product? source) {
    final normalizedCategory = source?.normalizedCategory.trim() ?? '';
    if (normalizedCategory.isNotEmpty) {
      return ListingCatalogs.nameOf(
        normalizedCategory,
        fallback: normalizedCategory,
      );
    }

    final legacyCategory = ListingCatalogs.normalizeCategory(
      source?.itemType ?? '',
    );
    if (legacyCategory.isNotEmpty) {
      return ListingCatalogs.nameOf(legacyCategory, fallback: product.category);
    }
    return product.category.trim();
  }

  String _attributeValue(Product product, String key) {
    final structured = product.categoryAttributes[key];
    if (structured?.isNotEmpty == true) return structured!;
    return switch (key) {
      'material' => product.material,
      'pattern' => product.pattern,
      'fit' => product.fit,
      'sleeve_length' => product.sleeveLength,
      'closure' => product.closure,
      'season' => product.season,
      'style' => product.style,
      _ => '',
    };
  }
}

// ignore: unused_element
class _SellerProfileLink extends StatelessWidget {
  const _SellerProfileLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'перейти в профиль',
                style: TextStyle(
                  fontSize: 14,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                  color: Colors.black,
                ),
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: Colors.black.withValues(alpha: 0.72),
            ),
          ],
        ),
      ),
    );
  }
}

class _RelatedProductsSection extends StatelessWidget {
  const _RelatedProductsSection({
    required this.products,
    required this.onProductTap,
    this.onToggleLike,
  });

  final List<Product> products;
  final ValueChanged<Product> onProductTap;
  final Future<void> Function(String productId)? onToggleLike;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Похожие объявления',
          style: TextStyle(
            fontSize: 16,
            height: 1,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 7),
        GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: products.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 12,
            childAspectRatio: 0.58,
          ),
          itemBuilder: (context, index) {
            final product = products[index];
            return _RelatedProductCard(
              product: product,
              onTap: () => onProductTap(product),
              onToggleLike: onToggleLike == null
                  ? null
                  : () => onToggleLike!(product.id),
            );
          },
        ),
      ],
    );
  }
}

class _RelatedProductCard extends StatefulWidget {
  const _RelatedProductCard({
    required this.product,
    required this.onTap,
    this.onToggleLike,
  });

  final Product product;
  final VoidCallback onTap;
  final Future<void> Function()? onToggleLike;

  @override
  State<_RelatedProductCard> createState() => _RelatedProductCardState();
}

class _RelatedProductCardState extends State<_RelatedProductCard> {
  late bool _isLiked = widget.product.isLiked;

  @override
  void didUpdateWidget(covariant _RelatedProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.isLiked != widget.product.isLiked) {
      _isLiked = widget.product.isLiked;
    }
  }

  Future<void> _toggleLike() async {
    final onToggleLike = widget.onToggleLike;
    if (onToggleLike == null) return;
    final previous = _isLiked;
    setState(() => _isLiked = !_isLiked);
    try {
      await onToggleLike();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLiked = previous);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 4 / 5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: const Color(0xFFF1F1F1),
                  child: AppImage(
                    imageUrl: widget.product.image,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleLike,
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: Icon(
                        _isLiked
                            ? CupertinoIcons.heart_fill
                            : CupertinoIcons.heart,
                        size: 25,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.product.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              height: 1.12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.product.price,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
              color: Colors.black,
              fontFeatures: [
                FontFeature.tabularFigures(),
                FontFeature.liningFigures(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductInfoSection extends StatelessWidget {
  const _ProductInfoSection({
    required this.title,
    required this.child,
    required this.hairline,
    this.showTopBorder = true,
    this.compact = false,
  });

  final String title;
  final Widget child;
  final double hairline;
  final bool showTopBorder;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTopBorder)
            Center(
              child: Container(
                width: 64,
                height: hairline,
                color: Colors.black,
              ),
            ),
          Padding(
            padding: compact
                ? const EdgeInsets.fromLTRB(0, 8, 0, 10)
                : const EdgeInsets.fromLTRB(0, 12, 0, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: compact ? 17 : 24,
                    height: 1,
                    fontWeight: compact ? FontWeight.w700 : FontWeight.w800,
                    letterSpacing: 0,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: compact ? 7 : 10),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CharacteristicLine extends StatelessWidget {
  const _CharacteristicLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final normalized = value.trim();
    if (normalized.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 15,
            height: 1.24,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
            color: Color(0xFF77777C),
          ),
          children: [
            TextSpan(text: '$label:'),
            if (normalized.isNotEmpty)
              TextSpan(
                text: ' $normalized',
                style: const TextStyle(color: Colors.black),
              ),
          ],
        ),
      ),
    );
  }
}

class DeliveryCheckoutScreen extends StatefulWidget {
  const DeliveryCheckoutScreen({
    super.key,
    required this.product,
    required this.deliveryProfile,
    required this.onSaveProfile,
    required this.onSubmitOrder,
  });

  final ProductDetailData product;
  final DeliveryProfile deliveryProfile;
  final Future<void> Function(DeliveryProfile profile) onSaveProfile;
  final Future<void> Function() onSubmitOrder;

  @override
  State<DeliveryCheckoutScreen> createState() => _DeliveryCheckoutScreenState();
}

class _DeliveryCheckoutScreenState extends State<DeliveryCheckoutScreen> {
  static const _postPrice = 122;
  static const _pickupPrice = 0;

  late DeliveryProfile _profile;
  String _method = 'Почта России';
  bool _isSubmitting = false;

  int get _deliveryPrice =>
      _method == 'Почта России' ? _postPrice : _pickupPrice;
  int get _total => widget.product.priceValue + _deliveryPrice;

  @override
  void initState() {
    super.initState();
    _profile = widget.deliveryProfile;
  }

  String get _addressLine {
    final city = _profile.city.trim();
    final address = _profile.address.trim();
    if (city.isEmpty && address.isEmpty) return 'Добавьте адрес получателя';
    if (city.isEmpty) return address;
    if (address.isEmpty) return city;
    return '$city, $address';
  }

  Future<void> _editRecipient() async {
    final next = await showModalBottomSheet<DeliveryProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) => _RecipientEditor(profile: _profile),
    );
    if (next == null) return;
    setState(() => _profile = next);
    await widget.onSaveProfile(next);
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    await widget.onSaveProfile(_profile);
    await widget.onSubmitOrder();
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Заказ создан')));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  SizedBox(
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(CupertinoIcons.back, size: 24),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 44,
                              minHeight: 44,
                            ),
                          ),
                        ),
                        const Text(
                          'Оформление доставки',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Способ Получения',
                    style: TextStyle(
                      fontSize: 24,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Для адреса: $_addressLine',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _DeliveryMethodCard(
                          selected: _method == 'Почта России',
                          title: 'Почта России',
                          subtitle: '${_formatPrice(_postPrice)} ₽',
                          onTap: () => setState(() => _method = 'Почта России'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DeliveryMethodCard(
                          selected: _method == 'Пункт выдачи',
                          title: 'Пункт выдачи',
                          subtitle: _pickupPrice == 0
                              ? 'бесплатно'
                              : '${_formatPrice(_pickupPrice)} ₽',
                          onTap: () => setState(() => _method = 'Пункт выдачи'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 34),
                  Text(
                    widget.product.sellerName,
                    style: const TextStyle(
                      fontSize: 24,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 80,
                          height: 80,
                          child: AppImage(
                            imageUrl: widget.product.image,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.product.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_formatPrice(widget.product.priceValue)} ₽',
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _DeliveryAddressBlock(
                    method: _method,
                    address: _addressLine,
                    price: _deliveryPrice,
                  ),
                  const SizedBox(height: 34),
                  const Text(
                    'Получатель',
                    style: TextStyle(
                      fontSize: 24,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _profile.fullName.trim().isEmpty
                        ? 'Имя не указано'
                        : _profile.fullName,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (_profile.phone.trim().isNotEmpty) _profile.phone,
                      if (_profile.email.trim().isNotEmpty) _profile.email,
                    ].join('\n'),
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _editRecipient,
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFE0E0E0),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: const RoundedRectangleBorder(),
                      ),
                      child: const Text(
                        'ИЗМЕНИТЬ ПОЛУЧАТЕЛЯ',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Стоимость',
                    style: TextStyle(
                      fontSize: 24,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _PriceLine(
                    title: '1 товар',
                    value: '${_formatPrice(widget.product.priceValue)} ₽',
                  ),
                  _PriceLine(
                    title: _method,
                    value: '${_formatPrice(_deliveryPrice)} ₽',
                  ),
                  _PriceLine(
                    title: 'Итого',
                    value: '${_formatPrice(_total)} ₽',
                    bold: true,
                  ),
                  const SizedBox(height: 24),
                  InkWell(
                    onTap: () {},
                    splashFactory: NoSplash.splashFactory,
                    highlightColor: Colors.transparent,
                    child: const Row(
                      children: [
                        Expanded(
                          child: Text(
                            'промокод',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        Icon(CupertinoIcons.chevron_right, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(14, 10, 14, 12 + bottomInset),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.black.withValues(
                      alpha: 0.4,
                    ),
                    elevation: 0,
                    shape: const RoundedRectangleBorder(),
                  ),
                  child: Text(
                    _isSubmitting
                        ? 'СОХРАНЯЕМ'
                        : 'ОПЛАТИТЬ ${_formatPrice(_total)} ₽',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryMethodCard extends StatelessWidget {
  const _DeliveryMethodCard({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      child: Container(
        height: 64,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? Colors.white : const Color(0xFFD9D9D9),
          border: Border.all(
            color: selected ? Colors.black : Colors.transparent,
            width: selected ? 1.5 : 0,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                color: Colors.black.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryAddressBlock extends StatelessWidget {
  const _DeliveryAddressBlock({
    required this.method,
    required this.address,
    required this.price,
  });

  final String method;
  final String address;
  final int price;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(CupertinoIcons.location, size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                method,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                address,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_formatPrice(price)} ₽',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({
    required this.title,
    required this.value,
    this.bold = false,
  });

  final String title;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              height: 1,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: Colors.black,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              height: 1,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipientEditor extends StatefulWidget {
  const _RecipientEditor({required this.profile});

  final DeliveryProfile profile;

  @override
  State<_RecipientEditor> createState() => _RecipientEditorState();
}

class _RecipientEditorState extends State<_RecipientEditor> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _cityController;
  late final TextEditingController _addressController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.fullName);
    _phoneController = TextEditingController(text: widget.profile.phone);
    _emailController = TextEditingController(text: widget.profile.email);
    _cityController = TextEditingController(text: widget.profile.city);
    _addressController = TextEditingController(text: widget.profile.address);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      DeliveryProfile(
        fullName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        city: _cityController.text.trim(),
        address: _addressController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Получатель',
            style: TextStyle(
              fontSize: 24,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 18),
          _RecipientField(controller: _nameController, label: 'Имя Фамилия'),
          _RecipientField(controller: _phoneController, label: 'Телефон'),
          _RecipientField(controller: _emailController, label: 'Email'),
          _RecipientField(controller: _cityController, label: 'Город'),
          _RecipientField(controller: _addressController, label: 'Адрес'),
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: const RoundedRectangleBorder(),
              ),
              child: const Text(
                'СОХРАНИТЬ',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipientField extends StatelessWidget {
  const _RecipientField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.black.withValues(alpha: 0.5),
            fontWeight: FontWeight.w700,
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.black),
          ),
        ),
      ),
    );
  }
}

String _formatPrice(int value) {
  return value.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]} ',
  );
}

String _reviewCountLabel(int count) {
  final mod100 = count % 100;
  if (mod100 >= 11 && mod100 <= 14) {
    return '$count отзывов';
  }

  switch (count % 10) {
    case 1:
      return '$count отзыв';
    case 2:
    case 3:
    case 4:
      return '$count отзыва';
    default:
      return '$count отзывов';
  }
}
