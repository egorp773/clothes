import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_appearance.dart';
import '../models/app_profile.dart';
import '../models/product.dart';
import '../widgets/app_image.dart';
import '../widgets/seller_follow_button.dart';
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
    this.onShareSeller,
    this.onReportSeller,
    this.onBlockSeller,
    this.sellerFollowListenable,
    this.canFollowSeller,
    this.isFollowingSeller,
    this.onToggleSellerFollow,
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
  final Future<void> Function(SellerProfile seller)? onShareSeller;
  final Future<String?> Function(SellerProfile seller, String reason)?
  onReportSeller;
  final Future<String?> Function(SellerProfile seller)? onBlockSeller;
  final Listenable? sellerFollowListenable;
  final bool Function(String sellerId)? canFollowSeller;
  final bool Function(String sellerId)? isFollowingSeller;
  final Future<bool> Function(String sellerId)? onToggleSellerFollow;

  @override
  State<SellerProfileScreen> createState() => _SellerProfileScreenState();
}

class _SellerProfileScreenState extends State<SellerProfileScreen> {
  late SellerProfile _seller;
  late List<Product> _products;
  int _tabIndex = 0;
  bool _isRunningSellerAction = false;
  bool _isLoading = true;
  String? _loadError;

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
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    SellerProfile? profile;
    List<Product>? products;
    var failed = false;
    try {
      profile = await widget.loadProfile(widget.sourceProduct);
    } catch (_) {
      failed = true;
    }
    try {
      products = await widget.loadProducts(widget.sourceProduct.ownerId);
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      if (profile != null) _seller = profile;
      if (products != null) _products = products;
      _isLoading = false;
      _loadError = failed
          ? 'Не все данные продавца загрузились. Показана доступная информация.'
          : null;
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

  Future<void> _openMessage() async {
    if (_isRunningSellerAction) return;
    setState(() => _isRunningSellerAction = true);
    try {
      await widget.onMessage(_seller);
    } catch (_) {
      _showMessage('Не удалось открыть чат. Попробуйте ещё раз.');
    } finally {
      if (mounted) setState(() => _isRunningSellerAction = false);
    }
  }

  Future<void> _shareSeller() async {
    if (_isRunningSellerAction) return;
    setState(() => _isRunningSellerAction = true);
    try {
      final callback = widget.onShareSeller;
      if (callback != null) {
        await callback(_seller);
      } else {
        final handle = _seller.handle.trim();
        final text = [
          'Профиль продавца ${_seller.name.trim()}',
          if (handle.isNotEmpty) handle,
        ].join('\n');
        final box = context.findRenderObject() as RenderBox?;
        await Share.share(
          text,
          subject: 'Профиль продавца ${_seller.name.trim()}',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        );
      }
    } catch (_) {
      _showMessage('Не удалось открыть меню «Поделиться». Попробуйте ещё раз.');
    } finally {
      if (mounted) setState(() => _isRunningSellerAction = false);
    }
  }

  Future<void> _openSellerActions() async {
    if (_isRunningSellerAction) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.appPalette.surfaceRaised,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Пожаловаться на профиль'),
              subtitle: Text(
                widget.onReportSeller == null
                    ? 'Сервис модерации ещё подключается'
                    : 'Сообщить о нарушении правил',
              ),
              onTap: () => Navigator.pop(sheetContext, 'report'),
            ),
            ListTile(
              leading: const Icon(Icons.block_rounded, color: Colors.red),
              title: const Text(
                'Заблокировать пользователя',
                style: TextStyle(color: Colors.red),
              ),
              subtitle: Text(
                widget.onBlockSeller == null
                    ? 'Сервис блокировок ещё подключается'
                    : 'Скрыть объявления и прекратить общение',
              ),
              onTap: () => Navigator.pop(sheetContext, 'block'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'report') await _reportSeller();
    if (action == 'block') await _blockSeller();
  }

  Future<void> _reportSeller() async {
    final callback = widget.onReportSeller;
    if (callback == null) {
      _showMessage(
        'Жалобы станут доступны после подключения службы модерации.',
      );
      return;
    }
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.appPalette.surfaceRaised,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 2, 20, 8),
              child: Text(
                'Причина жалобы',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            for (final reason in const [
              'Мошенничество или попытка обмана',
              'Запрещённые товары',
              'Оскорбления или домогательства',
              'Спам или чужой контент',
              'Другая причина',
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
    setState(() => _isRunningSellerAction = true);
    try {
      final error = await callback(_seller, reason);
      if (!mounted) return;
      if (error != null) {
        _showMessage(error);
        return;
      }
      _showMessage('Жалоба отправлена на модерацию.');
    } catch (_) {
      _showMessage('Не удалось отправить жалобу. Попробуйте ещё раз.');
    } finally {
      if (mounted) setState(() => _isRunningSellerAction = false);
    }
  }

  Future<void> _blockSeller() async {
    final callback = widget.onBlockSeller;
    if (callback == null) {
      _showMessage(
        'Блокировка станет доступна после подключения службы модерации.',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Заблокировать пользователя?'),
        content: const Text(
          'Его объявления и сообщения должны исчезнуть из ваших разделов. Действие можно будет отменить в настройках.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ОТМЕНА'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'ЗАБЛОКИРОВАТЬ',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isRunningSellerAction = true);
    try {
      final error = await callback(_seller);
      if (!mounted) return;
      if (error != null) {
        _showMessage(error);
        return;
      }
      Navigator.of(context).maybePop();
    } catch (_) {
      _showMessage(
        'Не удалось заблокировать пользователя. Попробуйте ещё раз.',
      );
    } finally {
      if (mounted) setState(() => _isRunningSellerAction = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).viewPadding.top;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                        _TopBar(
                          onBack: () => Navigator.pop(context),
                          onShare: _isRunningSellerAction ? null : _shareSeller,
                          onMore: _isRunningSellerAction
                              ? null
                              : _openSellerActions,
                        ),
                        if (_isLoading) ...[
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            minHeight: 2,
                            color: Theme.of(context).colorScheme.primary,
                            backgroundColor: context.appPalette.surfaceMuted,
                          ),
                        ],
                        if (_loadError != null) ...[
                          const SizedBox(height: 10),
                          Material(
                            color: context.appPalette.surfaceMuted,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: _load,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.info_outline_rounded,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        _loadError!,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          height: 1.3,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'ПОВТОРИТЬ',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 28),
                        _SellerHeader(
                          seller: _seller,
                          followListenable: widget.sellerFollowListenable,
                          canFollowSeller: widget.canFollowSeller,
                          isFollowingSeller: widget.isFollowingSeller,
                          onToggleSellerFollow: widget.onToggleSellerFollow,
                        ),
                        const SizedBox(height: 16),
                        _SellerMeta(seller: _seller),
                        const SizedBox(height: 18),
                        _RatingPill(seller: _seller, onTap: _openReviews),
                        const SizedBox(height: 22),
                        Text(
                          'Написать продавцу',
                          style: TextStyle(
                            fontSize: 24,
                            height: 1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                            color: context.appPalette.ink,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _MessageBar(
                          onTap: _isRunningSellerAction ? null : _openMessage,
                        ),
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
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: context.appPalette.muted,
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
  const _TopBar({
    required this.onBack,
    required this.onShare,
    required this.onMore,
  });

  final VoidCallback onBack;
  final VoidCallback? onShare;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _TopIconButton(icon: Icons.arrow_back_ios_new, onTap: onBack),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TopIconButton(icon: Icons.ios_share, onTap: onShare),
            _TopIconButton(icon: Icons.more_horiz_rounded, onTap: onMore),
          ],
        ),
      ],
    );
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(
          icon,
          color: onTap == null
              ? context.appPalette.muted
              : context.appPalette.ink,
          size: 23,
        ),
      ),
    );
  }
}

class _SellerHeader extends StatelessWidget {
  const _SellerHeader({
    required this.seller,
    this.followListenable,
    this.canFollowSeller,
    this.isFollowingSeller,
    this.onToggleSellerFollow,
  });

  final SellerProfile seller;
  final Listenable? followListenable;
  final bool Function(String sellerId)? canFollowSeller;
  final bool Function(String sellerId)? isFollowingSeller;
  final Future<bool> Function(String sellerId)? onToggleSellerFollow;

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
                style: TextStyle(
                  fontSize: 28,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                  color: context.appPalette.ink,
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
                    color: context.appPalette.muted,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  SellerFollowButton(
                    sellerId: seller.id,
                    listenable: followListenable,
                    canFollow: canFollowSeller,
                    isFollowing: isFollowingSeller,
                    onToggle: onToggleSellerFollow,
                  ),
                  const SizedBox(width: 14),
                  Flexible(
                    child: Text(
                      _followersText(seller.followersCount),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: context.appPalette.ink,
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
      decoration: BoxDecoration(
        color: context.appPalette.surfaceMuted,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        seller.name.trim().isEmpty
            ? '?'
            : seller.name.characters.first.toUpperCase(),
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
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
            style: TextStyle(
              fontSize: 16,
              height: 1.12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
              color: context.appPalette.ink,
            ),
          ),
        if (seller.city.trim().isNotEmpty) const SizedBox(height: 8),
        Text(
          'Частное лицо',
          style: TextStyle(
            fontSize: 16,
            height: 1,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
            color: context.appPalette.ink,
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
    final scheme = Theme.of(context).colorScheme;
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
          color: scheme.primary,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Text(
              rating.toStringAsFixed(1).replaceAll('.', ','),
              style: TextStyle(
                fontSize: 28,
                height: 1,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                color: scheme.onPrimary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: _Stars(rating: rating.toDouble())),
            const SizedBox(width: 14),
            Flexible(
              child: Text(
                _reviewCountLabel(seller.salesCount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                  color: scheme.onPrimary,
                ),
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
                : Theme.of(
                    context,
                  ).colorScheme.onPrimary.withValues(alpha: 0.3),
          );
        }),
      ),
    );
  }
}

class _MessageBar extends StatelessWidget {
  const _MessageBar({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: 22, right: 16),
        decoration: BoxDecoration(
          color: context.appPalette.surfaceMuted,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                onTap == null ? 'открываем чат…' : 'введите сообщение',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                  color: context.appPalette.muted,
                ),
              ),
            ),
            Icon(
              Icons.send,
              size: 23,
              color: onTap == null
                  ? context.appPalette.muted
                  : Theme.of(context).colorScheme.primary,
            ),
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
      decoration: BoxDecoration(color: context.appPalette.page),
      child: Padding(
        padding: EdgeInsets.only(top: topInset),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.appPalette.surface,
            border: Border(
              top: BorderSide(color: context.appPalette.ink, width: 2),
              bottom: BorderSide(color: context.appPalette.border, width: 1),
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
              style: TextStyle(
                fontSize: 16,
                height: 1,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                color: context.appPalette.ink,
              ),
            ),
          ),
          if (isActive)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.primary,
                child: const SizedBox(height: 3),
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
  final Future<void> Function() onLike;
  final VoidCallback onShare;

  @override
  State<_SellerProductCard> createState() => _SellerProductCardState();
}

class _SellerProductCardState extends State<_SellerProductCard> {
  late bool _isLiked = widget.product.isLiked;
  bool _isUpdatingLike = false;

  @override
  void didUpdateWidget(covariant _SellerProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.isLiked != widget.product.isLiked) {
      _isLiked = widget.product.isLiked;
    }
  }

  Future<void> _toggleLike() async {
    if (_isUpdatingLike) return;
    final previous = _isLiked;
    setState(() {
      _isUpdatingLike = true;
      _isLiked = !_isLiked;
    });
    try {
      await widget.onLike();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLiked = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось обновить избранное. Попробуйте ещё раз.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUpdatingLike = false);
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
              style: TextStyle(
                fontSize: 13.5,
                height: 1.08,
                fontWeight: FontWeight.w500,
                color: context.appPalette.ink,
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
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: context.appPalette.ink,
                    ),
                  ),
                ),
                _SmallIconButton(
                  icon: _isLiked ? Icons.favorite : Icons.favorite_border,
                  onTap: _isUpdatingLike ? null : _toggleLike,
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 30,
        height: 28,
        child: Icon(
          icon,
          size: 22,
          color: onTap == null
              ? context.appPalette.muted
              : context.appPalette.ink,
        ),
      ),
    );
  }
}

String _followersText(int count) {
  final value = count.toString();
  return '$value подписчика';
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
