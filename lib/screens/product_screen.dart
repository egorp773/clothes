import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_typography.dart';
import '../models/app_profile.dart';
import '../models/product.dart';
import '../models/profile_feature.dart';
import '../services/image_download_service.dart';
import '../features/listing_publish/data/listing_catalogs.dart';
import '../widgets/app_image.dart';

const _productInfoBodyTextStyle = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: 15,
  height: 1.24,
  fontWeight: AppTypography.medium,
  letterSpacing: 0,
  color: Colors.black,
);

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
    this.publishedAt,
    this.viewsCount = 0,
    this.likesCount = 0,
    this.deliveryMethods = const [],
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
  final DateTime? publishedAt;
  final int viewsCount;
  final int likesCount;
  final List<String> deliveryMethods;
}

class ProductScreen extends StatefulWidget {
  const ProductScreen({
    super.key,
    required this.product,
    required this.onLike,
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
  final Future<AppOrder?> Function({
    required String deliveryService,
    required int deliveryPrice,
  })
  onCreateDeliveryOrder;

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
  int _viewsCount = 0;
  int _likesCount = 0;
  SellerProfile? _sellerProfile;
  int _reviewCount = 0;
  double _reviewRating = 0;
  bool _didShowUnavailableSheet = false;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.product.isLiked;
    _viewsCount =
        (widget.sourceProduct?.viewsCount ?? widget.product.viewsCount)
            .clamp(0, 1 << 31)
            .toInt();
    _likesCount =
        (widget.sourceProduct?.likesCount ?? widget.product.likesCount)
            .clamp(0, 1 << 31)
            .toInt();
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
    setState(() {
      final wasLiked = _isLiked;
      _isLiked = !wasLiked;
      _likesCount = (_likesCount + (wasLiked ? -1 : 1))
          .clamp(0, 1 << 31)
          .toInt();
    });
    widget.onLike();
  }

  Future<void> _loadSellerStats() async {
    final sourceProduct = widget.sourceProduct;
    final loadSellerProfile = widget.loadSellerProfile;
    final loadReviews = widget.loadReviews;
    if (sourceProduct == null || loadSellerProfile == null) {
      return;
    }
    final profile = await loadSellerProfile(sourceProduct);
    final sellerId = profile?.id.trim().isNotEmpty == true
        ? profile!.id
        : sourceProduct.ownerId;
    final reviews = loadReviews == null || sellerId.trim().isEmpty
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
    final titlePriceSpacing = spacing + 28.0 * (1 - t);
    final canPurchase = product.canPurchase;
    final sellerRating = _reviewCount == 0 ? 0.0 : _reviewRating;
    final sellerFollowers = (_sellerProfile?.followersCount ?? 0)
        .clamp(0, 1 << 31)
        .toInt();
    final priceText = canPurchase ? product.price : 'Не продается';
    final messageButtonText = canPurchase
        ? 'Написать сообщение'
        : 'Уточнить у продавца';
    final publishedAt =
        widget.sourceProduct?.publishedAt ?? product.publishedAt;

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
                                  (spacing * 0.5).clamp(12.0, 28.0),
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
                                      fallbackCity: product.location,
                                    ),
                                    if (!widget.isPreview ||
                                        publishedAt != null) ...[
                                      const SizedBox(height: 10),
                                      _ProductPublicationMeta(
                                        publishedAt: publishedAt,
                                        viewsCount: _viewsCount,
                                        likesCount: _likesCount,
                                      ),
                                    ],
                                    SizedBox(height: spacing),
                                    if (!widget.isPreview) ...[
                                      _BuyDeliveryBlock(
                                        onTap: _openDeliveryCheckout,
                                      ),
                                      SizedBox(height: spacing),
                                    ],
                                    _SellerCard(
                                      hairline: hairline,
                                      name: product.sellerName,
                                      handle: product.sellerHandle,
                                      avatarUrl:
                                          _sellerProfile?.avatarUrl ?? '',
                                      rating: sellerRating.toDouble(),
                                      reviews: _reviewCount,
                                      followers: sellerFollowers,
                                      onTap: widget.onOpenSeller,
                                      onReviewsTap: widget.onOpenReviews,
                                    ),
                                    const SizedBox(height: 14),
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
                                fontWeight: AppTypography.bold,
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

class _ProductPublicationMeta extends StatelessWidget {
  const _ProductPublicationMeta({
    required this.publishedAt,
    required this.viewsCount,
    required this.likesCount,
  });

  final DateTime? publishedAt;
  final int viewsCount;
  final int likesCount;

  @override
  Widget build(BuildContext context) {
    final publicationLabel = publishedAt == null
        ? '—'
        : _formatPublicationDate(publishedAt!);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Опубликовано: $publicationLabel',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13.5,
              height: 1.2,
              fontWeight: AppTypography.medium,
              letterSpacing: 0,
              color: Color(0xFF77777D),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _ProductMetaItem(
          icon: CupertinoIcons.eye,
          text: '$viewsCount',
          semanticsLabel: '$viewsCount просмотров',
        ),
        const SizedBox(width: 10),
        _ProductMetaItem(
          icon: CupertinoIcons.heart,
          text: '$likesCount',
          semanticsLabel: '$likesCount лайков',
        ),
      ],
    );
  }
}

class _ProductMetaItem extends StatelessWidget {
  const _ProductMetaItem({
    required this.icon,
    required this.text,
    required this.semanticsLabel,
  });

  final IconData icon;
  final String text;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF77777D)),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13.5,
              height: 1.2,
              fontWeight: AppTypography.medium,
              letterSpacing: 0,
              color: Color(0xFF77777D),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatPublicationDate(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int part) => part.toString().padLeft(2, '0');
  return '${twoDigits(local.day)}.${twoDigits(local.month)}.${local.year}, '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
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
    required this.avatarUrl,
    required this.rating,
    required this.reviews,
    required this.followers,
    required this.onTap,
    required this.onReviewsTap,
  });

  final double hairline;
  final String name;
  final String handle;
  final String avatarUrl;
  final double rating;
  final int reviews;
  final int followers;
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
              child: SizedBox(
                width: 56,
                height: 56,
                child: ClipOval(
                  child: avatarUrl.trim().isEmpty
                      ? ColoredBox(
                          color: const Color(0xFFF0F0F1),
                          child: Center(
                            child: Text(
                              name.trim().isEmpty
                                  ? '?'
                                  : name.trim()[0].toUpperCase(),
                              style: const TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 24,
                                fontWeight: AppTypography.bold,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        )
                      : AppImage(imageUrl: avatarUrl.trim(), fit: BoxFit.cover),
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
                            fontSize: 18,
                            height: 1,
                            fontWeight: AppTypography.bold,
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
                                  fontSize: 14,
                                  height: 1,
                                  fontWeight: AppTypography.bold,
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
                    onTap: onTap,
                    splashFactory: NoSplash.splashFactory,
                    highlightColor: Colors.transparent,
                    child: Text(
                      handle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1,
                        fontWeight: AppTypography.semiBold,
                        color: Colors.black.withValues(alpha: 0.58),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        height: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'ПРОДАВЕЦ',
                          style: TextStyle(
                            fontSize: 9,
                            height: 1,
                            fontWeight: AppTypography.bold,
                            letterSpacing: 3.2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          '$followers ${_followerCountLabel(followers)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: AppTypography.medium,
                            color: Colors.black.withValues(alpha: 0.72),
                          ),
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

String _followerCountLabel(int count) {
  final mod100 = count.abs() % 100;
  final mod10 = count.abs() % 10;
  if (mod100 >= 11 && mod100 <= 14) return 'подписчиков';
  if (mod10 == 1) return 'подписчик';
  if (mod10 >= 2 && mod10 <= 4) return 'подписчика';
  return 'подписчиков';
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
            fontWeight: AppTypography.bold,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _DeliveryAddress extends StatelessWidget {
  const _DeliveryAddress({required this.fallbackCity});

  final String fallbackCity;

  @override
  Widget build(BuildContext context) {
    final city = fallbackCity.trim();
    if (city.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          const Icon(CupertinoIcons.location_solid, size: 15),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Отправка из города: $city',
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
                fontWeight: AppTypography.bold,
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
        : ListingCatalogs.brandName(
            source?.normalizedBrand ?? '',
            fallback: '',
          );
    final audienceId = source?.audience.trim().isNotEmpty == true
        ? source!.audience.trim()
        : source?.gender.trim() ?? '';
    final audience = ListingCatalogs.genderName(
      audienceId,
      fallback: audienceId,
    );
    final primaryColorId = source?.primaryColor.trim() ?? '';
    final primaryColor = primaryColorId.isNotEmpty
        ? ListingCatalogs.colorName(
            primaryColorId,
            fallback: product.color.trim(),
          )
        : product.color.trim();
    final additionalColors =
        source?.secondaryColors
            .map(
              (color) =>
                  ListingCatalogs.colorName(color.trim(), fallback: color),
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
                  value: ListingCatalogs.attributeValueName(
                    definition.id,
                    _attributeValue(source!, definition.id),
                    category: source.normalizedCategory,
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
            child: Text(description, style: _productInfoBodyTextStyle),
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
              style: _productInfoBodyTextStyle,
            ),
          ),
      ],
    );
  }

  String _categoryName(ProductDetailData product, Product? source) {
    final normalizedCategory = source?.normalizedCategory.trim() ?? '';
    if (normalizedCategory.isNotEmpty) {
      return ListingCatalogs.categoryName(
        normalizedCategory,
        fallback: normalizedCategory,
      );
    }

    final legacyCategory = ListingCatalogs.normalizeCategory(
      source?.itemType ?? '',
    );
    if (legacyCategory.isNotEmpty) {
      return ListingCatalogs.categoryName(
        legacyCategory,
        fallback: product.category,
      );
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
                  fontWeight: AppTypography.bold,
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
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.62,
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
              fontWeight: AppTypography.bold,
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
              fontWeight: AppTypography.bold,
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
                    fontWeight: AppTypography.bold,
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
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label:',
              style: const TextStyle(color: Color(0xFF77777C)),
            ),
            if (normalized.isNotEmpty)
              TextSpan(text: ' $normalized', style: _productInfoBodyTextStyle),
          ],
        ),
        style: _productInfoBodyTextStyle,
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
  final Future<AppOrder?> Function({
    required String deliveryService,
    required int deliveryPrice,
  })
  onSubmitOrder;

  @override
  State<DeliveryCheckoutScreen> createState() => _DeliveryCheckoutScreenState();
}

class _DeliveryCheckoutScreenState extends State<DeliveryCheckoutScreen> {
  static const _addressMethod = 'address';
  static const _pickupMethod = 'pickup_point';

  late DeliveryProfile _profile;
  String _method = _addressMethod;
  late String _provider;
  _PickupPointDraft? _selectedPickupPoint;
  bool _isSubmitting = false;

  bool get _isPickup => _method == _pickupMethod;
  bool get _hasSelectedPickupPoint =>
      _selectedPickupPoint?.id.trim().isNotEmpty == true &&
      _selectedPickupPoint?.address.trim().isNotEmpty == true;
  int get _deliveryPrice => 0;
  int get _total => widget.product.priceValue + _deliveryPrice;

  List<_DeliveryProviderOption> get _providers {
    final methods = widget.product.deliveryMethods.toSet();
    // Legacy listings do not declare a carrier. Keep that state explicit
    // instead of silently presenting a real provider that was never selected.
    if (methods.isEmpty) return const [_unassignedDeliveryProvider];
    final options = _deliveryProviders
        .where((option) => methods.contains(option.id))
        .toList(growable: false);
    if (options.isNotEmpty) return options;
    return const [];
  }

  String get _providerLabel {
    for (final provider in _providers) {
      if (provider.id == _provider) return provider.label;
    }
    return _unassignedDeliveryProvider.label;
  }

  @override
  void initState() {
    super.initState();
    _profile = widget.deliveryProfile;
    final availableProviders = _providers;
    final savedProvider = _profile.pickupProvider.trim();
    _provider = availableProviders.any((item) => item.id == savedProvider)
        ? savedProvider
        : availableProviders.firstOrNull?.id ?? 'unavailable';
    if (_profile.pickupPointId.trim().isNotEmpty &&
        _profile.pickupPointAddress.trim().isNotEmpty) {
      _selectedPickupPoint = _PickupPointDraft(
        id: _profile.pickupPointId.trim(),
        name: _profile.pickupPointName.trim(),
        address: _profile.pickupPointAddress.trim(),
      );
    }
  }

  String get _addressLine {
    final city = _profile.city.trim();
    final address = _profile.address.trim();
    if (city.isEmpty && address.isEmpty) return 'Добавьте адрес получателя';
    if (city.isEmpty) return address;
    if (address.isEmpty) return city;
    return '$city, $address';
  }

  String? get _recipientValidationMessage {
    if (_profile.fullName.trim().length < 2) {
      return 'Укажите имя получателя';
    }
    final phoneDigits = _profile.phone.replaceAll(RegExp(r'\D'), '');
    if (phoneDigits.length < 10) return 'Проверьте телефон получателя';
    final email = _profile.email.trim();
    if (email.isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'Проверьте email получателя';
    }
    if (_profile.city.trim().isEmpty) return 'Укажите город доставки';
    if (_providers.isEmpty) {
      return 'Продавец не подключил доставку для этого объявления';
    }
    if (_isPickup && !_hasSelectedPickupPoint) {
      return 'Выберите пункт выдачи';
    }
    if (!_isPickup && _profile.address.trim().isEmpty) {
      return 'Укажите город и адрес доставки';
    }
    return null;
  }

  void _showCheckoutMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _editRecipient() async {
    final next = await showModalBottomSheet<DeliveryProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) =>
          _RecipientEditor(profile: _profile, requiresAddress: !_isPickup),
    );
    if (next == null || !mounted) return;
    final cityChanged =
        next.city.trim().toLowerCase() != _profile.city.trim().toLowerCase();
    setState(() {
      _profile = next;
      if (cityChanged) _selectedPickupPoint = null;
    });
    try {
      await widget.onSaveProfile(next);
    } catch (_) {
      if (mounted) {
        _showCheckoutMessage(
          'Не удалось сохранить данные получателя. Попробуйте ещё раз.',
        );
      }
    }
  }

  Future<void> _selectPickupPoint() async {
    final next = await showModalBottomSheet<_PickupPointDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) => _PickupPointEditor(
        city: _profile.city,
        providerLabel: _providerLabel,
        initialValue: _selectedPickupPoint,
      ),
    );
    if (next == null || !mounted) return;
    setState(() => _selectedPickupPoint = next);
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final validationMessage = _recipientValidationMessage;
    if (validationMessage != null) {
      _showCheckoutMessage(validationMessage);
      if (validationMessage == 'Выберите пункт выдачи') {
        await _selectPickupPoint();
      } else if (validationMessage !=
          'Продавец не подключил доставку для этого объявления') {
        await _editRecipient();
      }
      return;
    }

    setState(() => _isSubmitting = true);
    var completed = false;
    try {
      final submissionProfile = _isPickup
          ? _profile.copyWith(
              pickupProvider: _provider,
              pickupPointId: _selectedPickupPoint!.id.trim(),
              pickupPointName: _selectedPickupPoint!.name.trim(),
              pickupPointAddress: _selectedPickupPoint!.address.trim(),
            )
          : _profile;
      await widget.onSaveProfile(submissionProfile);
      final order = await widget.onSubmitOrder(
        deliveryService: '$_method:$_provider',
        deliveryPrice: _deliveryPrice,
      );
      if (!mounted) return;
      if (order == null) {
        _showCheckoutMessage('Не удалось оформить заказ. Попробуйте ещё раз.');
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      completed = true;
      Navigator.of(context).pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Заявка на заказ создана — она появилась в профиле'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } on CheckoutException catch (error) {
      if (mounted) _showCheckoutMessage(error.message);
    } catch (_) {
      if (mounted) {
        _showCheckoutMessage('Не удалось оформить заказ. Попробуйте ещё раз.');
      }
    } finally {
      if (mounted && !completed) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final baseTheme = Theme.of(context);
    return Theme(
      data: baseTheme.copyWith(
        textTheme: baseTheme.textTheme.apply(
          fontFamily: AppTypography.fontFamily,
        ),
        primaryTextTheme: baseTheme.primaryTextTheme.apply(
          fontFamily: AppTypography.fontFamily,
        ),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F7F8),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
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
                            'Оформление заказа',
                            style: TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 18,
                              fontWeight: AppTypography.bold,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Способ получения',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 18,
                        height: 1.1,
                        fontWeight: AppTypography.bold,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isPickup
                          ? 'Выберите удобный пункт в ${_profile.city.trim().isEmpty ? 'вашем городе' : _profile.city.trim()}'
                          : 'Куда доставить: $_addressLine',
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: AppTypography.medium,
                        letterSpacing: 0,
                        color: Color(0xFF66666B),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _DeliveryMethodCard(
                            key: const Key('delivery-method-post'),
                            selected: _method == _addressMethod,
                            title: 'До адреса',
                            subtitle: 'после подтверждения',
                            onTap: () =>
                                setState(() => _method = _addressMethod),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _DeliveryMethodCard(
                            key: const Key('delivery-method-pickup'),
                            selected: _isPickup,
                            title: 'Пункт выдачи',
                            subtitle: 'после подтверждения',
                            onTap: () =>
                                setState(() => _method = _pickupMethod),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _DeliveryProviderSelector(
                      providers: _providers,
                      selectedId: _provider,
                      onChanged: (provider) {
                        setState(() {
                          if (_provider != provider) {
                            _provider = provider;
                            _selectedPickupPoint = null;
                          }
                        });
                      },
                    ),
                    if (_isPickup) ...[
                      const SizedBox(height: 12),
                      _PickupPointSelector(
                        value: _selectedPickupPoint,
                        onTap: _selectPickupPoint,
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      widget.product.sellerName,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 16,
                        height: 1.1,
                        fontWeight: AppTypography.semiBold,
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
                                  fontFamily: AppTypography.fontFamily,
                                  fontSize: 14,
                                  height: 1.25,
                                  fontWeight: AppTypography.medium,
                                  letterSpacing: 0,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_formatPrice(widget.product.priceValue)} ₽',
                                style: const TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontSize: 13,
                                  height: 1,
                                  fontWeight: AppTypography.bold,
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
                      method: _isPickup ? 'Пункт выдачи' : 'До адреса',
                      provider: _providerLabel,
                      address: _isPickup
                          ? (_selectedPickupPoint?.displayLabel ??
                                'Пункт выдачи не выбран')
                          : _addressLine,
                      priceLabel: 'Стоимость после подтверждения',
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Получатель',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 18,
                        height: 1.1,
                        fontWeight: AppTypography.bold,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _profile.fullName.trim().isEmpty
                          ? 'Имя не указано'
                          : _profile.fullName,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 14,
                        height: 1.2,
                        fontWeight: AppTypography.semiBold,
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
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: AppTypography.medium,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _editRecipient,
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFFEDEDEF),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Изменить данные',
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 13,
                            fontWeight: AppTypography.semiBold,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Стоимость',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 18,
                        height: 1.1,
                        fontWeight: AppTypography.bold,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _PriceLine(
                      title: '1 товар',
                      value: '${_formatPrice(widget.product.priceValue)} ₽',
                    ),
                    _PriceLine(title: 'Доставка', value: 'после подтверждения'),
                    _PriceLine(
                      title: 'Итого сейчас',
                      value: '${_formatPrice(_total)} ₽',
                      bold: true,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Оплата не списывается. Продавец подтвердит заказ, а точная стоимость доставки появится после расчёта службы доставки.',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: AppTypography.medium,
                        color: Color(0xFF66666B),
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
                    key: const Key('checkout-submit'),
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.black.withValues(
                        alpha: 0.4,
                      ),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      _isSubmitting
                          ? 'ОФОРМЛЯЕМ'
                          : 'ОФОРМИТЬ ЗАЯВКУ · ${_formatPrice(_total)} ₽',
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13,
                        fontWeight: AppTypography.semiBold,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeliveryMethodCard extends StatelessWidget {
  const _DeliveryMethodCard({
    super.key,
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
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? Colors.white : const Color(0xFFEDEDEF),
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
                fontFamily: AppTypography.fontFamily,
                fontSize: 14,
                height: 1.15,
                fontWeight: AppTypography.semiBold,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                height: 1.2,
                fontWeight: AppTypography.medium,
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

class _DeliveryProviderOption {
  const _DeliveryProviderOption(this.id, this.label);

  final String id;
  final String label;
}

const _unassignedDeliveryProvider = _DeliveryProviderOption(
  'unassigned',
  'Служба после подтверждения',
);

const _deliveryProviders = <_DeliveryProviderOption>[
  _DeliveryProviderOption('cdek', 'СДЭК'),
  _DeliveryProviderOption('russian_post', 'Почта России'),
  _DeliveryProviderOption('yandex_delivery', 'Яндекс Доставка'),
];

class _DeliveryProviderSelector extends StatelessWidget {
  const _DeliveryProviderSelector({
    required this.providers,
    required this.selectedId,
    required this.onChanged,
  });

  final List<_DeliveryProviderOption> providers;
  final String selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (providers.isEmpty) {
      return Container(
        key: const Key('delivery-provider-unavailable'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Продавец не подключил доставку для этого объявления',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 13,
            height: 1.35,
            fontWeight: AppTypography.medium,
            color: Color(0xFF8E2C28),
          ),
        ),
      );
    }

    return DropdownButtonFormField<String>(
      key: const Key('delivery-provider-selector'),
      initialValue: providers.any((item) => item.id == selectedId)
          ? selectedId
          : providers.first.id,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Служба доставки',
        labelStyle: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 13,
          fontWeight: AppTypography.medium,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE1E1E5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE1E1E5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black, width: 1.4),
        ),
      ),
      style: const TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontSize: 14,
        fontWeight: AppTypography.semiBold,
        color: Colors.black,
      ),
      items: [
        for (final provider in providers)
          DropdownMenuItem(value: provider.id, child: Text(provider.label)),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _PickupPointSelector extends StatelessWidget {
  const _PickupPointSelector({required this.value, required this.onTap});

  final _PickupPointDraft? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedValue = value?.displayLabel ?? '';
    final hasSelection =
        value?.id.trim().isNotEmpty == true &&
        value?.address.trim().isNotEmpty == true;
    return Material(
      key: const Key('pickup-point-selector'),
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.location,
                size: 20,
                color: hasSelection ? Colors.black : const Color(0xFF77777D),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Пункт выдачи',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 14,
                        height: 1.1,
                        fontWeight: AppTypography.semiBold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasSelection ? selectedValue : 'Пункт ещё не выбран',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: AppTypography.medium,
                        color: Colors.black.withValues(alpha: 0.52),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                hasSelection ? 'Изменить' : 'Выбрать',
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  fontWeight: AppTypography.semiBold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(CupertinoIcons.chevron_right, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickupPointEditor extends StatefulWidget {
  const _PickupPointEditor({
    required this.city,
    required this.providerLabel,
    required this.initialValue,
  });

  final String city;
  final String providerLabel;
  final _PickupPointDraft? initialValue;

  @override
  State<_PickupPointEditor> createState() => _PickupPointEditorState();
}

class _PickupPointEditorState extends State<_PickupPointEditor> {
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialValue?.name);
    _addressController = TextEditingController(
      text: widget.initialValue?.address,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _save() {
    final address = _addressController.text.trim();
    if (address.length < 5) {
      setState(() => _errorText = 'Укажите точный адрес пункта выдачи');
      return;
    }
    final existingId = widget.initialValue?.id.trim() ?? '';
    Navigator.of(context).pop(
      _PickupPointDraft(
        id: existingId.isNotEmpty
            ? existingId
            : 'manual_${DateTime.now().microsecondsSinceEpoch}',
        name: _nameController.text.trim(),
        address: address,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Выбор пункта выдачи',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 20,
              height: 1.1,
              fontWeight: AppTypography.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.city.trim().isEmpty
                ? 'Сначала укажите город в данных получателя.'
                : '${widget.providerLabel} · ${widget.city.trim()}',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              height: 1.3,
              fontWeight: AppTypography.medium,
              color: Color(0xFF66666B),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'До подключения карты ПВЗ укажите точный пункт вручную. Перед оплатой адрес и стоимость будут подтверждены.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12.5,
              height: 1.35,
              fontWeight: AppTypography.medium,
              color: Color(0xFF66666B),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.next,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 15,
              fontWeight: AppTypography.medium,
            ),
            decoration: InputDecoration(
              labelText: 'Название пункта (необязательно)',
              hintText: 'Например, СДЭК на Тверской',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.black, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('pickup-point-field'),
            controller: _addressController,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 15,
              fontWeight: AppTypography.medium,
            ),
            decoration: InputDecoration(
              labelText: 'Точный адрес пункта',
              hintText: 'Улица, дом',
              errorText: _errorText,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.black, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              key: const Key('pickup-point-save'),
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Сохранить пункт',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  fontWeight: AppTypography.semiBold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickupPointDraft {
  const _PickupPointDraft({
    required this.id,
    required this.name,
    required this.address,
  });

  final String id;
  final String name;
  final String address;

  String get displayLabel => name.trim().isEmpty
      ? address.trim()
      : '${name.trim()} · ${address.trim()}';
}

class _DeliveryAddressBlock extends StatelessWidget {
  const _DeliveryAddressBlock({
    required this.method,
    required this.provider,
    required this.address,
    required this.priceLabel,
  });

  final String method;
  final String provider;
  final String address;
  final String priceLabel;

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
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  height: 1.1,
                  fontWeight: AppTypography.semiBold,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                provider,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  height: 1.25,
                  fontWeight: AppTypography.semiBold,
                  color: Color(0xFF55555B),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                address,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  height: 1.3,
                  fontWeight: AppTypography.medium,
                  letterSpacing: 0,
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                priceLabel,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12.5,
                  height: 1,
                  fontWeight: AppTypography.semiBold,
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
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              height: 1,
              fontWeight: bold ? AppTypography.bold : AppTypography.medium,
              letterSpacing: 0,
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: const Color(0xFFD8D8DC),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              height: 1,
              fontWeight: bold ? AppTypography.bold : AppTypography.medium,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipientEditor extends StatefulWidget {
  const _RecipientEditor({
    required this.profile,
    required this.requiresAddress,
  });

  final DeliveryProfile profile;
  final bool requiresAddress;

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
        address: widget.requiresAddress
            ? _addressController.text.trim()
            : widget.profile.address,
        pickupProvider: widget.profile.pickupProvider,
        pickupPointId: widget.profile.pickupPointId,
        pickupPointName: widget.profile.pickupPointName,
        pickupPointAddress: widget.profile.pickupPointAddress,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Получатель',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 20,
              height: 1.1,
              fontWeight: AppTypography.bold,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 18),
          _RecipientField(
            controller: _nameController,
            label: 'Имя и фамилия',
            textInputAction: TextInputAction.next,
          ),
          _RecipientField(
            controller: _phoneController,
            label: 'Телефон',
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
          ),
          _RecipientField(
            controller: _emailController,
            label: 'Email',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          _RecipientField(controller: _cityController, label: 'Город'),
          if (widget.requiresAddress)
            _RecipientField(
              controller: _addressController,
              label: 'Улица, дом, квартира',
            ),
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
                'Сохранить данные',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  fontWeight: AppTypography.semiBold,
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
  const _RecipientField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 16,
          fontWeight: AppTypography.medium,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            fontFamily: AppTypography.fontFamily,
            color: Colors.black.withValues(alpha: 0.5),
            fontWeight: AppTypography.medium,
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
