import 'package:flutter/material.dart';

import '../models/app_profile.dart';
import '../models/product.dart';
import '../widgets/app_image.dart';
import 'reviews_screen.dart';

class SellerProfileScreen extends StatefulWidget {
  const SellerProfileScreen({
    super.key,
    required this.sourceProduct,
    required this.initialProducts,
    required this.loadProfile,
    required this.loadProducts,
    required this.onProductTap,
    required this.onToggleLike,
    required this.onShare,
    required this.onMessage,
    required this.loadReviews,
    required this.onCreateReview,
    required this.canCreateReview,
  });

  final Product sourceProduct;
  final List<Product> initialProducts;
  final Future<SellerProfile?> Function(Product product) loadProfile;
  final Future<List<Product>> Function(String sellerId) loadProducts;
  final ValueChanged<Product> onProductTap;
  final Future<void> Function(String productId) onToggleLike;
  final ValueChanged<Product> onShare;
  final Future<void> Function(SellerProfile seller) onMessage;
  final Future<List<SellerReview>> Function(String sellerId) loadReviews;
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
  final bool canCreateReview;

  @override
  State<SellerProfileScreen> createState() => _SellerProfileScreenState();
}

class _SellerProfileScreenState extends State<SellerProfileScreen> {
  late SellerProfile _seller;
  late List<Product> _products;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _seller = SellerProfile(
      id: widget.sourceProduct.ownerId,
      name: widget.sourceProduct.sellerName,
      handle: widget.sourceProduct.sellerHandle,
    );
    _products = List<Product>.from(widget.initialProducts);
    _load();
  }

  Future<void> _load() async {
    final profile = await widget.loadProfile(widget.sourceProduct);
    final products = await widget.loadProducts(widget.sourceProduct.ownerId);
    if (!mounted) return;
    setState(() {
      if (profile != null) _seller = profile;
      _products = products;
    });
  }

  List<Product> get _visibleProducts {
    return _products
        .where(
          (product) => _tabIndex == 0 ? !product.isHidden : product.isHidden,
        )
        .toList();
  }

  void _openReviews() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ReviewsScreen(
          seller: _seller,
          sourceProduct: widget.sourceProduct,
          loadReviews: widget.loadReviews,
          onCreateReview: widget.onCreateReview,
          canCreateReview: widget.canCreateReview,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).viewPadding.top;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(18, topInset + 10, 18, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TopBar(onBack: () => Navigator.pop(context)),
                        const SizedBox(height: 28),
                        _SellerHeader(seller: _seller),
                        const SizedBox(height: 16),
                        _SellerMeta(seller: _seller),
                        const SizedBox(height: 18),
                        _RatingPill(seller: _seller, onTap: _openReviews),
                        const SizedBox(height: 22),
                        const Text(
                          'Написать продавцу',
                          style: TextStyle(
                            fontSize: 24,
                            height: 1,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                            color: Color(0xFF050505),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _MessageBar(onTap: () => widget.onMessage(_seller)),
                        const SizedBox(height: 22),
                      ],
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabsHeaderDelegate(
                    tabIndex: _tabIndex,
                    topInset: topInset,
                    onChanged: (index) => setState(() => _tabIndex = index),
                  ),
                ),
                if (_visibleProducts.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        _tabIndex == 0
                            ? 'Активных объявлений нет'
                            : 'Завершенных объявлений нет',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF8C8C91),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(8, 10, 8, 120 + bottomInset),
                    sliver: SliverGrid.builder(
                      itemCount: _visibleProducts.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 7,
                            mainAxisSpacing: 5,
                            mainAxisExtent: 320,
                          ),
                      itemBuilder: (context, index) {
                        final product = _visibleProducts[index];
                        return _SellerProductCard(
                          product: product,
                          onTap: () => widget.onProductTap(product),
                          onLike: () => widget.onToggleLike(product.id),
                          onShare: () => widget.onShare(product),
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

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _TopIconButton(icon: Icons.arrow_back_ios_new, onTap: onBack),
        _TopIconButton(
          icon: Icons.ios_share,
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Профиль продавца готов к отправке'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(icon, color: Colors.black, size: 23),
      ),
    );
  }
}

class _SellerHeader extends StatelessWidget {
  const _SellerHeader({required this.seller});

  final SellerProfile seller;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Avatar(seller: seller),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                seller.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 28,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                  color: Color(0xFF050505),
                ),
              ),
              if (seller.handle.trim().isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  seller.handle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'ПОДПИСАТЬСЯ',
                      style: TextStyle(
                        fontSize: 9.5,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3.2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Flexible(
                    child: Text(
                      _followersText(seller.followersCount),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF242429),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.seller});

  final SellerProfile seller;

  @override
  Widget build(BuildContext context) {
    if (seller.avatarUrl.trim().isNotEmpty) {
      return AppImage(
        imageUrl: seller.avatarUrl,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.circular(999),
      );
    }
    return Container(
      width: 48,
      height: 48,
      decoration: const BoxDecoration(
        color: Color(0xFFEDEDEF),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        seller.name.trim().isEmpty
            ? '?'
            : seller.name.characters.first.toUpperCase(),
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _SellerMeta extends StatelessWidget {
  const _SellerMeta({required this.seller});

  final SellerProfile seller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (seller.city.trim().isNotEmpty)
          Text(
            seller.city,
            style: const TextStyle(
              fontSize: 16,
              height: 1.12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
              color: Color(0xFF050505),
            ),
          ),
        if (seller.city.trim().isNotEmpty) const SizedBox(height: 8),
        const Text(
          'Частное лицо',
          style: TextStyle(
            fontSize: 16,
            height: 1,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
            color: Color(0xFF050505),
          ),
        ),
      ],
    );
  }
}

class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.seller, required this.onTap});

  final SellerProfile seller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rating = seller.salesCount <= 0
        ? 0.0
        : seller.rating.clamp(0, 5).toDouble();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 58,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Text(
              rating.toStringAsFixed(1).replaceAll('.', ','),
              style: const TextStyle(
                fontSize: 28,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: _Stars(rating: rating.toDouble())),
            const SizedBox(width: 14),
            Text(
              '${seller.salesCount} отзывов',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      alignment: Alignment.centerLeft,
      fit: BoxFit.scaleDown,
      child: Row(
        children: List.generate(5, (index) {
          return Icon(
            Icons.star,
            size: 27,
            color: index < rating.round()
                ? const Color(0xFFFFB21A)
                : const Color(0xFFE8E8EA),
          );
        }),
      ),
    );
  }
}

class _MessageBar extends StatelessWidget {
  const _MessageBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: 22, right: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F3),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Row(
          children: [
            Expanded(
              child: Text(
                'введите сообщение',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                  color: Color(0xFF85858A),
                ),
              ),
            ),
            Icon(Icons.send, size: 23, color: Colors.black),
          ],
        ),
      ),
    );
  }
}

class _TabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _TabsHeaderDelegate({
    required this.tabIndex,
    required this.topInset,
    required this.onChanged,
  });

  final int tabIndex;
  final double topInset;
  final ValueChanged<int> onChanged;

  @override
  double get minExtent => topInset + 50;

  @override
  double get maxExtent => topInset + 50;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.white),
      child: Padding(
        padding: EdgeInsets.only(top: topInset),
        child: DecoratedBox(
          decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.black, width: 2),
          bottom: BorderSide(color: Color(0xFFDADADD), width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              label: 'активные',
              isActive: tabIndex == 0,
              onTap: () => onChanged(0),
            ),
          ),
          Expanded(
            child: _TabButton(
              label: 'завершенные',
              isActive: tabIndex == 1,
              onTap: () => onChanged(1),
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabsHeaderDelegate oldDelegate) {
    return oldDelegate.tabIndex != tabIndex || oldDelegate.topInset != topInset;
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
                color: Color(0xFF050505),
              ),
            ),
          ),
          if (isActive)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ColoredBox(
                color: Colors.black,
                child: SizedBox(height: 3),
              ),
            ),
        ],
      ),
    );
  }
}

class _SellerProductCard extends StatefulWidget {
  const _SellerProductCard({
    required this.product,
    required this.onTap,
    required this.onLike,
    required this.onShare,
  });

  final Product product;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onShare;

  @override
  State<_SellerProductCard> createState() => _SellerProductCardState();
}

class _SellerProductCardState extends State<_SellerProductCard> {
  late bool _isLiked = widget.product.isLiked;

  @override
  void didUpdateWidget(covariant _SellerProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.isLiked != widget.product.isLiked) {
      _isLiked = widget.product.isLiked;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: SizedBox(
        height: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 266,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: AppImage(
                  imageUrl: widget.product.image,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.fill,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              widget.product.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.08,
                fontWeight: FontWeight.w500,
                color: Color(0xFF070707),
              ),
            ),
            const SizedBox(height: 1),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.product.price,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF070707),
                    ),
                  ),
                ),
                _SmallIconButton(
                  icon: _isLiked ? Icons.favorite : Icons.favorite_border,
                  onTap: () {
                    setState(() => _isLiked = !_isLiked);
                    widget.onLike();
                  },
                ),
                _SmallIconButton(
                  icon: Icons.near_me_outlined,
                  onTap: widget.onShare,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 30,
        height: 28,
        child: Icon(icon, size: 22, color: Colors.black),
      ),
    );
  }
}

String _followersText(int count) {
  final value = count.toString();
  return '$value подписчика';
}
