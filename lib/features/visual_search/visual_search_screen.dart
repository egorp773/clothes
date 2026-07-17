import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_appearance.dart';
import '../../core/app_typography.dart';
import '../../models/product.dart';
import '../../screens/catalog_screen.dart';
import '../listing_publish/data/listing_catalogs.dart';
import 'visual_search_service.dart';

class VisualSearchScreen extends StatefulWidget {
  const VisualSearchScreen({
    super.key,
    required this.initialImage,
    required this.onProductTap,
    required this.onToggleLike,
    required this.onProductMenu,
    required this.onShareProduct,
    this.catalogProducts = const [],
    this.service,
    this.initialResult,
    this.initialPreviewBytes,
  });

  final XFile initialImage;
  final ValueChanged<Product> onProductTap;
  final Future<void> Function(String productId) onToggleLike;
  final List<Product> catalogProducts;
  final ValueChanged<Product> onProductMenu;
  final ValueChanged<Product> onShareProduct;
  final VisualSearchService? service;
  final VisualSearchResult? initialResult;
  final Uint8List? initialPreviewBytes;

  @override
  State<VisualSearchScreen> createState() => _VisualSearchScreenState();
}

class _VisualSearchScreenState extends State<VisualSearchScreen> {
  late final VisualSearchService _service;
  XFile? _image;
  Uint8List? _previewBytes;
  VisualSearchResult? _result;
  VisualSearchFilters _filters = const VisualSearchFilters();
  bool _searching = false;
  String? _error;
  final Set<String> _updatingLikeIds = <String>{};

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? VisualSearchService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialImage());
  }

  Future<void> _loadInitialImage() async {
    final bytes =
        widget.initialPreviewBytes ?? await widget.initialImage.readAsBytes();
    if (!mounted) return;
    setState(() {
      _image = widget.initialImage;
      _previewBytes = bytes;
      _result = widget.initialResult;
    });
    if (widget.initialResult == null) await _search(imageBytes: bytes);
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<void> _search({Uint8List? imageBytes}) async {
    final image = _image;
    if (image == null || _searching) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final result = await _service.search(
        image,
        filters: _filters,
        imageBytes: imageBytes ?? _previewBytes,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } on VisualSearchException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'Поиск по фото временно недоступен. Каталог продолжает работать.',
      );
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _backToCamera() => Navigator.maybePop(context);

  Future<void> _toggleLike(Product product) async {
    if (!_updatingLikeIds.add(product.id)) return;
    try {
      final update = widget.onToggleLike(product.id);
      if (mounted) setState(() {});
      await update;
      if (mounted) setState(() {});
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Не удалось обновить избранное'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      _updatingLikeIds.remove(product.id);
    }
  }

  Future<void> _showFilters() async {
    final minController = TextEditingController(
      text: _filters.minPrice?.round().toString() ?? '',
    );
    final maxController = TextEditingController(
      text: _filters.maxPrice?.round().toString() ?? '',
    );
    var size = _filters.sizes.firstOrNull;
    var brand = _filters.brands.firstOrNull;
    var condition = _filters.conditions.firstOrNull;
    var color = _filters.colors.firstOrNull;
    final selected = await showModalBottomSheet<VisualSearchFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appPalette.surfaceRaised,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            0,
            18,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Фильтры',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 18,
                    fontWeight: AppTypography.semiBold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: minController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Цена от',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: maxController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Цена до',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _FilterChoiceSection(
                  label: 'Размер',
                  value: size,
                  options: [
                    ...ListingCatalogs.universalSizes,
                    ...ListingCatalogs.shoeSizes,
                  ],
                  onChanged: (value) => setSheetState(() => size = value),
                ),
                _FilterChoiceSection(
                  label: 'Бренд',
                  value: brand,
                  options: ListingCatalogs.brands,
                  onChanged: (value) => setSheetState(() => brand = value),
                ),
                _FilterChoiceSection(
                  label: 'Состояние',
                  value: condition,
                  options: ListingCatalogs.conditions,
                  onChanged: (value) => setSheetState(() => condition = value),
                ),
                _FilterChoiceSection(
                  label: 'Цвет',
                  value: color,
                  options: ListingCatalogs.colors,
                  onChanged: (value) => setSheetState(() => color = value),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.pop(context, const VisualSearchFilters()),
                        child: const Text('Сбросить'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          overlayColor: Colors.transparent,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimary,
                        ),
                        onPressed: () => Navigator.pop(
                          context,
                          VisualSearchFilters(
                            minPrice: double.tryParse(minController.text),
                            maxPrice: double.tryParse(maxController.text),
                            sizes: size == null ? const [] : [size!],
                            brands: brand == null ? const [] : [brand!],
                            conditions: condition == null
                                ? const []
                                : [condition!],
                            colors: color == null ? const [] : [color!],
                          ),
                        ),
                        child: const Text('Применить'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    minController.dispose();
    maxController.dispose();
    if (selected == null || !mounted) return;
    setState(() => _filters = selected);
    await _search();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    appBar: AppBar(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'Поиск по фото',
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 17,
          fontWeight: AppTypography.semiBold,
        ),
      ),
      actions: [
        if (_image != null)
          IconButton(
            tooltip: 'Фильтры',
            onPressed: _searching ? null : _showFilters,
            icon: Badge(
              isLabelVisible: !_filters.isEmpty,
              child: const Icon(Icons.tune_rounded),
            ),
          ),
      ],
    ),
    body: _image == null
        ? Center(
            child: CircularProgressIndicator(color: context.appPalette.ink),
          )
        : _buildResults(),
  );

  Widget _buildResults() {
    final exactProducts = _catalogProductsFor(
      _result?.products ?? const <Product>[],
    );
    final similarProducts = _catalogProductsFor(
      _result?.similarProducts ?? const <Product>[],
    );
    final similarOnly = exactProducts.isEmpty && similarProducts.isNotEmpty;
    final products = similarOnly ? similarProducts : exactProducts;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 74,
                    height: 74,
                    child: Image.memory(_previewBytes!, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _searching
                            ? 'Ищем похожие вещи…'
                            : similarOnly
                            ? 'Похожие варианты'
                            : _productsCountLabel(products.length),
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 15,
                          fontWeight: AppTypography.semiBold,
                        ),
                      ),
                      if (_result?.timingsMs['total'] case final int total)
                        Text(
                          'Поиск ${(total / 1000).toStringAsFixed(1)} с',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.appPalette.muted,
                          ),
                        ),
                      TextButton(
                        onPressed: _searching ? null : _backToCamera,
                        child: const Text('Новое фото'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_searching)
          SliverToBoxAdapter(
            child: LinearProgressIndicator(
              minHeight: 2,
              color: context.appPalette.ink,
              backgroundColor: context.appPalette.border,
            ),
          ),
        if (_error != null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _MessageState(
              icon: Icons.cloud_off_outlined,
              title: _error!,
              subtitle:
                  'Можно вернуться в каталог или попробовать другое фото.',
              action: 'Повторить',
              onTap: _search,
            ),
          )
        else if (!_searching && _result != null && products.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _MessageState(
              icon: Icons.search_off_rounded,
              title: 'Похоже, такую вещь у нас ещё никто не выложил',
              subtitle:
                  'Попробуйте выделить вещь точнее или загрузить другой ракурс.',
              action: 'Сделать новое фото',
              onTap: _backToCamera,
            ),
          )
        else ...[
          if (similarOnly)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Похоже, такую вещь у нас ещё никто не выложил',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 17,
                        fontWeight: AppTypography.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Но мы нашли несколько действительно похожих вариантов.',
                      style: TextStyle(
                        color: context.appPalette.muted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Смотрите похожее',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 16,
                        fontWeight: AppTypography.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 28),
            sliver: SliverGrid.builder(
              itemCount: products.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 7,
                mainAxisSpacing: 4,
                mainAxisExtent: 320,
              ),
              itemBuilder: (context, index) {
                final product = products[index];
                return ProductCard(
                  key: ValueKey<String>('visual-search-product-${product.id}'),
                  product: product,
                  scale: 1,
                  onTap: () => widget.onProductTap(product),
                  onLike: () => _toggleLike(product),
                  onMenu: () => widget.onProductMenu(product),
                  onShare: () => widget.onShareProduct(product),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  List<Product> _catalogProductsFor(List<Product> searchProducts) {
    return resolveVisualSearchCatalogProducts(
      searchProducts: searchProducts,
      catalogProducts: widget.catalogProducts,
    );
  }

  String _productsCountLabel(int count) {
    final mod100 = count % 100;
    final mod10 = count % 10;
    if (mod100 >= 11 && mod100 <= 14) return '$count похожих товаров';
    if (mod10 == 1) return '$count похожий товар';
    if (mod10 >= 2 && mod10 <= 4) return '$count похожих товара';
    return '$count похожих товаров';
  }
}

/// Resolves search candidates to the current catalog snapshot by product ID.
///
/// Visual-search rows are intentionally treated as ranking references rather
/// than display models: they can be sparse or stale and may contain a matched
/// embedding image that is not the product's primary catalog image. Unknown
/// IDs are omitted so they cannot open an incomplete product detail page.
List<Product> resolveVisualSearchCatalogProducts({
  required Iterable<Product> searchProducts,
  required Iterable<Product> catalogProducts,
}) {
  final catalogById = <String, Product>{
    for (final product in catalogProducts)
      if (product.id.trim().isNotEmpty) product.id.trim(): product,
  };
  if (catalogById.isEmpty) return const [];

  final resolved = <Product>[];
  final seenIds = <String>{};
  for (final candidate in searchProducts) {
    final id = candidate.id.trim();
    final product = catalogById[id];
    if (product == null || !seenIds.add(id)) continue;
    resolved.add(product);
  }
  return List.unmodifiable(resolved);
}

class _FilterChoiceSection extends StatelessWidget {
  const _FilterChoiceSection({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<CatalogOption> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12.5,
            fontWeight: AppTypography.bold,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 9),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: options.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 7),
            itemBuilder: (context, index) {
              final option = index == 0 ? null : options[index - 1];
              final id = option?.id;
              final selected = value == id;
              return ChoiceChip(
                label: Text(option?.name ?? 'Любой'),
                selected: selected,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                side: BorderSide(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : context.appPalette.border,
                ),
                backgroundColor: context.appPalette.surface,
                selectedColor: Theme.of(context).colorScheme.primary,
                labelStyle: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12,
                  fontWeight: AppTypography.semiBold,
                  color: selected
                      ? Theme.of(context).colorScheme.onPrimary
                      : context.appPalette.ink,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                onSelected: (_) => onChanged(id),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 46, color: context.appPalette.muted),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.appPalette.muted),
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onTap, child: Text(action)),
        ],
      ),
    ),
  );
}
