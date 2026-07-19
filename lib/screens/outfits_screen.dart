import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_appearance.dart';
import '../core/app_typography.dart';
import '../core/supabase_config.dart';
import '../features/catalog_search/catalog_search_engine.dart';
import '../models/created_outfit.dart';
import '../models/product.dart';
import '../models/profile_feature.dart';
import '../services/image_download_service.dart';
import '../widgets/app_image.dart';
import '../widgets/app_glass_surface.dart';
import 'product_screen.dart';

const _outfitMediaBackground = Color(0xFFF4F4F4);

class OutfitsScreen extends StatefulWidget {
  final double scale;
  final double sidePadding;
  final List<CreatedOutfit> createdOutfits;
  final List<Product> products;
  final VoidCallback onCreateTap;
  final Future<void> Function(String productId) onToggleProductLike;
  final Future<void> Function(String outfitId) onToggleOutfitLike;
  final Future<int> Function(String productId) onProductViewed;
  final Future<int> Function(String outfitId) onOutfitViewed;
  final Future<void> Function(
    Product product, {
    bool imageOnly,
    Route<dynamic>? sourceRoute,
  })
  onContactSeller;
  final ValueChanged<Product> onOpenSellerProfile;
  final Future<bool> Function({
    required String targetType,
    required String targetId,
    required String reason,
    String details,
  })?
  onSubmitContentReport;
  final DeliveryProfile deliveryProfile;
  final Future<void> Function(DeliveryProfile profile) onSaveDeliveryProfile;
  final Future<AppOrder?> Function(
    Product product, {
    required String deliveryService,
    required int deliveryPrice,
  })
  onCreateDeliveryOrder;
  final Listenable? sellerFollowListenable;
  final bool Function(String sellerId)? canFollowSeller;
  final bool Function(String sellerId)? isFollowingSeller;
  final Future<bool> Function(String sellerId)? onToggleSellerFollow;

  const OutfitsScreen({
    super.key,
    required this.scale,
    required this.sidePadding,
    this.createdOutfits = const [],
    this.products = const [],
    required this.onCreateTap,
    required this.onToggleProductLike,
    required this.onToggleOutfitLike,
    required this.onProductViewed,
    required this.onOutfitViewed,
    required this.onContactSeller,
    required this.onOpenSellerProfile,
    this.onSubmitContentReport,
    required this.deliveryProfile,
    required this.onSaveDeliveryProfile,
    required this.onCreateDeliveryOrder,
    this.sellerFollowListenable,
    this.canFollowSeller,
    this.isFollowingSeller,
    this.onToggleSellerFollow,
  });

  @override
  State<OutfitsScreen> createState() => _OutfitsScreenState();
}

class _OutfitsScreenState extends State<OutfitsScreen> {
  // Editorial demo content must never be mixed with real marketplace data.
  // It stays available for isolated design previews only.
  static const bool _showEditorialPlaceholder = false;
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

  Product _sellerProductForOutfit(CreatedOutfit outfit) {
    final ownerId = outfit.ownerId.trim();
    if (ownerId.isNotEmpty) {
      for (final product in widget.products) {
        if (product.ownerId == ownerId) return product;
      }
    }

    final authorHandle = outfit.authorHandle.trim().toLowerCase();
    if (authorHandle.isNotEmpty) {
      for (final product in widget.products) {
        if (product.sellerHandle.trim().toLowerCase() == authorHandle) {
          return product;
        }
      }
    }

    final authorName = outfit.authorName.trim().toLowerCase();
    if (authorName.isNotEmpty) {
      for (final product in widget.products) {
        if (product.sellerName.trim().toLowerCase() == authorName) {
          return product;
        }
      }
    }

    final displayName = outfit.authorName.trim().isEmpty
        ? 'Автор'
        : outfit.authorName.trim();
    final handle = outfit.authorHandle.trim().isEmpty
        ? '@user'
        : outfit.authorHandle.trim();
    final image = outfit.photos.isNotEmpty
        ? outfit.photos.first
        : outfit.items.isNotEmpty
        ? outfit.items.first.image
        : '';

    return Product(
      id: 'outfit_author_${outfit.id}',
      title: displayName,
      detailTitle: displayName,
      description: '',
      price: '',
      detailPrice: '',
      priceValue: 0,
      image: image,
      category: '',
      brand: '',
      size: '',
      color: '',
      condition: '',
      ownerId: ownerId,
      sellerName: displayName,
      sellerHandle: handle,
      dotsOnDark: false,
      isHidden: true,
    );
  }

  Product _sellerProductForOutfitProduct(_OutfitProduct product) {
    final source = product.sourceProduct;
    if (source != null) return source;

    return Product(
      id: product.id.isEmpty ? 'outfit_product_${product.name}' : product.id,
      title: product.name,
      detailTitle: product.name,
      description: '',
      price: product.price,
      detailPrice: product.price,
      priceValue: 0,
      image: product.image ?? '',
      category: '',
      brand: product.brand,
      size: '',
      color: '',
      condition: '',
      ownerId: '',
      sellerName: 'Продавец',
      sellerHandle: '@seller',
      dotsOnDark: false,
      isHidden: true,
    );
  }

  void _openOutfitAuthorProfile(CreatedOutfit outfit) {
    widget.onOpenSellerProfile(_sellerProductForOutfit(outfit));
  }

  Future<void> _shareText({
    required String text,
    required String subject,
  }) async {
    final renderObject = context.findRenderObject();
    final origin = renderObject is RenderBox
        ? renderObject.localToGlobal(Offset.zero) & renderObject.size
        : null;

    try {
      await Share.share(text, subject: subject, sharePositionOrigin: origin);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Системное меню недоступно. Текст скопирован'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _shareOutfit(CreatedOutfit outfit) {
    final author = outfit.authorName.trim().isEmpty
        ? 'пользователя clothes'
        : outfit.authorName.trim();
    final itemNames = outfit.items
        .map((item) => item.name.trim())
        .where((name) => name.isNotEmpty)
        .take(3)
        .join(', ');
    final link = SupabaseConfig.outfitShareUrl(outfit.id);
    return _shareText(
      subject: 'Образ от $author',
      text: [
        'Образ от $author',
        if (itemNames.isNotEmpty) 'В образе: $itemNames',
        link,
      ].join('\n'),
    );
  }

  Future<void> _shareSampleOutfit() {
    return _shareText(
      subject: 'Образ от Lil Yachty',
      text:
          'Образ от Lil Yachty\n'
          'Откройте приложение clothes, чтобы посмотреть вещи из образа.',
    );
  }

  Future<void> _shareOutfitProduct(_OutfitProduct product) {
    final link = product.id.trim().isEmpty
        ? ''
        : SupabaseConfig.productShareUrl(product.id);
    return _shareText(
      subject: product.name,
      text: [product.name, product.price, if (link.isNotEmpty) link].join('\n'),
    );
  }

  void _showUnavailableProductSheet(_OutfitProduct product) {
    final source = product.sourceProduct;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewPadding.bottom;
        return Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + bottomInset),
          decoration: BoxDecoration(
            color: sheetContext.appPalette.surfaceRaised,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                    color: sheetContext.appPalette.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Упс, этот товар не продается',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: sheetContext.appPalette.ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                source == null
                    ? 'Объявление удалено или больше недоступно.'
                    : 'Можно написать продавцу и уточнить, готов ли он продать эту вещь.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: sheetContext.appPalette.muted,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(sheetContext, rootNavigator: true).pop();
                    if (source != null) {
                      widget.onContactSeller(source, imageOnly: true);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(sheetContext).colorScheme.primary,
                    foregroundColor: Theme.of(
                      sheetContext,
                    ).colorScheme.onPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  child: Text(
                    source == null ? 'Понятно' : 'Написать продавцу',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showProductDetails(_OutfitProduct product) {
    final source = product.sourceProduct;
    final canPurchase = product.canPurchase;
    if (!canPurchase) {
      _showUnavailableProductSheet(product);
      return;
    }
    final route = buildProductRoute<void>(
      builder: (context) {
        return ProductScreen(
          sourceProduct: source,
          product: ProductDetailData(
            id:
                source?.id ??
                (product.id.isEmpty
                    ? product.name.toLowerCase().replaceAll(' ', '_')
                    : product.id),
            title: source?.title ?? product.name,
            description: source?.description ?? product.detailDescription,
            price: source?.price ?? product.price,
            priceValue: source?.priceValue ?? _parsePrice(product.price),
            image: source?.image ?? product.image ?? '',
            images: source?.images.isNotEmpty == true
                ? source!.images
                : [
                    if ((source?.image ?? product.image ?? '').isNotEmpty)
                      source?.image ?? product.image!,
                  ],
            category: source?.category ?? '',
            brand: source?.brand ?? product.brand,
            color: source?.color ?? '',
            sellerName: source?.sellerName ?? 'Продавец',
            sellerHandle: source?.sellerHandle ?? '@seller',
            size: source?.size ?? 'M',
            condition: source?.condition ?? 'Отличное',
            location: source?.location ?? '',
            shippingAddress: source?.shippingAddress ?? '',
            isLiked: source?.isLiked ?? product.isLiked,
            canPurchase: canPurchase,
            publishedAt: source?.publishedAt,
            viewsCount: source?.viewsCount ?? 0,
            likesCount: source?.likesCount ?? 0,
            deliveryMethods: source?.deliveryMethods ?? const [],
          ),
          onLike: product.id.isEmpty || !canPurchase
              ? () {}
              : () => widget.onToggleProductLike(product.id),
          sellerFollowListenable: widget.sellerFollowListenable,
          canFollowSeller: widget.canFollowSeller,
          isFollowingSeller: widget.isFollowingSeller,
          onToggleSellerFollow: widget.onToggleSellerFollow,
          onOpenSeller: () => widget.onOpenSellerProfile(
            _sellerProductForOutfitProduct(product),
          ),
          onOpenReviews: () => widget.onOpenSellerProfile(
            _sellerProductForOutfitProduct(product),
          ),
          relatedProducts: source == null
              ? const []
              : _relatedProductsFor(source),
          onRelatedProductTap: (related) =>
              _showProductDetails(_outfitProductForSourceProduct(related)),
          deliveryProfile: widget.deliveryProfile,
          onSaveDeliveryProfile: widget.onSaveDeliveryProfile,
          onCreateDeliveryOrder: source == null
              ? ({required deliveryService, required deliveryPrice}) async =>
                    null
              : ({required deliveryService, required deliveryPrice}) =>
                    widget.onCreateDeliveryOrder(
                      source,
                      deliveryService: deliveryService,
                      deliveryPrice: deliveryPrice,
                    ),
          onContactSeller: source == null
              ? () {}
              : () => widget.onContactSeller(
                  source,
                  sourceRoute: ModalRoute.of(context),
                ),
          onShare: () => _shareOutfitProduct(product),
        );
      },
    );
    Navigator.of(context, rootNavigator: true).push(route);
    if (product.id.isNotEmpty) widget.onProductViewed(product.id);
  }

  List<Product> _relatedProductsFor(Product product) {
    return rankRelatedCatalogProducts(product, widget.products);
  }

  _OutfitProduct _outfitProductForSourceProduct(Product product) {
    return _OutfitProduct(
      id: product.id,
      icon: Icons.checkroom_outlined,
      sourceProduct: product,
      brand: product.brand,
      description: product.description,
      name: product.title,
      price: product.price,
      image: product.image,
      isLiked: product.isLiked,
      canPurchase: !product.isHidden,
    );
  }

  int _parsePrice(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  List<_OutfitProduct> _outfitProducts(CreatedOutfit outfit) {
    final productsById = {
      for (final product in widget.products) product.id: product,
    };
    return outfit.items.map((item) {
      final product = productsById[item.id];
      return _OutfitProduct(
        id: item.id,
        icon: Icons.checkroom_outlined,
        sourceProduct: product,
        brand: product?.brand ?? '',
        description: product?.description ?? '',
        name: product?.title ?? item.name,
        price: product == null
            ? item.price
            : product.isHidden
            ? 'Не продается'
            : product.price,
        image: product?.outfitDisplayImage ?? item.image,
        isLiked: product?.isLiked ?? false,
        canPurchase: product != null && !product.isHidden,
      );
    }).toList();
  }

  List<CreatedOutfit> _relatedOutfits(CreatedOutfit outfit) {
    final ownerId = outfit.ownerId.trim();
    final handle = outfit.authorHandle.trim().toLowerCase();
    final name = outfit.authorName.trim().toLowerCase();
    return widget.createdOutfits.where((candidate) {
      if (candidate.id == outfit.id) return false;
      if (ownerId.isNotEmpty && candidate.ownerId.trim() == ownerId) {
        return true;
      }
      if (handle.isNotEmpty &&
          candidate.authorHandle.trim().toLowerCase() == handle) {
        return true;
      }
      return name.isNotEmpty &&
          candidate.authorName.trim().toLowerCase() == name;
    }).toList();
  }

  void _showOutfitDetails(CreatedOutfit outfit) {
    final viewsCountCompleter = Completer<int>();
    final route = MaterialPageRoute<void>(
      builder: (context) => _OutfitDetailScreen(
        photos: outfit.photos,
        previewBackgroundColor: outfit.previewBackgroundColor,
        layoutItems: outfit.layoutItems,
        authorName: outfit.authorName,
        authorHandle: outfit.authorHandle,
        authorAvatarUrl: outfit.authorAvatarUrl,
        isLiked: outfit.isLiked,
        likesCount: outfit.likesCount,
        initialViewsCount: outfit.viewsCount,
        viewsCountFuture: viewsCountCompleter.future,
        publishedAt: outfit.publishedAt,
        products: _outfitProducts(outfit),
        moreOutfits: _relatedOutfits(outfit),
        onLikeTap: () => widget.onToggleOutfitLike(outfit.id),
        onAuthorTap: () => _openOutfitAuthorProfile(outfit),
        onProductTap: _showProductDetails,
        onOutfitTap: _showOutfitDetails,
        onShare: () => _shareOutfit(outfit),
        onReport: widget.onSubmitContentReport == null
            ? null
            : () => _reportOutfit(outfit),
      ),
    );
    Navigator.of(context, rootNavigator: true).push(route);
    unawaited(_completeOutfitView(outfit, viewsCountCompleter));
  }

  Future<void> _reportOutfit(CreatedOutfit outfit) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 10),
              child: Text(
                'Почему вы жалуетесь на образ?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            for (final reason in const [
              'Спам',
              'Подделка',
              'Неподходящий контент',
              'Обман',
              'Другое',
            ])
              ListTile(
                title: Text(reason),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(sheetContext, reason),
              ),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;
    final submitted = await widget.onSubmitContentReport!(
      targetType: 'outfit',
      targetId: outfit.id,
      reason: reason,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          submitted ? 'Жалоба отправлена' : 'Не удалось отправить жалобу',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _completeOutfitView(
    CreatedOutfit outfit,
    Completer<int> completer,
  ) async {
    try {
      completer.complete(await widget.onOutfitViewed(outfit.id));
    } catch (_) {
      completer.complete(outfit.viewsCount);
    }
  }

  void _showSampleOutfitDetails() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (context) => _OutfitDetailScreen(
          photos: const ['assets/mock/outfit_hero.jpg'],
          previewBackgroundColor: null,
          layoutItems: const [],
          authorName: 'Lil Yachty',
          authorHandle: '@lilyachty',
          authorAvatarUrl: '',
          isLiked: _isLiked,
          likesCount: _likesCount,
          initialViewsCount: 0,
          viewsCountFuture: Future<int>.value(0),
          publishedAt: null,
          products: const [],
          moreOutfits: const [],
          onLikeTap: () async => _toggleLike(),
          onAuthorTap: () => widget.onOpenSellerProfile(
            Product(
              id: 'sample_outfit_author',
              title: 'Lil Yachty',
              detailTitle: 'Lil Yachty',
              description: '',
              price: '',
              detailPrice: '',
              priceValue: 0,
              image: 'assets/mock/outfit_hero.jpg',
              category: '',
              brand: '',
              size: '',
              color: '',
              condition: '',
              ownerId: '',
              sellerName: 'Lil Yachty',
              sellerHandle: '@lilyachty',
              dotsOnDark: false,
              isHidden: true,
            ),
          ),
          onProductTap: _showProductDetails,
          onOutfitTap: (_) {},
          onShare: _shareSampleOutfit,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).viewPadding.top;

    return Container(
      color: context.appBackdrop.scaffoldColor,
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
                  onAuthorTap: () => _openOutfitAuthorProfile(outfit),
                  onProductTap: _showProductDetails,
                  onOutfitTap: () => _showOutfitDetails(outfit),
                  onLikeTap: () => widget.onToggleOutfitLike(outfit.id),
                ),
              ),
            ),
            if (widget.createdOutfits.isEmpty && _showEditorialPlaceholder)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.sidePadding),
                child: _OutfitCard(
                  scale: widget.scale,
                  products: _products,
                  isLiked: _isLiked,
                  likesCount: _likesCount,
                  pageController: _pageController,
                  onLikeTap: _toggleLike,
                  onAuthorTap: () => widget.onOpenSellerProfile(
                    Product(
                      id: 'sample_outfit_author',
                      title: 'Lil Yachty',
                      detailTitle: 'Lil Yachty',
                      description: '',
                      price: '',
                      detailPrice: '',
                      priceValue: 0,
                      image: 'assets/mock/outfit_hero.jpg',
                      category: '',
                      brand: '',
                      size: '',
                      color: '',
                      condition: '',
                      ownerId: '',
                      sellerName: 'Lil Yachty',
                      sellerHandle: '@lilyachty',
                      dotsOnDark: false,
                      isHidden: true,
                    ),
                  ),
                  onProductTap: _showProductDetails,
                  onOutfitTap: _showSampleOutfitDetails,
                ),
              ),
            if (widget.createdOutfits.isEmpty && !_showEditorialPlaceholder)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.sidePadding),
                child: _EmptyOutfitsState(onCreateTap: widget.onCreateTap),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyOutfitsState extends StatelessWidget {
  const _EmptyOutfitsState({required this.onCreateTap});

  final VoidCallback onCreateTap;

  @override
  Widget build(BuildContext context) {
    return AppGlassSurface(
      key: const Key('outfits-glass-empty-state'),
      role: AppGlassRole.card,
      borderRadius: BorderRadius.circular(20),
      padding: EdgeInsets.zero,
      interactiveGlint: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 36),
        decoration: BoxDecoration(
          color: context.appGlass.enabled
              ? Colors.transparent
              : context.appPalette.surfaceRaised,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            const Icon(Icons.checkroom_outlined, size: 38),
            const SizedBox(height: 16),
            Text(
              'Пока нет опубликованных образов',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 17,
                height: 1.25,
                fontWeight: AppTypography.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Соберите первый образ из вещей каталога — он появится здесь после публикации.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                height: 1.4,
                fontWeight: AppTypography.medium,
                color: context.appPalette.muted,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 46,
              child: ElevatedButton(
                onPressed: onCreateTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'СОЗДАТЬ ОБРАЗ',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    fontWeight: AppTypography.semiBold,
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

class _Header extends StatelessWidget {
  const _Header({required this.scale, required this.onCreateTap});

  final double scale;
  final VoidCallback onCreateTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('outfits-header-row'),
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: Text(
              'образы',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 22,
                fontWeight: AppTypography.bold,
                height: 1,
                letterSpacing: -0.4,
                color: context.appPalette.ink,
              ),
            ),
          ),
          AppGlassSurface(
            key: const Key('outfits-glass-create-button'),
            role: AppGlassRole.compactButton,
            borderRadius: BorderRadius.circular(999),
            padding: EdgeInsets.zero,
            child: AppGlassPressable(
              onTap: onCreateTap,
              pressedScale: 0.95,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.add_circle_outline,
                  size: 24,
                  color: context.appPalette.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutfitDetailScreen extends StatefulWidget {
  const _OutfitDetailScreen({
    required this.photos,
    required this.previewBackgroundColor,
    required this.layoutItems,
    required this.authorName,
    required this.authorHandle,
    required this.authorAvatarUrl,
    required this.isLiked,
    required this.likesCount,
    required this.initialViewsCount,
    required this.viewsCountFuture,
    required this.publishedAt,
    required this.products,
    required this.moreOutfits,
    required this.onLikeTap,
    required this.onAuthorTap,
    required this.onProductTap,
    required this.onOutfitTap,
    required this.onShare,
    this.onReport,
  });

  final List<String> photos;
  final int? previewBackgroundColor;
  final List<OutfitLayoutItem> layoutItems;
  final String authorName;
  final String authorHandle;
  final String authorAvatarUrl;
  final bool isLiked;
  final int likesCount;
  final int initialViewsCount;
  final Future<int> viewsCountFuture;
  final DateTime? publishedAt;
  final List<_OutfitProduct> products;
  final List<CreatedOutfit> moreOutfits;
  final Future<void> Function() onLikeTap;
  final VoidCallback onAuthorTap;
  final void Function(_OutfitProduct) onProductTap;
  final void Function(CreatedOutfit) onOutfitTap;
  final VoidCallback onShare;
  final VoidCallback? onReport;

  @override
  State<_OutfitDetailScreen> createState() => _OutfitDetailScreenState();
}

class _OutfitDetailScreenState extends State<_OutfitDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showCollapsedHeader = false;
  late bool _isLiked;
  late int _likesCount;
  late int _viewsCount;
  int _viewsFutureGeneration = 0;

  static const _heroImageHeight = 560.0;
  static const _heroSectionHeight = 598.0;

  List<_OutfitProduct> get _products => widget.products;

  String get _authorName {
    final trimmed = widget.authorName.trim();
    return trimmed.isEmpty ? 'Автор' : trimmed;
  }

  @override
  void initState() {
    super.initState();
    _isLiked = widget.isLiked;
    _likesCount = widget.likesCount.clamp(0, 1 << 31).toInt();
    _viewsCount = widget.initialViewsCount.clamp(0, 1 << 31).toInt();
    if (_isLiked && _likesCount == 0) {
      _likesCount = 1;
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scrollController.addListener(_handleScroll);
    _watchViewsCount(widget.viewsCountFuture);
  }

  @override
  void didUpdateWidget(covariant _OutfitDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialViewsCount != oldWidget.initialViewsCount) {
      _viewsCount = widget.initialViewsCount.clamp(0, 1 << 31).toInt();
    }
    if (!identical(oldWidget.viewsCountFuture, widget.viewsCountFuture)) {
      _watchViewsCount(widget.viewsCountFuture);
    }
  }

  void _watchViewsCount(Future<int> future) {
    final generation = ++_viewsFutureGeneration;
    _applyViewsCount(future, generation);
  }

  Future<void> _applyViewsCount(Future<int> future, int generation) async {
    try {
      final resolved = await future;
      if (!mounted || generation != _viewsFutureGeneration) return;
      final authoritative = resolved.clamp(0, 1 << 31).toInt();
      if (authoritative == _viewsCount) return;
      setState(() => _viewsCount = authoritative);
    } catch (_) {
      // Keep the initial/optimistic value when recording a view fails.
    }
  }

  Future<void> _toggleLike() async {
    final previousLiked = _isLiked;
    final previousCount = _likesCount;
    setState(() {
      _isLiked = !_isLiked;
      _likesCount += _isLiked ? 1 : -1;
      if (_likesCount < 0) {
        _likesCount = 0;
      }
    });

    try {
      await widget.onLikeTap();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLiked = previousLiked;
        _likesCount = previousCount;
      });
    }
  }

  void _handleScroll() {
    final next = _scrollController.offset > 430;
    if (next == _showCollapsedHeader) return;
    setState(() => _showCollapsedHeader = next);
  }

  void _openPhotos(int initialPage) {
    if (widget.photos.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) =>
            _OutfitImageViewer(images: widget.photos, initialPage: initialPage),
      ),
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _OutfitHeroSection(
                  height: _heroSectionHeight,
                  imageHeight: _heroImageHeight,
                  photos: widget.photos,
                  previewBackgroundColor: widget.previewBackgroundColor,
                  layoutItems: widget.layoutItems,
                  authorName: _authorName,
                  authorHandle: widget.authorHandle,
                  authorAvatarUrl: widget.authorAvatarUrl,
                  likesCount: _likesCount,
                  isLiked: _isLiked,
                  onLikeTap: _toggleLike,
                  onAuthorTap: widget.onAuthorTap,
                  onOpenPhoto: _openPhotos,
                ),
                _OutfitProductsList(
                  products: _products,
                  onProductTap: widget.onProductTap,
                ),
                _TotalSection(total: _totalText(_products)),
                _OutfitPublicationMeta(
                  publishedAt: widget.publishedAt,
                  viewsCount: _viewsCount,
                ),
                _MoreOutfitsSection(
                  authorName: _authorName,
                  outfits: widget.moreOutfits,
                  onOutfitTap: widget.onOutfitTap,
                  onAuthorTap: widget.onAuthorTap,
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _DetailTopBar(
              isCollapsed: _showCollapsedHeader,
              onShare: widget.onShare,
              onReport: widget.onReport,
            ),
          ),
        ],
      ),
    );
  }

  static String _totalText(List<_OutfitProduct> products) {
    final total = products.fold<int>(0, (sum, product) {
      final digits = product.price.replaceAll(RegExp(r'[^0-9]'), '');
      return sum + (int.tryParse(digits) ?? 0);
    });
    return '${_formatNumber(total)} \u20BD';
  }

  static String _formatNumber(int value) {
    final raw = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < raw.length; index++) {
      final remaining = raw.length - index;
      buffer.write(raw[index]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(' ');
      }
    }
    return buffer.toString();
  }
}

class _OutfitImageViewer extends StatefulWidget {
  const _OutfitImageViewer({required this.images, required this.initialPage});

  final List<String> images;
  final int initialPage;

  @override
  State<_OutfitImageViewer> createState() => _OutfitImageViewerState();
}

class _OutfitImageViewerState extends State<_OutfitImageViewer> {
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
        name: 'clothes_outfit_${DateTime.now().millisecondsSinceEpoch}',
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
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
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
                      Icons.download_rounded,
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

class _DetailTopBar extends StatelessWidget {
  const _DetailTopBar({
    required this.isCollapsed,
    required this.onShare,
    this.onReport,
  });

  final bool isCollapsed;
  final VoidCallback onShare;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).viewPadding.top;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: top + 58,
      padding: EdgeInsets.fromLTRB(16, top + 8, 16, 8),
      decoration: BoxDecoration(
        color: isCollapsed
            ? context.appPalette.surfaceRaised
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: isCollapsed ? context.appPalette.border : Colors.transparent,
          ),
        ),
      ),
      child: Row(
        children: [
          _DetailTopButton(
            onPressed: () => Navigator.maybePop(context),
            icon: Icons.arrow_back,
          ),
          const Spacer(),
          if (onReport != null) ...[
            _DetailTopButton(
              onPressed: onReport!,
              icon: Icons.more_horiz_rounded,
            ),
            const SizedBox(width: 8),
          ],
          _DetailTopButton(onPressed: onShare, icon: Icons.ios_share),
        ],
      ),
    );
  }
}

class _DetailTopButton extends StatelessWidget {
  const _DetailTopButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.appPalette.surfaceRaised.withValues(alpha: 0.94),
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: context.appPalette.shadow,
      child: InkWell(
        customBorder: const CircleBorder(),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        onTap: onPressed,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, size: 25, color: context.appPalette.ink),
        ),
      ),
    );
  }
}

class _OutfitHeroSection extends StatelessWidget {
  const _OutfitHeroSection({
    required this.height,
    required this.imageHeight,
    required this.photos,
    required this.previewBackgroundColor,
    required this.layoutItems,
    required this.authorName,
    required this.authorHandle,
    required this.authorAvatarUrl,
    required this.likesCount,
    required this.isLiked,
    required this.onLikeTap,
    required this.onAuthorTap,
    required this.onOpenPhoto,
  });

  final double height;
  final double imageHeight;
  final List<String> photos;
  final int? previewBackgroundColor;
  final List<OutfitLayoutItem> layoutItems;
  final String authorName;
  final String authorHandle;
  final String authorAvatarUrl;
  final int likesCount;
  final bool isLiked;
  final Future<void> Function() onLikeTap;
  final VoidCallback onAuthorTap;
  final ValueChanged<int> onOpenPhoto;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: photos.isEmpty ? null : () => onOpenPhoto(0),
            child: SizedBox(
              width: double.infinity,
              height: imageHeight,
              child: layoutItems.isNotEmpty
                  ? _OutfitLayoutCanvas(
                      backgroundColor: Color(
                        previewBackgroundColor ??
                            _outfitMediaBackground.toARGB32(),
                      ),
                      items: layoutItems,
                    )
                  : AppImage(
                      imageUrl: photos.isNotEmpty
                          ? photos.first
                          : 'assets/mock/outfit_hero.jpg',
                      width: double.infinity,
                      height: imageHeight,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      placeholderColor: _outfitMediaBackground,
                    ),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 0,
            child: _CreatorFloatingCard(
              authorName: authorName,
              authorHandle: authorHandle,
              authorAvatarUrl: authorAvatarUrl,
              likesCount: likesCount,
              isLiked: isLiked,
              onLikeTap: onLikeTap,
              onAuthorTap: onAuthorTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreatorFloatingCard extends StatelessWidget {
  const _CreatorFloatingCard({
    required this.authorName,
    required this.authorHandle,
    required this.authorAvatarUrl,
    required this.likesCount,
    required this.isLiked,
    required this.onLikeTap,
    required this.onAuthorTap,
  });

  final String authorName;
  final String authorHandle;
  final String authorAvatarUrl;
  final int likesCount;
  final bool isLiked;
  final Future<void> Function() onLikeTap;
  final VoidCallback onAuthorTap;

  @override
  Widget build(BuildContext context) {
    final handle = authorHandle.trim();
    final user = handle.isEmpty
        ? '@user'
        : handle.startsWith('@')
        ? handle
        : '@$handle';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onAuthorTap,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: context.appPalette.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: context.appPalette.shadow,
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipOval(
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.appPalette.surfaceMuted,
                ),
                child: authorAvatarUrl.trim().isEmpty
                    ? Icon(
                        Icons.person_outline,
                        size: 24,
                        color: context.appPalette.muted,
                      )
                    : AppImage(
                        imageUrl: authorAvatarUrl,
                        width: 42,
                        height: 42,
                        fit: BoxFit.cover,
                      ),
              ),
            ),
            const SizedBox(width: 11),
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
                      fontFamily: 'Montserrat',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      color: context.appPalette.ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$user В· $likesCount likes',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1,
                      color: context.appPalette.muted,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onLikeTap,
              child: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border,
                size: 31,
                color: isLiked
                    ? const Color(0xFFD71920)
                    : context.appPalette.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutfitProductsList extends StatelessWidget {
  const _OutfitProductsList({
    required this.products,
    required this.onProductTap,
  });

  final List<_OutfitProduct> products;
  final void Function(_OutfitProduct) onProductTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < products.length; index++) ...[
          _OutfitProductRow(
            product: products[index],
            onTap: () => onProductTap(products[index]),
          ),
          if (index != products.length - 1)
            Divider(height: 1, thickness: 1, color: context.appPalette.border),
        ],
      ],
    );
  }
}

class _OutfitProductRow extends StatelessWidget {
  const _OutfitProductRow({required this.product, required this.onTap});

  final _OutfitProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 82,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              SizedBox(
                width: 54,
                height: 54,
                child: product.image == null || product.image!.trim().isEmpty
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.appPalette.surface,
                        ),
                        child: Icon(
                          product.icon,
                          size: 28,
                          color: context.appPalette.muted,
                        ),
                      )
                    : AppImage(
                        imageUrl: product.image!,
                        width: 54,
                        height: 54,
                        fit: BoxFit.contain,
                        placeholderColor: context.appPalette.surface,
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        height: 1.05,
                        color: context.appPalette.ink,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      product.price,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 16,
                        fontWeight: AppTypography.semiBold,
                        height: 1,
                        color: context.appPalette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 28,
                color: context.appPalette.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalSection extends StatelessWidget {
  const _TotalSection({required this.total});

  final String total;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Divider(height: 1, thickness: 1, color: context.appPalette.border),
        SizedBox(
          height: 78,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: context.appPalette.muted,
                  ),
                  children: [
                    const TextSpan(text: 'Итого: '),
                    TextSpan(
                      text: total,
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        color: context.appPalette.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 12,
          width: double.infinity,
          child: ColoredBox(color: context.appPalette.surfaceMuted),
        ),
      ],
    );
  }
}

class _OutfitPublicationMeta extends StatelessWidget {
  const _OutfitPublicationMeta({
    required this.publishedAt,
    required this.viewsCount,
    this.horizontalPadding = 24,
  });

  final DateTime? publishedAt;
  final int viewsCount;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final safeViewsCount = viewsCount.clamp(0, 1 << 31).toInt();
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        13,
        horizontalPadding,
        15,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.appPalette.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _outfitPublicationLabel(publishedAt),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12.5,
                height: 1.2,
                fontWeight: AppTypography.medium,
                color: context.appPalette.muted,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _OutfitMetric(
            icon: Icons.visibility_outlined,
            count: safeViewsCount,
            semanticsLabel: '$safeViewsCount просмотров',
          ),
        ],
      ),
    );
  }
}

class _OutfitMetric extends StatelessWidget {
  const _OutfitMetric({
    required this.icon,
    required this.count,
    required this.semanticsLabel,
  });

  final IconData icon;
  final int count;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: context.appPalette.muted),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12.5,
              height: 1.2,
              fontWeight: AppTypography.semiBold,
              color: context.appPalette.muted,
            ),
          ),
        ],
      ),
    );
  }
}

String _outfitPublicationLabel(DateTime? value) {
  if (value == null) return 'Опубликовано: —';
  final local = value.toLocal();
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return 'Опубликовано: ${twoDigits(local.day)}.${twoDigits(local.month)}.'
      '${local.year}, $hour:$minute';
}

class _MoreOutfitsSection extends StatelessWidget {
  const _MoreOutfitsSection({
    required this.authorName,
    required this.outfits,
    required this.onOutfitTap,
    required this.onAuthorTap,
  });

  final String authorName;
  final List<CreatedOutfit> outfits;
  final void Function(CreatedOutfit) onOutfitTap;
  final VoidCallback onAuthorTap;

  @override
  Widget build(BuildContext context) {
    if (outfits.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Wrap(
              children: [
                Text(
                  'Больше образов от ',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: context.appPalette.muted,
                  ),
                ),
                InkWell(
                  onTap: onAuthorTap,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                  child: Text(
                    authorName,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: context.appPalette.ink,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: outfits.length,
              separatorBuilder: (context, index) => const SizedBox(width: 11),
              itemBuilder: (context, index) {
                final outfit = outfits[index];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onOutfitTap(outfit),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 116,
                      height: 150,
                      child: _RelatedOutfitPreview(outfit: outfit),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RelatedOutfitPreview extends StatelessWidget {
  const _RelatedOutfitPreview({required this.outfit});

  final CreatedOutfit outfit;

  @override
  Widget build(BuildContext context) {
    if (outfit.layoutItems.isNotEmpty) {
      return _OutfitLayoutCanvas(
        backgroundColor: Color(
          outfit.previewBackgroundColor ?? _outfitMediaBackground.toARGB32(),
        ),
        items: outfit.layoutItems,
      );
    }

    if (outfit.photos.isNotEmpty) {
      return AppImage(
        imageUrl: outfit.photos.first,
        width: 116,
        height: 150,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        placeholderColor: _outfitMediaBackground,
      );
    }

    return ColoredBox(
      color: context.appPalette.surfaceMuted,
      child: Center(
        child: Icon(Icons.checkroom_outlined, color: context.appPalette.muted),
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
    required this.onOutfitTap,
    required this.onLikeTap,
  });

  final double scale;
  final CreatedOutfit outfit;
  final List<Product> products;
  final VoidCallback onAuthorTap;
  final void Function(_OutfitProduct) onProductTap;
  final VoidCallback onOutfitTap;
  final VoidCallback onLikeTap;

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
        color: context.appPalette.surfaceRaised,
        borderRadius: BorderRadius.circular(30 * widget.scale),
        border: Border.all(color: context.appPalette.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: context.appPalette.shadow,
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
              GestureDetector(
                key: ValueKey<String>('outfit-card-${widget.outfit.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: widget.onOutfitTap,
                child: _HeroMedia(
                  scale: widget.scale,
                  photos: widget.outfit.photos,
                  previewBackgroundColor: widget.outfit.previewBackgroundColor,
                  layoutItems: widget.outfit.layoutItems,
                  pageController: _pageController,
                ),
              ),
              _ProductsSection(
                scale: widget.scale,
                products: widget.outfit.items.map((item) {
                  final product = _productsById[item.id];
                  return _OutfitProduct(
                    id: item.id,
                    icon: Icons.checkroom_outlined,
                    sourceProduct: product,
                    brand: product?.brand ?? '',
                    name: product?.title ?? item.name,
                    price: product == null
                        ? item.price
                        : product.isHidden
                        ? 'Не продается'
                        : product.price,
                    image: product?.outfitDisplayImage ?? item.image,
                    isLiked: product?.isLiked ?? false,
                    canPurchase: product != null && !product.isHidden,
                  );
                }).toList(),
                onProductTap: widget.onProductTap,
              ),
              _OutfitPublicationMeta(
                publishedAt: widget.outfit.publishedAt,
                viewsCount: widget.outfit.viewsCount,
                horizontalPadding: 16 * widget.scale,
              ),
            ],
          ),
          Positioned(
            left: 16 * widget.scale,
            right: 16 * widget.scale,
            top: 398 * widget.scale,
            child: _AuthorCard(
              scale: widget.scale,
              authorName: widget.outfit.authorName,
              authorHandle: widget.outfit.authorHandle,
              authorAvatarUrl: widget.outfit.authorAvatarUrl,
              isLiked: widget.outfit.isLiked,
              likesCount: widget.outfit.likesCount,
              onLikeTap: widget.onLikeTap,
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
    required this.onOutfitTap,
  });

  final double scale;
  final List<_OutfitProduct> products;
  final bool isLiked;
  final int likesCount;
  final PageController pageController;
  final VoidCallback onLikeTap;
  final VoidCallback onAuthorTap;
  final void Function(_OutfitProduct) onProductTap;
  final VoidCallback onOutfitTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.appPalette.surfaceRaised,
        borderRadius: BorderRadius.circular(30 * scale),
        border: Border.all(color: context.appPalette.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: context.appPalette.shadow,
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
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onOutfitTap,
                child: _HeroMedia(scale: scale, pageController: pageController),
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
            top: 398 * scale,
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
      height: 430 * scale,
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
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          context.appPalette.surfaceRaised,
                          context.appPalette.surfaceMuted,
                          context.appPalette.surface,
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
    this.authorAvatarUrl = '',
    required this.isLiked,
    required this.likesCount,
    required this.onLikeTap,
    required this.onAuthorTap,
  });

  final double scale;
  final String authorName;
  final String authorHandle;
  final String authorAvatarUrl;
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
          color: context.appPalette.surfaceRaised,
          borderRadius: BorderRadius.circular(18 * scale),
          boxShadow: [
            BoxShadow(
              color: context.appPalette.shadow,
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipOval(
              child: Container(
                width: 38 * scale,
                height: 38 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.appPalette.surfaceMuted,
                ),
                child: authorAvatarUrl.trim().isEmpty
                    ? Icon(
                        Icons.person_outline,
                        size: 20 * scale,
                        color: context.appPalette.muted,
                      )
                    : AppImage(
                        imageUrl: authorAvatarUrl,
                        width: 38 * scale,
                        height: 38 * scale,
                        fit: BoxFit.cover,
                      ),
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
                      color: context.appPalette.ink,
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
                      color: context.appPalette.muted,
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
                    : context.appPalette.muted,
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
        42 * widget.scale,
        0,
        12 * widget.scale,
      ),
      decoration: BoxDecoration(
        color: context.appPalette.surfaceRaised,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(30 * widget.scale),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 84 * widget.scale,
            child: Stack(
              children: [
                ListView.separated(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(right: 16 * widget.scale),
                  itemCount: widget.products.length,
                  separatorBuilder: (context, index) =>
                      SizedBox(width: 10 * widget.scale),
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
        width: 74 * scale,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 48 * scale,
              height: 48 * scale,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.appPalette.surface,
                  borderRadius: BorderRadius.circular(5 * scale),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5 * scale),
                  child: product.image == null || product.image!.isEmpty
                      ? Container(
                          color: context.appPalette.surface,
                          child: Icon(
                            product.icon,
                            size: 24 * scale,
                            color: context.appPalette.muted,
                          ),
                        )
                      : AppImage(
                          imageUrl: product.image!,
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          placeholderColor: context.appPalette.surface,
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
                fontSize: 9.5 * scale,
                fontWeight: FontWeight.w600,
                height: 1,
                color: context.appPalette.ink,
              ),
            ),
            SizedBox(height: 1.5 * scale),
            Text(
              product.price,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10 * scale,
                fontWeight: FontWeight.w700,
                height: 1,
                color: context.appPalette.muted,
              ),
            ),
          ],
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
            color: context.appPalette.surfaceRaised.withValues(alpha: 0.94),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: context.appPalette.shadow,
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, size: 18 * scale, color: context.appPalette.ink),
        ),
      ),
    );
  }
}

class _OutfitProduct {
  const _OutfitProduct({
    this.id = '',
    required this.icon,
    this.sourceProduct,
    this.brand = '',
    this.description = '',
    required this.name,
    required this.price,
    this.image,
    this.isLiked = false,
    this.canPurchase = true,
  });

  final String id;
  final IconData icon;
  final Product? sourceProduct;
  final String brand;
  final String description;
  final String name;
  final String price;
  final String? image;
  final bool isLiked;
  final bool canPurchase;

  String get detailDescription {
    final clean = description.trim();
    if (clean.isNotEmpty) return clean;
    final label = [
      brand,
      name,
    ].where((part) => part.trim().isNotEmpty).join(' ');
    if (label.trim().isEmpty) return 'Item from this outfit.';
    return '$label. Item from this outfit.';
  }
}
