import 'package:flutter/material.dart';

import '../models/created_outfit.dart';
import 'product_screen.dart';

class OutfitsScreen extends StatefulWidget {
  final double scale;
  final double sidePadding;
  final List<CreatedOutfit> createdOutfits;
  final VoidCallback onCreateTap;

  const OutfitsScreen({
    super.key,
    required this.scale,
    required this.sidePadding,
    this.createdOutfits = const [],
    required this.onCreateTap,
  });

  @override
  State<OutfitsScreen> createState() => _OutfitsScreenState();
}

class _OutfitsScreenState extends State<OutfitsScreen> {
  bool _isLiked = false;
  int _likesCount = 79;
  int _currentPhotoIndex = 0;
  late final PageController _pageController;

  final List<_OutfitProduct> _products = [
    const _OutfitProduct(
      icon: Icons.diamond_outlined,
      name: 'Подвеска Cross',
      price: '6 900 ₽',
    ),
    const _OutfitProduct(
      icon: Icons.checkroom_outlined,
      name: 'Лонгслив Rebirth',
      price: '8 400 ₽',
    ),
    const _OutfitProduct(
      icon: Icons.dry_cleaning_outlined,
      name: 'Шорты Shadow',
      price: '7 200 ₽',
    ),
    const _OutfitProduct(
      icon: Icons.hiking_outlined,
      name: 'Ботинки Track',
      price: '14 900 ₽',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleLike() {
    setState(() {
      _isLiked = !_isLiked;
      _likesCount += _isLiked ? 1 : -1;
    });
  }

  void _onPageChanged(int index) {
    setState(() => _currentPhotoIndex = index);
  }

  void _showAuthorProfile() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Nightshade',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111111),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Профиль автора будет добавлен позже',
                style: TextStyle(fontSize: 15, color: Color(0xFF8F8F94)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFE7E7EA)),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Center(
                    child: Text(
                      'Закрыть',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0B0B0B),
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

  void _showProductDetails(_OutfitProduct product) {
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.24),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (context, animation, secondaryAnimation) {
          return ProductScreen(
            product: ProductDetailData(
              id: product.name.toLowerCase().replaceAll(' ', '_'),
              title: product.name,
              price: product.price,
              image: 'assets/products/placeholder.jpg',
              brand: 'Brand',
              size: 'M',
              condition: 'Отличное',
              isLiked: false,
            ),
            onLike: () {},
            onAddToCart: () {},
            onContactSeller: () {},
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          0,
          18 * widget.scale,
          0,
          86 * widget.scale,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                widget.sidePadding,
                14,
                widget.sidePadding,
                18,
              ),
              child: _Header(
                scale: widget.scale,
                onCreateTap: widget.onCreateTap,
              ),
            ),
            ...widget.createdOutfits.map(
              (outfit) => Padding(
                padding: EdgeInsets.fromLTRB(
                  widget.sidePadding,
                  0,
                  widget.sidePadding,
                  18 * widget.scale,
                ),
                child: _PublishedOutfitCard(
                  scale: widget.scale,
                  outfit: outfit,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.sidePadding),
              child: _OutfitCard(
                scale: widget.scale,
                products: _products,
                isLiked: _isLiked,
                likesCount: _likesCount,
                currentPhotoIndex: _currentPhotoIndex,
                pageController: _pageController,
                onLikeTap: _toggleLike,
                onAuthorTap: _showAuthorProfile,
                onPageChanged: _onPageChanged,
                onProductTap: _showProductDetails,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.scale, required this.onCreateTap});

  final double scale;
  final VoidCallback onCreateTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Образы',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.35,
                height: 1,
                color: const Color(0xFF070707),
              ),
            ),
          ),
          GestureDetector(
            onTap: onCreateTap,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                Icons.add_circle_outline,
                size: 24,
                color: const Color(0xFF070707),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PublishedOutfitCard extends StatelessWidget {
  const _PublishedOutfitCard({required this.scale, required this.outfit});

  final double scale;
  final CreatedOutfit outfit;

  @override
  Widget build(BuildContext context) {
    final heroPhoto = outfit.photos.isNotEmpty ? outfit.photos.first : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24 * scale),
        border: Border.all(color: const Color(0xFFEFEFF1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 280 * scale,
            width: double.infinity,
            child: heroPhoto == null
                ? Container(
                    color: const Color(0xFFF5F5F6),
                    child: Icon(
                      Icons.checkroom_outlined,
                      size: 72 * scale,
                      color: const Color(0xFFB8B8BE),
                    ),
                  )
                : Image.asset(
                    heroPhoto,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: const Color(0xFFF5F5F6),
                      child: Icon(
                        Icons.checkroom_outlined,
                        size: 72 * scale,
                        color: const Color(0xFFB8B8BE),
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: EdgeInsets.all(14 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Образ',
                  style: TextStyle(
                    fontSize: 16 * scale,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111111),
                  ),
                ),
                SizedBox(height: 10 * scale),
                SizedBox(
                  height: 76 * scale,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: outfit.items.length,
                    separatorBuilder: (context, index) =>
                        SizedBox(width: 10 * scale),
                    itemBuilder: (context, index) {
                      final item = outfit.items[index];
                      return SizedBox(
                        width: 78 * scale,
                        child: Column(
                          children: [
                            Expanded(
                              child: Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF6F6F7),
                                  borderRadius: BorderRadius.circular(
                                    10 * scale,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Image.asset(
                                  item.image,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Icon(
                                        Icons.checkroom_outlined,
                                        size: 22 * scale,
                                      ),
                                ),
                              ),
                            ),
                            SizedBox(height: 5 * scale),
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5 * scale,
                                color: const Color(0xFF111111),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OutfitCard extends StatelessWidget {
  const _OutfitCard({
    required this.scale,
    required this.products,
    required this.isLiked,
    required this.likesCount,
    required this.currentPhotoIndex,
    required this.pageController,
    required this.onLikeTap,
    required this.onAuthorTap,
    required this.onPageChanged,
    required this.onProductTap,
  });

  final double scale;
  final List<_OutfitProduct> products;
  final bool isLiked;
  final int likesCount;
  final int currentPhotoIndex;
  final PageController pageController;
  final VoidCallback onLikeTap;
  final VoidCallback onAuthorTap;
  final ValueChanged<int> onPageChanged;
  final void Function(_OutfitProduct) onProductTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30 * scale),
        border: Border.all(color: const Color(0xFFF0F0F2), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.055),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              _HeroMedia(
                scale: scale,
                pageController: pageController,
                currentPhotoIndex: currentPhotoIndex,
                onPageChanged: onPageChanged,
              ),
              _ProductsSection(
                scale: scale,
                products: products,
                onProductTap: onProductTap,
              ),
            ],
          ),
          Positioned(
            left: 16 * scale,
            right: 16 * scale,
            top: 478 * scale,
            child: _AuthorCard(
              scale: scale,
              isLiked: isLiked,
              likesCount: likesCount,
              onLikeTap: onLikeTap,
              onAuthorTap: onAuthorTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMedia extends StatelessWidget {
  const _HeroMedia({
    required this.scale,
    required this.pageController,
    required this.currentPhotoIndex,
    required this.onPageChanged,
  });

  final double scale;
  final PageController pageController;
  final int currentPhotoIndex;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 520 * scale,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30 * scale)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: pageController,
              onPageChanged: onPageChanged,
              itemCount: 2,
              itemBuilder: (context, index) {
                return const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFF0F0F1),
                        Color(0xFFE6E6E8),
                        Color(0xFFF8F8F8),
                      ],
                    ),
                  ),
                );
              },
            ),
            Positioned(
              left: 36 * scale,
              right: 36 * scale,
              top: 38 * scale,
              bottom: 88 * scale,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.50),
                  borderRadius: BorderRadius.circular(26 * scale),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.76),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.checkroom_outlined,
                  size: 92 * scale,
                  color: const Color(0xFFB5B5BA),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 62 * scale,
              child: _PaginationDots(
                scale: scale,
                currentIndex: currentPhotoIndex,
                totalDots: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaginationDots extends StatelessWidget {
  const _PaginationDots({
    required this.scale,
    required this.currentIndex,
    required this.totalDots,
  });

  final double scale;
  final int currentIndex;
  final int totalDots;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalDots, (index) {
        return Container(
          width: 7 * scale,
          height: 7 * scale,
          margin: EdgeInsets.symmetric(horizontal: 4 * scale),
          decoration: BoxDecoration(
            color: currentIndex == index
                ? const Color(0xFF111111)
                : const Color(0xFFD2D2D6),
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}

class _AuthorCard extends StatelessWidget {
  const _AuthorCard({
    required this.scale,
    required this.isLiked,
    required this.likesCount,
    required this.onLikeTap,
    required this.onAuthorTap,
  });

  final double scale;
  final bool isLiked;
  final int likesCount;
  final VoidCallback onLikeTap;
  final VoidCallback onAuthorTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onAuthorTap,
      child: Container(
        height: 84 * scale,
        padding: EdgeInsets.symmetric(horizontal: 16 * scale),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22 * scale),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.13),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50 * scale,
              height: 50 * scale,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE9E9EC),
              ),
              child: Icon(
                Icons.person_outline,
                size: 25 * scale,
                color: const Color(0xFF8F8F94),
              ),
            ),
            SizedBox(width: 14 * scale),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nightshade',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16 * scale,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.15,
                      height: 1.05,
                      color: const Color(0xFF111111),
                    ),
                  ),
                  SizedBox(height: 6 * scale),
                  Text(
                    '28 июля 2025 · $likesCount лайков',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5 * scale,
                      fontWeight: FontWeight.w400,
                      height: 1,
                      color: const Color(0xFF8F8F94),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 10 * scale),
            GestureDetector(
              onTap: onLikeTap,
              behavior: HitTestBehavior.opaque,
              child: Icon(
                isLiked ? Icons.favorite : Icons.favorite_outline,
                size: 25 * scale,
                color: isLiked
                    ? const Color(0xFFFF3B30)
                    : const Color(0xFF8F8F94),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductsSection extends StatefulWidget {
  const _ProductsSection({
    required this.scale,
    required this.products,
    required this.onProductTap,
  });

  final double scale;
  final List<_OutfitProduct> products;
  final void Function(_OutfitProduct) onProductTap;

  @override
  State<_ProductsSection> createState() => _ProductsSectionState();
}

class _ProductsSectionState extends State<_ProductsSection> {
  late final ScrollController _controller;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController()..addListener(_updateArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  void _updateArrows() {
    if (!_controller.hasClients) return;
    final nextLeft = _controller.offset > 2;
    final nextRight =
        _controller.position.maxScrollExtent - _controller.offset > 2;
    if (nextLeft == _canScrollLeft && nextRight == _canScrollRight) return;
    setState(() {
      _canScrollLeft = nextLeft;
      _canScrollRight = nextRight;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_updateArrows);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        16 * widget.scale,
        58 * widget.scale,
        0,
        22 * widget.scale,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(30 * widget.scale),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 99 * widget.scale,
            child: Stack(
              children: [
                ListView.separated(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(right: 16 * widget.scale),
                  itemCount: widget.products.length,
                  separatorBuilder: (context, index) =>
                      SizedBox(width: 12 * widget.scale),
                  itemBuilder: (context, index) {
                    return _ProductCard(
                      scale: widget.scale,
                      product: widget.products[index],
                      onTap: () => widget.onProductTap(widget.products[index]),
                    );
                  },
                ),
                if (_canScrollLeft)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: _ScrollArrow(
                      scale: widget.scale,
                      icon: Icons.chevron_left,
                    ),
                  ),
                if (_canScrollRight)
                  Positioned(
                    right: 12 * widget.scale,
                    top: 0,
                    bottom: 0,
                    child: _ScrollArrow(
                      scale: widget.scale,
                      icon: Icons.chevron_right,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.scale,
    required this.product,
    required this.onTap,
  });

  final double scale;
  final _OutfitProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 110 * scale,
        child: Container(
          padding: EdgeInsets.all(6 * scale),
          decoration: BoxDecoration(
            color: const Color(0xFFFCFCFC),
            borderRadius: BorderRadius.circular(14 * scale),
            border: Border.all(color: const Color(0xFFEFEFF1), width: 1),
          ),
          child: Column(
            children: [
              Container(
                height: 38 * scale,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10 * scale),
                ),
                child: Icon(
                  product.icon,
                  size: 22 * scale,
                  color: const Color(0xFFB8B8BD),
                ),
              ),
              SizedBox(height: 5 * scale),
              SizedBox(
                height: 22 * scale,
                child: Text(
                  product.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.2 * scale,
                    fontWeight: FontWeight.w500,
                    height: 1.05,
                    color: const Color(0xFF111111),
                  ),
                ),
              ),
              SizedBox(height: 2 * scale),
              Text(
                product.price,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10.8 * scale,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF707076),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrollArrow extends StatelessWidget {
  const _ScrollArrow({required this.scale, required this.icon});

  final double scale;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34 * scale,
      child: Center(
        child: Container(
          width: 28 * scale,
          height: 28 * scale,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, size: 18 * scale, color: const Color(0xFF111111)),
        ),
      ),
    );
  }
}

class _OutfitProduct {
  const _OutfitProduct({
    required this.icon,
    required this.name,
    required this.price,
  });

  final IconData icon;
  final String name;
  final String price;
}
