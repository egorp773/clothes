import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_appearance.dart';
import '../models/app_profile.dart';
import '../models/product.dart';
import '../widgets/app_image.dart';

enum ReviewSort { helpful, newest, oldest, positive, negative }

class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({
    super.key,
    required this.seller,
    required this.sourceProduct,
    required this.loadReviews,
    required this.onCreateReview,
    required this.canCreateReview,
  });

  final SellerProfile seller;
  final Product? sourceProduct;
  final Future<List<SellerReview>> Function(String sellerId) loadReviews;
  final Future<void> Function({
    required String sellerId,
    required String productId,
    required String productTitle,
    required String productImage,
    required int rating,
    required String text,
    bool hasPhoto,
  })?
  onCreateReview;
  final bool canCreateReview;

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  List<SellerReview> _reviews = const [];
  ReviewSort _sort = ReviewSort.helpful;
  bool _onlyPhoto = false;
  bool _isLoading = true;
  bool _isReloading = false;
  bool _isSubmittingReview = false;
  String? _loadError;

  bool get _canWriteReview =>
      widget.sourceProduct != null && widget.onCreateReview != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loadError = null;
        _isReloading = !_isLoading;
      });
    }
    try {
      final reviews = await widget.loadReviews(widget.seller.id);
      if (!mounted) return;
      setState(() => _reviews = reviews);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Не удалось загрузить отзывы';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isReloading = false;
        });
      }
    }
  }

  List<SellerReview> get _visibleReviews {
    final next = _reviews
        .where((review) => !_onlyPhoto || review.hasPhoto)
        .toList();
    switch (_sort) {
      case ReviewSort.helpful:
        next.sort((a, b) {
          final byRating = b.rating.compareTo(a.rating);
          return byRating == 0 ? b.createdAt.compareTo(a.createdAt) : byRating;
        });
      case ReviewSort.newest:
        next.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case ReviewSort.oldest:
        next.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case ReviewSort.positive:
        next.sort((a, b) => b.rating.compareTo(a.rating));
      case ReviewSort.negative:
        next.sort((a, b) => a.rating.compareTo(b.rating));
    }
    return next;
  }

  double get _rating {
    if (_reviews.isEmpty) {
      return widget.seller.salesCount > 0 ? widget.seller.rating : 0;
    }
    return _reviews.fold<int>(0, (sum, review) => sum + review.rating) /
        _reviews.length;
  }

  Future<void> _showSortSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        var selected = _sort;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
              decoration: BoxDecoration(
                color: context.appPalette.surfaceRaised,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(CupertinoIcons.xmark, size: 20),
                      ),
                      const Expanded(
                        child: Text(
                          'сортировка',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  ...ReviewSort.values.map(
                    (sort) => _SortOption(
                      title: _sortTitle(sort),
                      selected: selected == sort,
                      onTap: () => setSheetState(() => selected = sort),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() => _sort = selected);
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimary,
                        shape: const RoundedRectangleBorder(),
                      ),
                      child: const Text('ПРИМЕНИТЬ'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _createReview() async {
    if (_isSubmittingReview) return;
    final sourceProduct = widget.sourceProduct;
    final onCreateReview = widget.onCreateReview;
    if (sourceProduct == null || onCreateReview == null) return;
    if (!widget.canCreateReview) {
      _showSignInRequired();
      return;
    }
    final draft = await showModalBottomSheet<_ReviewDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appPalette.surfaceRaised,
      builder: (context) => const _ReviewEditor(),
    );
    if (draft == null) return;
    setState(() => _isSubmittingReview = true);
    try {
      await onCreateReview(
        sellerId: widget.seller.id,
        productId: sourceProduct.id,
        productTitle: sourceProduct.title,
        productImage: sourceProduct.image,
        rating: draft.rating,
        text: draft.text,
        hasPhoto: draft.hasPhoto,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Отзыв опубликован'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on SellerReviewSubmissionException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось опубликовать отзыв. Попробуйте ещё раз.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmittingReview = false);
    }
  }

  void _showSignInRequired() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Войдите в профиль, чтобы оставить отзыв'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final listBottomPadding = _canWriteReview ? 86 + bottomInset : 24.0;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 14, 14, 12),
                          child: SizedBox(
                            height: 44,
                            child: Row(
                              children: [
                                IconButton(
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(
                                    CupertinoIcons.back,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  'Отзывы',
                                  style: TextStyle(
                                    fontSize: 22,
                                    height: 1,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: context.appPalette.ink,
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                          child: _ReviewsSummary(
                            rating: _rating,
                            reviews: _reviews,
                            fallbackCount: widget.seller.salesCount,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                          child: Row(
                            children: [
                              Flexible(
                                child: _FilterChipButton(
                                  title: _sortTitle(_sort),
                                  selected: false,
                                  icon: CupertinoIcons.slider_horizontal_3,
                                  onTap: _showSortSheet,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: _FilterChipButton(
                                  title: 'только с фото',
                                  selected: _onlyPhoto,
                                  onTap: () =>
                                      setState(() => _onlyPhoto = !_onlyPhoto),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, listBottomPadding),
                    sliver: _isLoading
                        ? const SliverToBoxAdapter(child: _ReviewsLoading())
                        : _loadError != null
                        ? SliverToBoxAdapter(
                            child: _ReviewsLoadError(
                              message: _loadError!,
                              isReloading: _isReloading,
                              onRetry: _load,
                            ),
                          )
                        : _visibleReviews.isEmpty
                        ? SliverToBoxAdapter(
                            child: _EmptyReviews(
                              filtered: _onlyPhoto && _reviews.isNotEmpty,
                            ),
                          )
                        : SliverList.builder(
                            itemCount: _visibleReviews.length * 2 - 1,
                            itemBuilder: (context, index) {
                              if (index.isOdd) {
                                return Divider(
                                  height: 20,
                                  color: context.appPalette.border,
                                );
                              }
                              return _ReviewTile(
                                review: _visibleReviews[index ~/ 2],
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            if (_canWriteReview)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: context.appPalette.surfaceRaised,
                  border: Border(
                    top: BorderSide(color: context.appPalette.border),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomInset),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSubmittingReview ? null : _createReview,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        _isSubmittingReview ? 'ОТПРАВЛЯЕМ' : 'ОСТАВИТЬ ОТЗЫВ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
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

class _ReviewsSummary extends StatelessWidget {
  const _ReviewsSummary({
    required this.rating,
    required this.reviews,
    required this.fallbackCount,
  });

  final double rating;
  final List<SellerReview> reviews;
  final int fallbackCount;

  @override
  Widget build(BuildContext context) {
    final count = reviews.isEmpty ? fallbackCount : reviews.length;
    final buckets = {
      for (var stars = 1; stars <= 5; stars++)
        stars: reviews.where((review) => review.rating == stars).length,
    };
    final maxCount = buckets.values.fold<int>(
      1,
      (max, value) => value > max ? value : max,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rating.toStringAsFixed(1).replaceAll('.', ','),
                style: const TextStyle(
                  fontSize: 36,
                  height: 0.95,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              _StarsRow(rating: rating, size: 13),
              const SizedBox(height: 3),
              Text(
                _reviewCountLabel(count),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: List.generate(5, (index) {
              final stars = 5 - index;
              final value = buckets[stars] ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 66,
                      child: _StarsRow(rating: stars.toDouble(), size: 13),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: value / maxCount,
                        minHeight: 4,
                        backgroundColor: context.appPalette.surfaceMuted,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 18,
                      child: Text(
                        '$value',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _StarsRow extends StatelessWidget {
  const _StarsRow({required this.rating, required this.size});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          Icons.star,
          size: size,
          color: index < rating.round()
              ? const Color(0xFFFFB21A)
              : context.appPalette.border,
        );
      }),
    );
  }
}

class _EmptyReviews extends StatelessWidget {
  const _EmptyReviews({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 28, 10, 18),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: context.appPalette.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(
                CupertinoIcons.star,
                size: 25,
                color: context.appPalette.muted,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              filtered ? 'Нет отзывов с фото' : 'Пока нет отзывов',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                height: 1.1,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                color: context.appPalette.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              filtered
                  ? 'Попробуйте отключить фильтр, чтобы увидеть все отзывы.'
                  : 'Здесь появятся отзывы покупателей после завершённых сделок.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.25,
                fontWeight: FontWeight.w500,
                color: context.appPalette.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewsLoading extends StatelessWidget {
  const _ReviewsLoading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 54),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _ReviewsLoadError extends StatelessWidget {
  const _ReviewsLoadError({
    required this.message,
    required this.isReloading,
    required this.onRetry,
  });

  final String message;
  final bool isReloading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34),
      child: Column(
        children: [
          Icon(
            CupertinoIcons.exclamationmark_circle,
            size: 30,
            color: context.appPalette.muted,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: isReloading ? null : onRetry,
            child: Text(isReloading ? 'ЗАГРУЗКА…' : 'ПОВТОРИТЬ'),
          ),
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.title,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String title;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : context.appPalette.surfaceMuted,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? scheme.onPrimary : context.appPalette.ink,
                ),
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 8),
              Icon(
                icon,
                size: 15,
                color: selected ? scheme.onPrimary : context.appPalette.ink,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final SellerReview review;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppImage(
                imageUrl: review.buyerAvatar,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(999),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.buyerName.isEmpty
                          ? 'Покупатель'
                          : review.buyerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _dateText(review.createdAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.05,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StarsRow(rating: review.rating.toDouble(), size: 14),
              const SizedBox(width: 8),
              if (review.dealCompleted)
                const Flexible(
                  child: Text(
                    'Сделка состоялась',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            review.productTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              height: 1.15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (review.productImage.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            AppImage(
              imageUrl: review.productImage,
              width: 46,
              height: 46,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(6),
            ),
          ],
          if (review.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review.text,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.28,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SortOption extends StatelessWidget {
  const _SortOption({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: selected ? scheme.primary : context.appPalette.border,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewEditor extends StatefulWidget {
  const _ReviewEditor();

  @override
  State<_ReviewEditor> createState() => _ReviewEditorState();
}

class _ReviewEditorState extends State<_ReviewEditor> {
  final _controller = TextEditingController();
  int _rating = 5;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'оставить отзыв',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final value = index + 1;
              return IconButton(
                onPressed: () => setState(() => _rating = value),
                icon: Icon(
                  Icons.star,
                  color: value <= _rating
                      ? const Color(0xFFFFB21A)
                      : context.appPalette.border,
                ),
              );
            }),
          ),
          TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(hintText: 'Текст отзыва'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.photo_outlined,
                  size: 19,
                  color: context.appPalette.muted,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Фото к отзыву станет доступно после подключения защищённого хранилища отзывов.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      color: context.appPalette.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  _ReviewDraft(
                    rating: _rating,
                    text: _controller.text,
                    hasPhoto: false,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                shape: const RoundedRectangleBorder(),
              ),
              child: const Text('СОХРАНИТЬ'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewDraft {
  const _ReviewDraft({
    required this.rating,
    required this.text,
    required this.hasPhoto,
  });

  final int rating;
  final String text;
  final bool hasPhoto;
}

String _sortTitle(ReviewSort sort) {
  return switch (sort) {
    ReviewSort.helpful => 'сначала с высокой оценкой',
    ReviewSort.newest => 'сначала новые',
    ReviewSort.oldest => 'сначала старые',
    ReviewSort.positive => 'сначала положительные',
    ReviewSort.negative => 'сначала отрицательные',
  };
}

String _dateText(DateTime date) {
  const months = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
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
