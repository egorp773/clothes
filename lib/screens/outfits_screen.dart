import 'package:flutter/material.dart';

import '../models/created_outfit.dart';
import '../models/product.dart';
import '../widgets/app_image.dart';
import 'product_screen.dart';

const _outfitMediaBackground = Color(0xFFF4F4F4);
const _outfitItemBackground = Color(0xFFFFFFFF);

class OutfitsScreen extends StatefulWidget {
  final double scale;
  final double sidePadding;
  final List<CreatedOutfit> createdOutfits;
  final List<Product> products;
  final VoidCallback onCreateTap;

  const OutfitsScreen({
    super.key,
    required this.scale,
    required this.sidePadding,
    this.createdOutfits = const [],
    this.products = const [],
    required this.onCreateTap,
  });

  @override
  State<OutfitsScreen> createState() => _OutfitsScreenState();
}

class _OutfitsScreenState extends State<OutfitsScreen> {
  bool _isLiked = false;
  int _likesCount = 79;
  late final PageController _pageController;

  final List<_OutfitProduct> _products = [
    const _OutfitProduct(
      icon: Icons.diamond_outlined,
      name: 'Подвеска Cross',
      price: '6 900 ₽',
      image: 'assets/mock/item_cross.jpg',
    ),
    const _OutfitProduct(
      icon: Icons.checkroom_outlined,
      name: 'Лонгслив Rebirth',
      price: '8 400 ₽',
      image: 'assets/mock/item_longsleeve.jpg',
    ),
    const _OutfitProduct(
      icon: Icons.dry_cleaning_outlined,
      name: 'Шорты Shadow',
      price: '7 200 ₽',
      image: 'assets/mock/item_shorts.jpg',
    ),
    const _OutfitProduct(
      icon: Icons.hiking_outlined,
      name: 'Ботинки Track',
      price: '14 900 ₽',
      image: 'assets/mock/item_boots.jpg',
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
              description: '',
              price: product.price,
              image: product.image ?? '',
              images: product.image == null ? const [] : [product.image!],
              brand: 'Brand',
              sellerName: 'Продавец',
              sellerHandle: '@seller',
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
    final topInset = MediaQuery.of(context).viewPadding.top;

    return Container(
      color: _outfitMediaBackground,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          0,
          topInset + 4 * widget.scale,
          0,
          86 * widget.scale,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                widget.sidePadding,
                8,
                widget.sidePadding,
                14,
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
                  products: widget.products,
                  onAuthorTap: _showAuthorProfile,
                  onProductTap: _showProductDetails,
                ),
              ),
            ),
            if (widget.createdOutfits.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.sidePadding),
                child: _OutfitCard(
                  scale: widget.scale,
                  products: _products,
                  isLiked: _isLiked,
                  likesCount: _likesCount,
                  pageController: _pageController,
                  onLikeTap: _toggleLike,
                  onAuthorTap: _showAuthorProfile,
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
                fontWeight: FontWeight.w500,
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

class _PublishedOutfitCard extends StatefulWidget {
  const _PublishedOutfitCard({
    required this.scale,
    required this.outfit,
    required this.products,
    required this.onAuthorTap,
    required this.onProductTap,
  });

  final double scale;
  final CreatedOutfit outfit;
  final List<Product> products;
  final VoidCallback onAuthorTap;
  final void Function(_OutfitProduct) onProductTap;

  @override
  State<_PublishedOutfitCard> createState() => _PublishedOutfitCardState();
}

class _PublishedOutfitCardState extends State<_PublishedOutfitCard> {
  late final PageController _pageController;

  Map<String, Product> get _productsById {
    return {for (final product in widget.products) product.id: product};
  }

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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30 * widget.scale),
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
                scale: widget.scale,
                photos: widget.outfit.photos,
                previewBackgroundColor: widget.outfit.previewBackgroundColor,
                layoutItems: widget.outfit.layoutItems,
                pageController: _pageController,
              ),
              _ProductsSection(
                scale: widget.scale,
                products: widget.outfit.items.map((item) {
                  final product = _productsById[item.id];
                  return _OutfitProduct(
                    icon: Icons.checkroom_outlined,
                    name: item.name,
                    price: item.price,
                    image: product?.outfitDisplayImage ?? item.image,
                  );
                }).toList(),
                onProductTap: widget.onProductTap,
              ),
            ],
          ),
          Positioned(
            left: 16 * widget.scale,
            right: 16 * widget.scale,
            top: 488 * widget.scale,
            child: _AuthorCard(
              scale: widget.scale,
              authorName: widget.outfit.authorName,
              authorHandle: widget.outfit.authorHandle,
              isLiked: false,
              likesCount: 0,
              onLikeTap: () {},
              onAuthorTap: widget.onAuthorTap,
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
    required this.pageController,
    required this.onLikeTap,
    required this.onAuthorTap,
    required this.onProductTap,
  });

  final double scale;
  final List<_OutfitProduct> products;
  final bool isLiked;
  final int likesCount;
  final PageController pageController;
  final VoidCallback onLikeTap;
  final VoidCallback onAuthorTap;
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
              _HeroMedia(scale: scale, pageController: pageController),
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
            top: 488 * scale,
            child: _AuthorCard(
              scale: scale,
              authorName: 'Nightshade',
              authorHandle: '@nightshade',
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
    this.photos = const [],
    this.previewBackgroundColor,
    this.layoutItems = const [],
    required this.pageController,
  });

  final double scale;
  final List<String> photos;
  final int? previewBackgroundColor;
  final List<OutfitLayoutItem> layoutItems;
  final PageController pageController;

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
            if (layoutItems.isNotEmpty)
              _OutfitLayoutCanvas(
                backgroundColor: Color(
                  previewBackgroundColor ?? _outfitMediaBackground.toARGB32(),
                ),
                items: layoutItems,
              )
            else
              PageView.builder(
                controller: pageController,
                itemCount: photos.isEmpty ? 2 : photos.length,
                itemBuilder: (context, index) {
                  if (photos.isNotEmpty) {
                    return AppImage(
                      imageUrl: photos[index],
                      fit: BoxFit.fill,
                      alignment: Alignment.topCenter,
                      placeholderColor: _outfitMediaBackground,
                    );
                  }
                  return const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFF8F8F8),
                          Color(0xFFF4F4F4),
                          Color(0xFFEFEFEF),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _OutfitLayoutCanvas extends StatelessWidget {
  const _OutfitLayoutCanvas({
    required this.backgroundColor,
    required this.items,
  });

  final Color backgroundColor;
  final List<OutfitLayoutItem> items;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: backgroundColor),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (final item in items)
                Positioned.fill(
                  child: Center(
                    child: Transform.translate(
                      offset: Offset(
                        item.offsetX * constraints.maxWidth,
                        item.offsetY * constraints.maxHeight,
                      ),
                      child: Transform.rotate(
                        angle: item.rotation,
                        child: Transform.scale(
                          scale: item.scale,
                          child: SizedBox(
                            width: constraints.maxWidth * item.widthFactor,
                            height: constraints.maxHeight * item.heightFactor,
                            child: AppImage(
                              imageUrl: item.image,
                              fit: BoxFit.contain,
                              alignment: Alignment.center,
                              placeholderColor: Colors.transparent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AuthorCard extends StatelessWidget {
  const _AuthorCard({
    required this.scale,
    required this.authorName,
    required this.authorHandle,
    required this.isLiked,
    required this.likesCount,
    required this.onLikeTap,
    required this.onAuthorTap,
  });

  final double scale;
  final String authorName;
  final String authorHandle;
  final bool isLiked;
  final int likesCount;
  final VoidCallback onLikeTap;
  final VoidCallback onAuthorTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onAuthorTap,
      child: Container(
        height: 64 * scale,
        padding: EdgeInsets.symmetric(horizontal: 12 * scale),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18 * scale),
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
              width: 38 * scale,
              height: 38 * scale,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE9E9EC),
              ),
              child: Icon(
                Icons.person_outline,
                size: 20 * scale,
                color: const Color(0xFF8F8F94),
              ),
            ),
            SizedBox(width: 10 * scale),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14 * scale,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.15,
                      height: 1.05,
                      color: const Color(0xFF111111),
                    ),
                  ),
                  SizedBox(height: 3 * scale),
                  Text(
                    '$authorHandle · $likesCount лайков',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5 * scale,
                      fontWeight: FontWeight.w500,
                      height: 1,
                      color: const Color(0xFF8F8F94),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8 * scale),
            GestureDetector(
              onTap: onLikeTap,
              behavior: HitTestBehavior.opaque,
              child: Icon(
                isLiked ? Icons.favorite : Icons.favorite_outline,
                size: 22 * scale,
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
            height: 86 * widget.scale,
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
        width: 80 * scale,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _outfitItemBackground,
            borderRadius: BorderRadius.circular(5 * scale),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5 * scale),
            child: product.image == null || product.image!.isEmpty
                ? Container(
                    color: _outfitItemBackground,
                    child: Icon(
                      product.icon,
                      size: 28 * scale,
                      color: const Color(0xFFB8B8BD),
                    ),
                  )
                : AppImage(
                    imageUrl: product.image!,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    placeholderColor: _outfitItemBackground,
                  ),
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
    this.image,
  });

  final IconData icon;
  final String name;
  final String price;
  final String? image;
}
