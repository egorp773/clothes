import 'package:flutter/material.dart';

import '../models/app_profile.dart';
import '../models/created_outfit.dart';
import '../models/product.dart';
import '../widgets/app_image.dart';

const _outfitMediaBackground = Color(0xFFF4F4F4);
const _outfitItemBackground = Color(0xFFFFFFFF);

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.profile,
    required this.products,
    required this.likedProducts,
    required this.likedOutfits,
    required this.recentlyViewedProducts,
    required this.recentlyViewedOutfits,
    required this.outfits,
    required this.allProducts,
    required this.isSignedIn,
    required this.isSigningIn,
    required this.accountLabel,
    required this.authError,
    required this.onSignInWithYandex,
    required this.onSignInWithTelegram,
    required this.onSignOut,
    required this.onUpdateProfile,
    required this.onToggleProductLike,
    required this.onToggleOutfitLike,
  });

  final AppProfile profile;
  final List<Product> products;
  final List<Product> likedProducts;
  final List<CreatedOutfit> likedOutfits;
  final List<Product> recentlyViewedProducts;
  final List<CreatedOutfit> recentlyViewedOutfits;
  final List<CreatedOutfit> outfits;
  final List<Product> allProducts;
  final bool isSignedIn;
  final bool isSigningIn;
  final String? accountLabel;
  final String? authError;
  final Future<void> Function() onSignInWithYandex;
  final VoidCallback onSignInWithTelegram;
  final Future<void> Function() onSignOut;
  final Future<String?> Function({required String name, required String handle})
  onUpdateProfile;
  final Future<void> Function(String productId) onToggleProductLike;
  final Future<void> Function(String outfitId) onToggleOutfitLike;

  @override
  Widget build(BuildContext context) {
    final outfitCards = outfits.map(_ProfileOutfit.fromOutfit).toList();
    final topInset = MediaQuery.of(context).viewPadding.top;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(18, topInset + 20, 18, 136),
          children: [
            const _ProfileTopBar(),
            const SizedBox(height: 27),
            _ProfileHeader(profile: profile),
            const SizedBox(height: 16),
            _RatingCard(rating: profile.rating),
            _ProfileShortcutSection(
              favoritesCount: likedProducts.length + likedOutfits.length,
              recentCount:
                  recentlyViewedProducts.length + recentlyViewedOutfits.length,
              onFavoritesTap: () => _openLikedProducts(context),
              onRecentTap: () => _openRecentlyViewedProducts(context),
            ),
            _PhotoPreviewSection(
              title: 'мои объявления',
              count: products.length,
              images: products.map((product) => product.image).take(3).toList(),
              topPadding: 10,
              onOpen: () => _openProducts(context),
            ),
            _PhotoPreviewSection(
              title: 'мои образы',
              count: outfitCards.length,
              images: outfitCards
                  .map((outfit) => outfit.image)
                  .take(3)
                  .toList(),
              topPadding: 10,
              onOpen: () => _openOutfits(context),
            ),
            const SizedBox(height: 4),
            const _ProfileMenuSection(
              rows: [
                _MenuRowData('мои заказы'),
                _MenuRowData('уведомления'),
                _MenuRowData('настройки уведомлений'),
                _MenuRowData('мои адреса'),
                _MenuRowData('подарочная карта'),
                _MenuRowData('дашборд продавца'),
              ],
            ),
            const _CountrySection(),
            const _SupportSection(),
            const _InfoSection(),
            const SizedBox(height: 10),
            _LogoutBlock(onSignOut: onSignOut),
          ],
        ),
      ),
    );
  }

  void _openProducts(BuildContext context) {
    _openProductList(
      context,
      title: 'мои объявления',
      emptyText: 'активных объявлений пока нет',
      products: products,
    );
  }

  void _openLikedProducts(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ProfileCollectionScreen(
          title: 'избранное',
          productEmptyText: 'в избранном пока нет вещей',
          outfitEmptyText: 'в избранном пока нет образов',
          products: likedProducts,
          outfits: likedOutfits,
          allProducts: allProducts,
          onToggleProductLike: onToggleProductLike,
          onToggleOutfitLike: onToggleOutfitLike,
        ),
      ),
    );
  }

  void _openRecentlyViewedProducts(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ProfileCollectionScreen(
          title: 'недавно просмотренное',
          productEmptyText: 'просмотренных вещей пока нет',
          outfitEmptyText: 'просмотренных образов пока нет',
          products: recentlyViewedProducts,
          outfits: recentlyViewedOutfits,
          allProducts: allProducts,
          onToggleProductLike: onToggleProductLike,
          onToggleOutfitLike: onToggleOutfitLike,
        ),
      ),
    );
  }

  void _openProductList(
    BuildContext context, {
    required String title,
    required String emptyText,
    required List<Product> products,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _AllProductsScreen(
          title: title,
          emptyText: emptyText,
          products: products,
          onToggleLike: onToggleProductLike,
        ),
      ),
    );
  }

  void _openOutfits(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _AllOutfitsScreen(
          outfits: outfits,
          products: allProducts,
          onToggleLike: onToggleOutfitLike,
        ),
      ),
    );
  }
}

class _ProfileTopBar extends StatelessWidget {
  const _ProfileTopBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            // TODO: Navigate to main screen.
          },
          child: Container(
            width: 39,
            height: 39,
            decoration: const BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.ios_share_outlined,
              size: 21,
              color: Colors.white,
            ),
          ),
        ),
        const Spacer(),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            // TODO: Open notifications or profile actions.
          },
          child: Container(
            width: 66,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.notifications_none_outlined,
                  size: 18,
                  color: Colors.white,
                ),
                SizedBox(width: 8),
                Icon(Icons.settings_outlined, size: 18, color: Colors.white),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});

  final AppProfile profile;

  @override
  Widget build(BuildContext context) {
    final displayName = profile.name.trim().isEmpty
        ? 'Имя Фамилия'
        : profile.name.trim();
    final handle = _normalizedHandle(profile.handle);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 74,
          height: 74,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFF1F1F1),
          ),
          child: const Icon(
            Icons.person_outline,
            size: 36,
            color: Colors.black,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                  letterSpacing: 0,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      handle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        height: 1,
                        letterSpacing: 0,
                        color: Color(0xFF8E8E8E),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _formatFollowers(profile.followersCount),
                    maxLines: 1,
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1,
                      letterSpacing: 0,
                      color: Colors.black,
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

  static String _normalizedHandle(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '@user';
    return trimmed.startsWith('@') ? trimmed : '@$trimmed';
  }

  static String _formatFollowers(int count) {
    if (count == 1) return '1 подписчик';
    if (count > 1 && count < 5) return '$count подписчика';
    return '$count подписчиков';
  }
}

class _RatingCard extends StatelessWidget {
  const _RatingCard({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 66,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 21),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Text(
            rating.toStringAsFixed(1).replaceAll('.', ','),
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 25,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: 0,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          const Row(
            children: [
              _RatingStar(),
              _RatingStar(),
              _RatingStar(),
              _RatingStar(),
              _RatingStar(),
            ],
          ),
          const Spacer(),
          const Text(
            '102 отзыва',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              height: 1,
              letterSpacing: 0,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingStar extends StatelessWidget {
  const _RatingStar();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(right: 2.5),
      child: Icon(Icons.star, size: 17, color: Color(0xFFFFB800)),
    );
  }
}

class _ProfileShortcutSection extends StatelessWidget {
  const _ProfileShortcutSection({
    required this.favoritesCount,
    required this.recentCount,
    required this.onFavoritesTap,
    required this.onRecentTap,
  });

  final int favoritesCount;
  final int recentCount;
  final VoidCallback onFavoritesTap;
  final VoidCallback onRecentTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Row(
        children: [
          Expanded(
            child: _ProfileShortcutTile(
              icon: Icons.favorite_border,
              title: 'избранное',
              count: favoritesCount,
              isDark: false,
              onTap: onFavoritesTap,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ProfileShortcutTile(
              icon: Icons.history,
              title: 'недавно просмотренное',
              count: recentCount,
              isDark: false,
              onTap: onRecentTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileShortcutTile extends StatelessWidget {
  const _ProfileShortcutTile({
    required this.icon,
    required this.title,
    required this.count,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final int count;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isDark ? Colors.black : const Color(0xFFDCDCE0);
    final foregroundColor = isDark ? Colors.white : Colors.black;
    final iconBackground = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 104,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? Colors.black : const Color(0xFFEDEDEF),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 19, color: foregroundColor),
                ),
                const Spacer(),
                Container(
                  constraints: const BoxConstraints(minWidth: 28),
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.14)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    count.toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      letterSpacing: 0,
                      color: foregroundColor,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.08,
                letterSpacing: 0,
                color: foregroundColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPreviewSection extends StatelessWidget {
  const _PhotoPreviewSection({
    required this.title,
    required this.count,
    required this.images,
    required this.onOpen,
    this.topPadding = 18,
  });

  final String title;
  final int count;
  final List<String> images;
  final VoidCallback onOpen;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final visibleImages = images.take(3).toList();

    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpen,
            child: SizedBox(
              height: 30,
              child: Row(
                children: [
                  Text(
                    count == 0 ? title : '$title • $count',
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      letterSpacing: 0,
                      color: Colors.black,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.chevron_right,
                    size: 21,
                    color: Colors.black,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 124,
            child: Row(
              children: List.generate(3, (index) {
                final image = index < visibleImages.length
                    ? visibleImages[index]
                    : '';
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: index == 2 ? 0 : 10),
                    child: _PreviewPhoto(image: image),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewPhoto extends StatelessWidget {
  const _PreviewPhoto({required this.image});

  final String image;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: _outfitMediaBackground,
        child: image.trim().isEmpty
            ? const SizedBox.expand()
            : AppImage(
                imageUrl: image,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.fill,
                placeholderColor: _outfitMediaBackground,
              ),
      ),
    );
  }
}

class _ProfileCollectionScreen extends StatefulWidget {
  const _ProfileCollectionScreen({
    required this.title,
    required this.productEmptyText,
    required this.outfitEmptyText,
    required this.products,
    required this.outfits,
    required this.allProducts,
    required this.onToggleProductLike,
    required this.onToggleOutfitLike,
  });

  final String title;
  final String productEmptyText;
  final String outfitEmptyText;
  final List<Product> products;
  final List<CreatedOutfit> outfits;
  final List<Product> allProducts;
  final Future<void> Function(String productId) onToggleProductLike;
  final Future<void> Function(String outfitId) onToggleOutfitLike;

  @override
  State<_ProfileCollectionScreen> createState() =>
      _ProfileCollectionScreenState();
}

class _ProfileCollectionScreenState extends State<_ProfileCollectionScreen> {
  int _selectedTab = 0;

  bool get _showsProducts => _selectedTab == 0;

  @override
  Widget build(BuildContext context) {
    return _ProfileGridScaffold(
      title: widget.title,
      isEmpty: _showsProducts
          ? widget.products.isEmpty
          : widget.outfits.isEmpty,
      emptyText: _showsProducts
          ? widget.productEmptyText
          : widget.outfitEmptyText,
      backgroundColor: _showsProducts ? Colors.white : _outfitMediaBackground,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
        child: _ProfileCollectionTabs(
          selectedIndex: _selectedTab,
          onChanged: (index) => setState(() => _selectedTab = index),
        ),
      ),
      child: _showsProducts
          ? _ProductsGrid(
              products: widget.products,
              onToggleLike: widget.onToggleProductLike,
            )
          : _OutfitsList(
              outfits: widget.outfits,
              products: widget.allProducts,
              onToggleLike: widget.onToggleOutfitLike,
            ),
    );
  }
}

class _ProfileCollectionTabs extends StatelessWidget {
  const _ProfileCollectionTabs({
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _ProfileCollectionTab(
            label: 'вещи',
            isActive: selectedIndex == 0,
            onTap: () => onChanged(0),
          ),
          _ProfileCollectionTab(
            label: 'образы',
            isActive: selectedIndex == 1,
            onTap: () => onChanged(1),
          ),
        ],
      ),
    );
  }
}

class _ProfileCollectionTab extends StatelessWidget {
  const _ProfileCollectionTab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? Colors.black : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: 0,
              color: isActive ? Colors.white : const Color(0xFF070707),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductsGrid extends StatelessWidget {
  const _ProductsGrid({required this.products, required this.onToggleLike});

  final List<Product> products;
  final Future<void> Function(String productId) onToggleLike;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 120),
      physics: const BouncingScrollPhysics(),
      itemCount: products.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 7,
        mainAxisSpacing: 4,
        mainAxisExtent: 320,
      ),
      itemBuilder: (context, index) {
        return _CatalogProductCard(
          product: products[index],
          onTap: () {
            // TODO: Open product details.
          },
          onMenu: () {
            // TODO: Open product actions.
          },
          onLike: () {
            onToggleLike(products[index].id);
          },
          onShare: () {
            // TODO: Share product.
          },
        );
      },
    );
  }
}

class _OutfitsList extends StatelessWidget {
  const _OutfitsList({
    required this.outfits,
    required this.products,
    required this.onToggleLike,
  });

  final List<CreatedOutfit> outfits;
  final List<Product> products;
  final Future<void> Function(String outfitId) onToggleLike;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      physics: const BouncingScrollPhysics(),
      itemCount: outfits.length,
      separatorBuilder: (context, index) => const SizedBox(height: 18),
      itemBuilder: (context, index) {
        return _ProfileOutfitCard(
          outfit: outfits[index],
          products: products,
          onToggleLike: () => onToggleLike(outfits[index].id),
        );
      },
    );
  }
}

class _AllProductsScreen extends StatelessWidget {
  const _AllProductsScreen({
    required this.title,
    required this.emptyText,
    required this.products,
    required this.onToggleLike,
  });

  final String title;
  final String emptyText;
  final List<Product> products;
  final Future<void> Function(String productId) onToggleLike;

  @override
  Widget build(BuildContext context) {
    return _ProfileGridScaffold(
      title: title,
      isEmpty: products.isEmpty,
      emptyText: emptyText,
      child: _ProductsGrid(products: products, onToggleLike: onToggleLike),
    );
  }
}

class _AllOutfitsScreen extends StatelessWidget {
  const _AllOutfitsScreen({
    required this.outfits,
    required this.products,
    required this.onToggleLike,
  });

  final List<CreatedOutfit> outfits;
  final List<Product> products;
  final Future<void> Function(String outfitId) onToggleLike;

  @override
  Widget build(BuildContext context) {
    return _ProfileGridScaffold(
      title: 'мои образы',
      isEmpty: outfits.isEmpty,
      emptyText: 'активных образов пока нет',
      backgroundColor: _outfitMediaBackground,
      topPadding: 4,
      child: _OutfitsList(
        outfits: outfits,
        products: products,
        onToggleLike: onToggleLike,
      ),
    );
  }
}

class _ProfileOutfitCard extends StatefulWidget {
  const _ProfileOutfitCard({
    required this.outfit,
    required this.products,
    required this.onToggleLike,
  });

  final CreatedOutfit outfit;
  final List<Product> products;
  final VoidCallback onToggleLike;

  @override
  State<_ProfileOutfitCard> createState() => _ProfileOutfitCardState();
}

class _ProfileOutfitCardState extends State<_ProfileOutfitCard> {
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
    const scale = 1.0;
    final outfitProducts = widget.outfit.items.map((item) {
      final product = _productsById[item.id];
      return _OutfitProductPreview(
        name: item.name,
        price: item.price,
        image: product?.outfitDisplayImage ?? item.image,
      );
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
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
              _OutfitHeroMedia(
                scale: scale,
                photos: widget.outfit.photos,
                pageController: _pageController,
              ),
              _OutfitProductsStrip(scale: scale, products: outfitProducts),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 398,
            child: _OutfitAuthorCard(
              authorName: widget.outfit.authorName.trim().isEmpty
                  ? 'Автор'
                  : widget.outfit.authorName,
              authorHandle: widget.outfit.authorHandle.trim().isEmpty
                  ? '@user'
                  : widget.outfit.authorHandle,
              isLiked: widget.outfit.isLiked,
              likesCount: 0,
              onLikeTap: widget.onToggleLike,
              onAuthorTap: () {
                // TODO: Open author profile.
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OutfitHeroMedia extends StatelessWidget {
  const _OutfitHeroMedia({
    required this.scale,
    required this.photos,
    required this.pageController,
  });

  final double scale;
  final List<String> photos;
  final PageController pageController;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 430 * scale,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30 * scale)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: pageController,
              itemCount: photos.isEmpty ? 1 : photos.length,
              itemBuilder: (context, index) {
                if (photos.isEmpty) {
                  return const DecoratedBox(
                    decoration: BoxDecoration(color: _outfitMediaBackground),
                  );
                }
                return AppImage(
                  imageUrl: photos[index],
                  fit: BoxFit.fill,
                  alignment: Alignment.topCenter,
                  placeholderColor: _outfitMediaBackground,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _OutfitAuthorCard extends StatelessWidget {
  const _OutfitAuthorCard({
    required this.authorName,
    required this.authorHandle,
    required this.isLiked,
    required this.likesCount,
    required this.onLikeTap,
    required this.onAuthorTap,
  });

  final String authorName;
  final String authorHandle;
  final bool isLiked;
  final int likesCount;
  final VoidCallback onLikeTap;
  final VoidCallback onAuthorTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onAuthorTap,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
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
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE9E9EC),
              ),
              child: const Icon(
                Icons.person_outline,
                size: 20,
                color: Color(0xFF8F8F94),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.05,
                      letterSpacing: 0,
                      color: Color(0xFF111111),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$authorHandle • $likesCount лайков',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      height: 1,
                      letterSpacing: 0,
                      color: Color(0xFF8F8F94),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onLikeTap,
              child: Icon(
                isLiked ? Icons.favorite : Icons.favorite_outline,
                size: 22,
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

class _OutfitProductsStrip extends StatelessWidget {
  const _OutfitProductsStrip({required this.scale, required this.products});

  final double scale;
  final List<_OutfitProductPreview> products;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16 * scale, 42 * scale, 0, 12 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(30 * scale),
        ),
      ),
      child: SizedBox(
        height: 84 * scale,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.only(right: 16 * scale),
          itemCount: products.length,
          separatorBuilder: (context, index) => SizedBox(width: 10 * scale),
          itemBuilder: (context, index) {
            return _OutfitProductCard(scale: scale, product: products[index]);
          },
        ),
      ),
    );
  }
}

class _OutfitProductCard extends StatelessWidget {
  const _OutfitProductCard({required this.scale, required this.product});

  final double scale;
  final _OutfitProductPreview product;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 74 * scale,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 48 * scale,
            height: 48 * scale,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _outfitItemBackground,
                borderRadius: BorderRadius.circular(5 * scale),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5 * scale),
                child: product.image.trim().isEmpty
                    ? Container(
                        color: _outfitItemBackground,
                        child: Icon(
                          Icons.checkroom_outlined,
                          size: 24 * scale,
                          color: const Color(0xFFB8B8BD),
                        ),
                      )
                    : AppImage(
                        imageUrl: product.image,
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        placeholderColor: _outfitItemBackground,
                      ),
              ),
            ),
          ),
          SizedBox(height: 3 * scale),
          Text(
            product.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 9.5 * scale,
              fontWeight: FontWeight.w600,
              height: 1,
              letterSpacing: 0,
              color: const Color(0xFF111111),
            ),
          ),
          SizedBox(height: 1.5 * scale),
          Text(
            product.price,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 10 * scale,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: 0,
              color: const Color(0xFF8F8F94),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutfitProductPreview {
  const _OutfitProductPreview({
    required this.name,
    required this.price,
    required this.image,
  });

  final String name;
  final String price;
  final String image;
}

class _ProfileGridScaffold extends StatelessWidget {
  const _ProfileGridScaffold({
    required this.title,
    required this.isEmpty,
    required this.emptyText,
    required this.child,
    this.backgroundColor = Colors.white,
    this.topPadding = 12,
    this.header,
  });

  final String title;
  final bool isEmpty;
  final String emptyText;
  final Widget child;
  final Color backgroundColor;
  final double topPadding;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).viewPadding.top;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(12, topInset + topPadding, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 34,
                      height: 34,
                    ),
                    splashRadius: 18,
                    icon: const Icon(
                      Icons.chevron_left,
                      size: 28,
                      color: Colors.black,
                    ),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        letterSpacing: 0,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ?header,
            Expanded(
              child: isEmpty
                  ? Center(
                      child: Text(
                        emptyText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.25,
                          letterSpacing: 0,
                          color: Color(0xFF8E8E8E),
                        ),
                      ),
                    )
                  : child,
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogProductCard extends StatelessWidget {
  const _CatalogProductCard({
    required this.product,
    required this.onTap,
    required this.onMenu,
    required this.onLike,
    required this.onShare,
  });

  final Product product;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  final VoidCallback onLike;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CatalogImageCard(
              image: product.image,
              dotsOnDark: product.dotsOnDark,
              onMenu: onMenu,
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: SizedBox(
                height: 50,
                child: _CatalogInfo(
                  title: product.title,
                  price: product.price,
                  isLiked: product.isLiked,
                  onLike: onLike,
                  onShare: onShare,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogImageCard extends StatelessWidget {
  const _CatalogImageCard({
    required this.image,
    this.dotsOnDark = false,
    this.onMenu,
  });

  final String image;
  final bool dotsOnDark;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final dotColor = dotsOnDark ? Colors.white : const Color(0xFF070707);

    return SizedBox(
      width: double.infinity,
      height: 266,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8F9),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: AppImage(
                  imageUrl: image,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.fill,
                  alignment: Alignment.center,
                ),
              ),
            ),
            if (onMenu != null)
              Positioned(
                right: 12,
                top: 12,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onMenu,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.more_horiz, size: 21, color: dotColor),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CatalogInfo extends StatelessWidget {
  const _CatalogInfo({
    required this.title,
    required this.price,
    required this.isLiked,
    required this.onLike,
    required this.onShare,
  });

  final String title;
  final String price;
  final bool isLiked;
  final VoidCallback onLike;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            height: 1.08,
            letterSpacing: 0,
            color: Color(0xFF070707),
          ),
        ),
        const SizedBox(height: 1),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                price,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  letterSpacing: 0,
                  color: Color(0xFF070707),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _IconTapTarget(
              onTap: onLike,
              child: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border,
                size: 23,
                color: const Color(0xFF070707),
              ),
            ),
            const SizedBox(width: 4),
            _IconTapTarget(
              onTap: onShare,
              child: const Icon(
                Icons.near_me_outlined,
                size: 23,
                color: Color(0xFF070707),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _IconTapTarget extends StatelessWidget {
  const _IconTapTarget({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(width: 28, height: 28, child: Center(child: child)),
    );
  }
}

class _ProfileOutfit {
  const _ProfileOutfit({
    required this.title,
    required this.price,
    required this.image,
  });

  final String title;
  final String price;
  final String image;

  factory _ProfileOutfit.fromOutfit(CreatedOutfit outfit) {
    return _ProfileOutfit(
      title: 'образ',
      price: _formatOutfitPrice(outfit.items),
      image: outfit.photos.isNotEmpty
          ? outfit.photos.first
          : outfit.items.isNotEmpty
          ? outfit.items.first.image
          : '',
    );
  }

  static String _formatOutfitPrice(List<OutfitItem> items) {
    final total = items.fold<int>(
      0,
      (sum, item) =>
          sum +
          (int.tryParse(item.price.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0),
    );
    if (total <= 0) return 'цена не указана';

    final raw = total.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final remaining = raw.length - i;
      buffer.write(raw[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(' ');
      }
    }
    return '$buffer ₽';
  }
}

class _ProfileMenuSection extends StatelessWidget {
  const _ProfileMenuSection({required this.rows});

  final List<_MenuRowData> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SectionDivider(),
        ...rows.map(
          (row) => _MenuRow(
            title: row.title,
            onTap: () {
              // TODO: Open profile menu item.
            },
          ),
        ),
      ],
    );
  }
}

class _MenuRowData {
  const _MenuRowData(this.title);

  final String title;
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.title,
    this.leading,
    this.showChevron = true,
    this.height = 52,
    this.textWeight = FontWeight.w600,
    this.onTap,
  });

  final String title;
  final Widget? leading;
  final bool showChevron;
  final double height;
  final FontWeight textWeight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 13.5,
                  fontWeight: textWeight,
                  height: 1,
                  letterSpacing: 0,
                  color: Colors.black,
                ),
              ),
            ),
            if (showChevron)
              const Icon(Icons.chevron_right, size: 19, color: Colors.black),
          ],
        ),
      ),
    );
  }
}

class _CountrySection extends StatelessWidget {
  const _CountrySection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SectionDivider(),
        _MenuRow(
          title: 'Россия',
          height: 54,
          leading: const _RussiaFlag(),
          onTap: () {
            // TODO: Open country selector.
          },
        ),
      ],
    );
  }
}

class _RussiaFlag extends StatelessWidget {
  const _RussiaFlag();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 21,
      height: 21,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      child: const Column(
        children: [
          Expanded(child: ColoredBox(color: Colors.white)),
          Expanded(child: ColoredBox(color: Color(0xFF1C57A7))),
          Expanded(child: ColoredBox(color: Color(0xFFE53935))),
        ],
      ),
    );
  }
}

class _SupportSection extends StatelessWidget {
  const _SupportSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SectionDivider(),
        _SupportRow(
          icon: Icons.chat_bubble_outline,
          title: 'написать в поддержку',
          meta: 'онлайн',
          onTap: () {
            // TODO: Open support chat.
          },
        ),
        _SupportRow(
          icon: Icons.phone_outlined,
          title: 'позвонить',
          meta: 'в сети 24/7',
          onTap: () {
            // TODO: Start support call.
          },
        ),
        _SupportRow(
          icon: Icons.help_outline,
          title: 'FAQ',
          meta: 'частые вопросы',
          onTap: () {
            // TODO: Open FAQ.
          },
        ),
      ],
    );
  }
}

class _SupportRow extends StatelessWidget {
  const _SupportRow({
    required this.icon,
    required this.title,
    required this.meta,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.black),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1,
                  letterSpacing: 0,
                  color: Colors.black,
                ),
              ),
            ),
            Text(
              meta,
              style: const TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1,
                letterSpacing: 0,
                color: Color(0xFF8E8E8E),
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right, size: 19, color: Colors.black),
          ],
        ),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _SectionDivider(),
        _MenuRow(
          title: 'доставка и оплата',
          height: 48,
          textWeight: FontWeight.w500,
          showChevron: true,
        ),
        _MenuRow(
          title: 'документы',
          height: 48,
          textWeight: FontWeight.w500,
          showChevron: true,
        ),
        _MenuRow(
          title: 'вакансии',
          height: 48,
          textWeight: FontWeight.w500,
          showChevron: true,
        ),
      ],
    );
  }
}

class _LogoutBlock extends StatelessWidget {
  const _LogoutBlock({required this.onSignOut});

  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SectionDivider(),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSignOut,
          child: const SizedBox(
            height: 54,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'выйти из профиля',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      letterSpacing: 0,
                      color: Colors.black,
                    ),
                  ),
                ),
                Icon(Icons.logout, size: 21, color: Color(0xFFFF3B30)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'версия приложения 1.0',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              height: 1,
              letterSpacing: 0,
              color: Color(0xFF8E8E8E),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 1,
      margin: const EdgeInsets.only(top: 4),
      color: const Color(0xFFE6E6E6),
    );
  }
}
