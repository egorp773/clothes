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
    required this.outfits,
    required this.isSignedIn,
    required this.isSigningIn,
    required this.accountLabel,
    required this.authError,
    required this.onSignInWithYandex,
    required this.onSignInWithTelegram,
    required this.onSignOut,
    required this.onUpdateProfile,
  });

  final AppProfile profile;
  final List<Product> products;
  final List<CreatedOutfit> outfits;
  final bool isSignedIn;
  final bool isSigningIn;
  final String? accountLabel;
  final String? authError;
  final Future<void> Function() onSignInWithYandex;
  final VoidCallback onSignInWithTelegram;
  final Future<void> Function() onSignOut;
  final Future<String?> Function({required String name, required String handle})
  onUpdateProfile;

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
          padding: EdgeInsets.fromLTRB(16, topInset + 18, 16, 120),
          children: [
            const _ProfileTopBar(),
            const SizedBox(height: 24),
            _ProfileHeader(profile: profile),
            const SizedBox(height: 14),
            _RatingCard(rating: profile.rating),
            _PhotoPreviewSection(
              title: 'мои объявления',
              count: products.length,
              images: products.map((product) => product.image).take(3).toList(),
              onOpen: () => _openProducts(context),
            ),
            _PhotoPreviewSection(
              title: 'мои образы',
              count: outfitCards.length,
              images: outfitCards
                  .map((outfit) => outfit.image)
                  .take(3)
                  .toList(),
              topPadding: 8,
              onOpen: () => _openOutfits(context),
            ),
            const SizedBox(height: 2),
            const _ProfileMenuSection(
              rows: [
                _MenuRowData('мои заказы'),
                _MenuRowData('избранное'),
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
            const SizedBox(height: 8),
            _LogoutBlock(onSignOut: onSignOut),
          ],
        ),
      ),
    );
  }

  void _openProducts(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _AllProductsScreen(products: products),
      ),
    );
  }

  void _openOutfits(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            _AllOutfitsScreen(outfits: outfits, products: products),
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
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.home_outlined,
              size: 18,
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
            width: 58,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.notifications_none_outlined,
                  size: 16,
                  color: Colors.white,
                ),
                SizedBox(width: 7),
                Icon(Icons.more_horiz, size: 17, color: Colors.white),
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
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFF1F1F1),
          ),
          child: const Icon(
            Icons.person_outline,
            size: 31,
            color: Colors.black,
          ),
        ),
        const SizedBox(width: 13),
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
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                  letterSpacing: 0,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                handle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  height: 1,
                  letterSpacing: 0,
                  color: Color(0xFF8E8E8E),
                ),
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
}

class _RatingCard extends StatelessWidget {
  const _RatingCard({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 58,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(
            rating.toStringAsFixed(1).replaceAll('.', ','),
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: 0,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
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
              fontSize: 10,
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
      padding: EdgeInsets.only(right: 2),
      child: Icon(Icons.star, size: 15, color: Color(0xFFFFB800)),
    );
  }
}

class _PhotoPreviewSection extends StatelessWidget {
  const _PhotoPreviewSection({
    required this.title,
    required this.count,
    required this.images,
    required this.onOpen,
    this.topPadding = 16,
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
              height: 26,
              child: Row(
                children: [
                  Text(
                    count == 0 ? title : '$title • $count',
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      letterSpacing: 0,
                      color: Colors.black,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Colors.black,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 108,
            child: Row(
              children: List.generate(3, (index) {
                final image = index < visibleImages.length
                    ? visibleImages[index]
                    : '';
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: index == 2 ? 0 : 8),
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
      borderRadius: BorderRadius.circular(10),
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

class _AllProductsScreen extends StatelessWidget {
  const _AllProductsScreen({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return _ProfileGridScaffold(
      title: 'мои объявления',
      isEmpty: products.isEmpty,
      emptyText: 'активных объявлений пока нет',
      child: GridView.builder(
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
              // TODO: Toggle product like.
            },
            onShare: () {
              // TODO: Share product.
            },
          );
        },
      ),
    );
  }
}

class _AllOutfitsScreen extends StatelessWidget {
  const _AllOutfitsScreen({required this.outfits, required this.products});

  final List<CreatedOutfit> outfits;
  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return _ProfileGridScaffold(
      title: 'мои образы',
      isEmpty: outfits.isEmpty,
      emptyText: 'активных образов пока нет',
      backgroundColor: _outfitMediaBackground,
      topPadding: 4,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
        physics: const BouncingScrollPhysics(),
        itemCount: outfits.length,
        separatorBuilder: (context, index) => const SizedBox(height: 18),
        itemBuilder: (context, index) {
          return _ProfileOutfitCard(outfit: outfits[index], products: products);
        },
      ),
    );
  }
}

class _ProfileOutfitCard extends StatefulWidget {
  const _ProfileOutfitCard({required this.outfit, required this.products});

  final CreatedOutfit outfit;
  final List<Product> products;

  @override
  State<_ProfileOutfitCard> createState() => _ProfileOutfitCardState();
}

class _ProfileOutfitCardState extends State<_ProfileOutfitCard> {
  late final PageController _pageController;
  bool _isLiked = false;

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
            top: 488,
            child: _OutfitAuthorCard(
              authorName: widget.outfit.authorName.trim().isEmpty
                  ? 'Автор'
                  : widget.outfit.authorName,
              authorHandle: widget.outfit.authorHandle.trim().isEmpty
                  ? '@user'
                  : widget.outfit.authorHandle,
              isLiked: _isLiked,
              likesCount: 0,
              onLikeTap: () {
                setState(() => _isLiked = !_isLiked);
              },
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
      height: 520 * scale,
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
      padding: EdgeInsets.fromLTRB(16 * scale, 58 * scale, 0, 22 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(30 * scale),
        ),
      ),
      child: SizedBox(
        height: 86 * scale,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.only(right: 16 * scale),
          itemCount: products.length,
          separatorBuilder: (context, index) => SizedBox(width: 12 * scale),
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
      width: 80 * scale,
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
                    size: 28 * scale,
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
  });

  final String title;
  final bool isEmpty;
  final String emptyText;
  final Widget child;
  final Color backgroundColor;
  final double topPadding;

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
    this.height = 46,
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
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 12,
                  fontWeight: textWeight,
                  height: 1,
                  letterSpacing: 0,
                  color: Colors.black,
                ),
              ),
            ),
            if (showChevron)
              const Icon(Icons.chevron_right, size: 16, color: Colors.black),
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
          height: 48,
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
      width: 18,
      height: 18,
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
        height: 44,
        child: Row(
          children: [
            Icon(icon, size: 17, color: Colors.black),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 12,
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
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1,
                letterSpacing: 0,
                color: Color(0xFF8E8E8E),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 16, color: Colors.black),
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
          height: 42,
          textWeight: FontWeight.w500,
          showChevron: true,
        ),
        _MenuRow(
          title: 'документы',
          height: 42,
          textWeight: FontWeight.w500,
          showChevron: true,
        ),
        _MenuRow(
          title: 'вакансии',
          height: 42,
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
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'выйти из профиля',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      letterSpacing: 0,
                      color: Colors.black,
                    ),
                  ),
                ),
                Icon(Icons.logout, size: 18, color: Color(0xFFFF3B30)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'версия приложения 1.0',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 9,
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
