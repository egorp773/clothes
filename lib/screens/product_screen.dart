import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ProductDetailData {
  const ProductDetailData({
    required this.id,
    required this.title,
    required this.price,
    required this.image,
    required this.brand,
    required this.size,
    required this.condition,
    required this.isLiked,
  });

  final String id;
  final String title;
  final String price;
  final String image;
  final String brand;
  final String size;
  final String condition;
  final bool isLiked;
}

class ProductScreen extends StatefulWidget {
  const ProductScreen({
    super.key,
    required this.product,
    required this.onLike,
    required this.onAddToCart,
    required this.onContactSeller,
  });

  final ProductDetailData product;
  final VoidCallback onLike;
  final VoidCallback onAddToCart;
  final VoidCallback onContactSeller;

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen>
    with TickerProviderStateMixin {
  static const _openDuration = Duration(milliseconds: 500);
  static const _expandDuration = Duration(milliseconds: 280);
  static const _scrollRange = 180.0;
  static const _spacingMin = 24.0;
  static const _spacingMax = 44.0;
  static const _topGapCard = 16.0;
  static const _topRadiusCard = 28.0;
  static const _bottomRadiusCard = 24.0;

  late final AnimationController _openController;
  late final AnimationController _expandController;
  late final Animation<Offset> _slide;
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0;
  bool _isClosing = false;
  double _dragOffset = 0;
  bool _isLiked = false;

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

  void _toggleWishlist() {
    setState(() => _isLiked = !_isLiked);
    widget.onLike();
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
    final topGap = _topGapCard * (1 - tExpand);
    final topRadius = _topRadiusCard * (1 - tExpand);
    final bottomRadius = _bottomRadiusCard * (1 - tExpand);
    final spacing = _spacing;
    final t = (_scrollOffset / _scrollRange).clamp(0.0, 1.0);
    final sellerTopExtra = 92.0 - 80.0 * t;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SlideTransition(
        position: _slide,
        child: Transform.translate(
          offset: Offset(0, _dragOffset),
          child: GestureDetector(
            onVerticalDragUpdate: (details) {
              setState(() {
                _dragOffset = (_dragOffset + details.delta.dy).clamp(
                  0.0,
                  screenHeight * 0.5,
                );
              });
            },
            onVerticalDragEnd: (details) {
              final dismiss =
                  _dragOffset > 80 || (details.primaryVelocity ?? 0) > 200;
              setState(() {
                if (!dismiss) _dragOffset = 0;
              });
              if (dismiss) _closeWithAnimation();
            },
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
                                    gallery: List<String>.filled(
                                      4,
                                      product.image,
                                    ),
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
                                        color: Colors.black.withValues(
                                          alpha: 0.12,
                                        ),
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
                                                fontWeight: FontWeight.w400,
                                                letterSpacing: 0.15,
                                                height: 1.2,
                                              ),
                                            ),
                                            SizedBox(height: spacing),
                                            Text(
                                              product.price,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w400,
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
                                                onTap: widget.onContactSeller,
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        _SellerCard(
                                          hairline: hairline,
                                          name: 'Продавец',
                                          handle:
                                              '@${product.brand.toLowerCase().replaceAll(' ', '')}',
                                          rating: 4.8,
                                          reviews: 126,
                                          onTap: () {},
                                        ),
                                        SizedBox(height: spacing),
                                        const _SectionTitle('Описание'),
                                        const SizedBox(height: 12),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            'Размер: ${product.size}\n'
                                            'Состояние: ${product.condition}\n'
                                            'Бренд: ${product.brand}',
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              height: 1.5,
                                              color: Colors.black.withValues(
                                                alpha: 0.78,
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(height: spacing),
                                        const _SectionTitle(
                                          'Доставка и условия',
                                        ),
                                        const SizedBox(height: 12),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            'Доставка 2-5 дней. Возврат по договоренности с продавцом.',
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              height: 1.5,
                                              color: Colors.black.withValues(
                                                alpha: 0.72,
                                              ),
                                            ),
                                          ),
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
                                  height:
                                      52 +
                                      16 +
                                      MediaQuery.of(context).padding.bottom,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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
                              onPressed: widget.onContactSeller,
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
                                style: TextStyle(
                                  letterSpacing: 0,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
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
        ),
      ),
    );
  }
}

class _HeroImageGallery extends StatefulWidget {
  const _HeroImageGallery({required this.gallery});

  final List<String> gallery;

  @override
  State<_HeroImageGallery> createState() => _HeroImageGalleryState();
}

class _HeroImageGalleryState extends State<_HeroImageGallery> {
  int _currentPage = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pageController.addListener(() {
      setState(() => _currentPage = _pageController.page?.round() ?? 0);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.gallery.length,
            itemBuilder: (context, index) {
              return Container(
                color: const Color(0xFFD9D9DB),
                child: Image.asset(
                  widget.gallery[index],
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(child: Icon(Icons.image_not_supported));
                  },
                ),
              );
            },
          ),
          if (widget.gallery.length > 1)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.gallery.length,
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

class _TopIcon extends StatelessWidget {
  const _TopIcon({
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
            color: isWishlist && icon == CupertinoIcons.heart_fill
                ? Colors.red
                : Colors.black.withValues(alpha: 0.9),
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
    required this.onTap,
  });

  final double hairline;
  final String name;
  final String handle;
  final double rating;
  final int reviews;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.10),
            width: hairline,
          ),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(
                CupertinoIcons.person,
                size: 18,
                color: Colors.black.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        CupertinoIcons.star_fill,
                        size: 14,
                        color: Colors.black.withValues(alpha: 0.75),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        rating.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.black.withValues(alpha: 0.75),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$reviews отзывов',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.black.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    handle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: Colors.black.withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          letterSpacing: 0,
          fontWeight: FontWeight.w700,
          color: Colors.black.withValues(alpha: 0.82),
        ),
      ),
    );
  }
}
