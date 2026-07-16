import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_typography.dart';
import '../../models/product.dart';
import '../../screens/catalog_screen.dart' show ProductCard;
import 'catalog_search_engine.dart';
import 'catalog_search_history.dart';

class CatalogSearchScreen extends StatefulWidget {
  const CatalogSearchScreen({
    super.key,
    required this.products,
    required this.index,
    required this.history,
    required this.onProductTap,
    required this.onToggleLike,
    required this.onProductMenu,
    this.onShareProduct,
    this.initialQuery = '',
  });

  final List<Product> products;
  final CatalogSearchIndex index;
  final CatalogSearchHistory history;
  final ValueChanged<Product> onProductTap;
  final Future<void> Function(String productId) onToggleLike;
  final ValueChanged<Product> onProductMenu;
  final ValueChanged<Product>? onShareProduct;
  final String initialQuery;

  @override
  State<CatalogSearchScreen> createState() => _CatalogSearchScreenState();
}

enum _SearchView { discovery, suggestions, results }

enum _SearchSort { relevance, cheapest, expensive, newest }

class _CatalogSearchScreenState extends State<CatalogSearchScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );
  late final FocusNode _focusNode = FocusNode();
  late final List<CatalogSearchSuggestion> _discoverySuggestions =
      _buildDiscoverySuggestions();
  final Map<String, bool> _likedOverrides = {};

  List<String> _recentQueries = const [];
  bool _historyLoading = true;
  late _SearchView _view =
      CatalogSearchIndex.normalize(widget.initialQuery).isEmpty
      ? _SearchView.discovery
      : _SearchView.suggestions;
  _SearchSort _sort = _SearchSort.relevance;
  String _submittedQuery = '';
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    unawaited(_loadHistory());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onQueryChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    List<String> queries;
    try {
      queries = await widget.history.load();
    } catch (_) {
      queries = const [];
    }
    if (!mounted) return;
    setState(() {
      _recentQueries = queries;
      _historyLoading = false;
    });
  }

  void _onQueryChanged() {
    final normalized = CatalogSearchIndex.normalize(_controller.text);
    final submitted = CatalogSearchIndex.normalize(_submittedQuery);
    if (_view == _SearchView.results && normalized == submitted) return;
    setState(() {
      _view = normalized.isEmpty
          ? _SearchView.discovery
          : _SearchView.suggestions;
      _submittedQuery = '';
      _selectedCategory = null;
    });
  }

  void _clearQuery() {
    _controller.clear();
    _focusNode.requestFocus();
  }

  void _submit([String? value]) {
    final query = (value ?? _controller.text).trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    if (query.isEmpty) {
      _clearQuery();
      return;
    }

    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    FocusScope.of(context).unfocus();
    setState(() {
      _submittedQuery = query;
      _selectedCategory = null;
      _sort = _SearchSort.relevance;
      _view = _SearchView.results;
    });
    unawaited(_rememberQuery(query));
  }

  Future<void> _rememberQuery(String query) async {
    try {
      final queries = await widget.history.add(query);
      if (!mounted) return;
      setState(() => _recentQueries = queries);
    } catch (_) {
      // Search stays available when local history cannot be persisted.
    }
  }

  Future<void> _removeRecent(String query) async {
    try {
      final queries = await widget.history.remove(query);
      if (!mounted) return;
      setState(() => _recentQueries = queries);
    } catch (_) {
      // A failed history write must not block search.
    }
  }

  Future<void> _clearHistory() async {
    try {
      await widget.history.clear();
      if (!mounted) return;
      setState(() => _recentQueries = const []);
    } catch (_) {
      // A failed history write must not block search.
    }
  }

  List<CatalogSearchSuggestion> get _querySuggestions =>
      widget.index.suggestions(_controller.text, limit: 40).take(9).toList();

  List<CatalogSearchSuggestion> _buildDiscoverySuggestions() {
    final seeds = <String>{};
    for (final product in widget.products.where((item) => !item.isHidden)) {
      for (final value in <String>[
        product.brand,
        product.normalizedBrand,
        product.category,
        product.normalizedCategory,
        product.itemType,
        product.subcategory,
        product.material,
        product.primaryColor,
        product.color,
        product.style,
      ]) {
        final seed = value.trim();
        if (CatalogSearchIndex.normalize(seed).length >= 2) seeds.add(seed);
      }
      if (seeds.length >= 42) break;
    }

    final byQuery = <String, CatalogSearchSuggestion>{};
    for (final seed in seeds) {
      for (final suggestion in widget.index.suggestions(seed, limit: 6)) {
        final key = CatalogSearchIndex.normalize(suggestion.query);
        if (key.isNotEmpty) byQuery.putIfAbsent(key, () => suggestion);
      }
    }
    final suggestions = byQuery.values.toList()
      ..sort((a, b) {
        final kindOrder = _suggestionKindWeight(
          a.kind,
        ).compareTo(_suggestionKindWeight(b.kind));
        if (kindOrder != 0) return kindOrder;
        return a.label.compareTo(b.label);
      });
    return suggestions.take(12).toList(growable: false);
  }

  static int _suggestionKindWeight(CatalogSearchSuggestionKind kind) =>
      switch (kind) {
        CatalogSearchSuggestionKind.category => 0,
        CatalogSearchSuggestionKind.brand => 1,
        CatalogSearchSuggestionKind.composite => 2,
        CatalogSearchSuggestionKind.characteristic => 3,
      };

  List<({Product product, int score})> get _rankedMatches {
    final normalized = CatalogSearchIndex.normalize(_submittedQuery);
    if (normalized.isEmpty) return const [];
    final matches = <({Product product, int score})>[];
    for (final product in widget.products) {
      if (product.isHidden) continue;
      final score = widget.index.scoreNormalized(product, normalized);
      if (score > 0) matches.add((product: product, score: score));
    }
    return matches;
  }

  List<String> get _resultCategories {
    final categories = <String>{
      for (final item in _rankedMatches)
        if (_categoryLabel(item.product).isNotEmpty)
          _categoryLabel(item.product),
    }.toList()..sort();
    return categories;
  }

  List<Product> get _results {
    final matches = _rankedMatches.where((item) {
      return _selectedCategory == null ||
          _categoryLabel(item.product) == _selectedCategory;
    }).toList();
    matches.sort((a, b) {
      return switch (_sort) {
        _SearchSort.relevance =>
          b.score.compareTo(a.score) != 0
              ? b.score.compareTo(a.score)
              : a.product.title.compareTo(b.product.title),
        _SearchSort.cheapest => a.product.priceValue.compareTo(
          b.product.priceValue,
        ),
        _SearchSort.expensive => b.product.priceValue.compareTo(
          a.product.priceValue,
        ),
        _SearchSort.newest => b.product.id.compareTo(a.product.id),
      };
    });
    return matches.map((item) => item.product).toList();
  }

  static String _categoryLabel(Product product) {
    for (final value in <String>[
      product.category,
      product.itemType,
      product.normalizedCategory,
    ]) {
      if (value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  Future<void> _toggleLike(Product product) async {
    final previous = _likedOverrides[product.id] ?? product.isLiked;
    setState(() => _likedOverrides[product.id] = !previous);
    try {
      await widget.onToggleLike(product.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _likedOverrides[product.id] = previous);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _SearchHeader(
              controller: _controller,
              focusNode: _focusNode,
              onBack: () => Navigator.maybePop(context),
              onClear: _clearQuery,
              onSubmitted: _submit,
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFFE8E8EA)),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return switch (_view) {
      _SearchView.discovery => _DiscoveryView(
        historyLoading: _historyLoading,
        recentQueries: _recentQueries,
        suggestions: _discoverySuggestions,
        onQuerySelected: _submit,
        onRemoveRecent: _removeRecent,
        onClearHistory: _clearHistory,
      ),
      _SearchView.suggestions => _SuggestionView(
        query: _controller.text.trim(),
        suggestions: _querySuggestions,
        onSelected: _submit,
        onSubmit: () => _submit(),
      ),
      _SearchView.results => _ResultsView(
        query: _submittedQuery,
        products: _results,
        categories: _resultCategories,
        selectedCategory: _selectedCategory,
        sort: _sort,
        likedOverrides: _likedOverrides,
        onCategoryChanged: (category) {
          setState(() => _selectedCategory = category);
        },
        onSortChanged: (sort) => setState(() => _sort = sort),
        onProductTap: widget.onProductTap,
        onToggleLike: _toggleLike,
        onProductMenu: widget.onProductMenu,
        onShareProduct: widget.onShareProduct ?? widget.onProductMenu,
      ),
    };
  }
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.controller,
    required this.focusNode,
    required this.onBack,
    required this.onClear,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onBack;
  final VoidCallback onClear;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 10),
      child: Row(
        children: [
          IconButton(
            key: const Key('catalog-search-back'),
            tooltip: 'Назад',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 25),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, child) {
                return TextField(
                  key: const Key('catalog-search-field'),
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: onSubmitted,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 15,
                    fontWeight: AppTypography.medium,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Поиск по товарам',
                    hintStyle: const TextStyle(
                      color: Color(0xFF85858B),
                      fontWeight: FontWeight.w500,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 21,
                      color: Color(0xFF303035),
                    ),
                    suffixIcon: value.text.isEmpty
                        ? null
                        : IconButton(
                            key: const Key('catalog-search-clear'),
                            tooltip: 'Очистить',
                            onPressed: onClear,
                            splashRadius: 18,
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 19,
                              color: Color(0xFF77777E),
                            ),
                          ),
                    filled: true,
                    fillColor: const Color(0xFFF2F2F4),
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: BorderSide.none,
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

class _DiscoveryView extends StatelessWidget {
  const _DiscoveryView({
    required this.historyLoading,
    required this.recentQueries,
    required this.suggestions,
    required this.onQuerySelected,
    required this.onRemoveRecent,
    required this.onClearHistory,
  });

  final bool historyLoading;
  final List<String> recentQueries;
  final List<CatalogSearchSuggestion> suggestions;
  final ValueChanged<String> onQuerySelected;
  final ValueChanged<String> onRemoveRecent;
  final VoidCallback onClearHistory;

  @override
  Widget build(BuildContext context) {
    if (historyLoading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (recentQueries.isEmpty && suggestions.isEmpty) {
      return const _SearchMessage(
        icon: Icons.search_rounded,
        title: 'Что хотите найти?',
        subtitle: 'Введите категорию, бренд, цвет или характеристику вещи',
      );
    }

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
      children: [
        if (recentQueries.isNotEmpty) ...[
          _SectionTitle(
            title: 'Недавние запросы',
            action: 'Очистить',
            onAction: onClearHistory,
          ),
          const SizedBox(height: 5),
          for (final query in recentQueries)
            _RecentQueryRow(
              query: query,
              onTap: () => onQuerySelected(query),
              onRemove: () => onRemoveRecent(query),
            ),
          const SizedBox(height: 22),
        ],
        if (suggestions.isNotEmpty) ...[
          const _SectionTitle(title: 'Популярное в каталоге'),
          const SizedBox(height: 5),
          for (final suggestion in suggestions)
            _SuggestionRow(
              suggestion: suggestion,
              onTap: () => onQuerySelected(suggestion.query),
            ),
        ],
      ],
    );
  }
}

class _SuggestionView extends StatelessWidget {
  const _SuggestionView({
    required this.query,
    required this.suggestions,
    required this.onSelected,
    required this.onSubmit,
  });

  final String query;
  final List<CatalogSearchSuggestion> suggestions;
  final ValueChanged<String> onSelected;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        _TypedQueryRow(query: query, onTap: onSubmit),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 13),
          const _SectionTitle(title: 'Варианты поиска'),
          const SizedBox(height: 5),
          for (final suggestion in suggestions)
            _SuggestionRow(
              suggestion: suggestion,
              onTap: () => onSelected(suggestion.query),
            ),
        ],
      ],
    );
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView({
    required this.query,
    required this.products,
    required this.categories,
    required this.selectedCategory,
    required this.sort,
    required this.likedOverrides,
    required this.onCategoryChanged,
    required this.onSortChanged,
    required this.onProductTap,
    required this.onToggleLike,
    required this.onProductMenu,
    required this.onShareProduct,
  });

  final String query;
  final List<Product> products;
  final List<String> categories;
  final String? selectedCategory;
  final _SearchSort sort;
  final Map<String, bool> likedOverrides;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<_SearchSort> onSortChanged;
  final ValueChanged<Product> onProductTap;
  final ValueChanged<Product> onToggleLike;
  final ValueChanged<Product> onProductMenu;
  final ValueChanged<Product> onShareProduct;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  query,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _resultCountLabel(products.length),
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF85858B),
                  ),
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _SortControl(value: sort, onChanged: onSortChanged),
                      if (categories.length > 1) ...[
                        const SizedBox(width: 8),
                        _CategoryControl(
                          categories: categories,
                          value: selectedCategory,
                          onChanged: onCategoryChanged,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (products.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _SearchMessage(
              icon: Icons.manage_search_rounded,
              title: 'Ничего не нашли',
              subtitle: selectedCategory == null
                  ? 'Попробуйте изменить запрос или проверить написание'
                  : 'Сбросьте категорию или измените запрос',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 36),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate((context, index) {
                final product = products[index];
                final resolvedProduct = product.copyWith(
                  isLiked: likedOverrides[product.id] ?? product.isLiked,
                );
                return ProductCard(
                  product: resolvedProduct,
                  scale: 1,
                  onTap: () => onProductTap(resolvedProduct),
                  onLike: () => onToggleLike(resolvedProduct),
                  onMenu: () => onProductMenu(resolvedProduct),
                  onShare: () => onShareProduct(resolvedProduct),
                );
              }, childCount: products.length),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 7,
                mainAxisSpacing: 4,
                mainAxisExtent: 320,
              ),
            ),
          ),
      ],
    );
  }

  static String _resultCountLabel(int count) {
    final mod100 = count % 100;
    if (mod100 >= 11 && mod100 <= 14) return '$count объявлений';
    return switch (count % 10) {
      1 => '$count объявление',
      2 || 3 || 4 => '$count объявления',
      _ => '$count объявлений',
    };
  }
}

class _TypedQueryRow extends StatelessWidget {
  const _TypedQueryRow({required this.query, required this.onTap});

  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: const Key('catalog-search-submit-query'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 3),
      leading: const Icon(Icons.search_rounded, color: Color(0xFF202024)),
      title: Text(
        'Искать «$query»',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: const Icon(Icons.arrow_forward_rounded, size: 20),
      onTap: onTap,
    );
  }
}

class _RecentQueryRow extends StatelessWidget {
  const _RecentQueryRow({
    required this.query,
    required this.onTap,
    required this.onRemove,
  });

  final String query;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 3),
      minLeadingWidth: 24,
      leading: const Icon(
        Icons.history_rounded,
        size: 21,
        color: Color(0xFF77777E),
      ),
      title: Text(
        query,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: IconButton(
        tooltip: 'Удалить запрос',
        onPressed: onRemove,
        icon: const Icon(Icons.close_rounded, size: 18),
      ),
      onTap: onTap,
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.suggestion, required this.onTap});

  final CatalogSearchSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 3),
      minLeadingWidth: 24,
      leading: Icon(_icon, size: 21, color: const Color(0xFF77777E)),
      title: Text(
        suggestion.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        _kindLabel,
        style: const TextStyle(fontSize: 11.5, color: Color(0xFF8C8C92)),
      ),
      trailing: const Icon(
        Icons.north_west_rounded,
        size: 17,
        color: Color(0xFF77777E),
      ),
      onTap: onTap,
    );
  }

  IconData get _icon => switch (suggestion.kind) {
    CatalogSearchSuggestionKind.brand => Icons.sell_outlined,
    CatalogSearchSuggestionKind.category => Icons.category_outlined,
    CatalogSearchSuggestionKind.composite => Icons.tune_rounded,
    CatalogSearchSuggestionKind.characteristic => Icons.tune_rounded,
  };

  String get _kindLabel => switch (suggestion.kind) {
    CatalogSearchSuggestionKind.brand => 'Бренд',
    CatalogSearchSuggestionKind.category => 'Категория',
    CatalogSearchSuggestionKind.composite => 'Подборка',
    CatalogSearchSuggestionKind.characteristic => 'Характеристика',
  };
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF65656B),
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}

class _SortControl extends StatelessWidget {
  const _SortControl({required this.value, required this.onChanged});

  final _SearchSort value;
  final ValueChanged<_SearchSort> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_SearchSort>(
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in _SearchSort.values)
          PopupMenuItem(value: option, child: Text(_sortLabel(option))),
      ],
      child: _ControlChip(
        icon: Icons.swap_vert_rounded,
        label: _sortLabel(value),
      ),
    );
  }

  static String _sortLabel(_SearchSort sort) => switch (sort) {
    _SearchSort.relevance => 'По релевантности',
    _SearchSort.cheapest => 'Сначала дешевле',
    _SearchSort.expensive => 'Сначала дороже',
    _SearchSort.newest => 'Сначала новые',
  };
}

class _CategoryControl extends StatelessWidget {
  const _CategoryControl({
    required this.categories,
    required this.value,
    required this.onChanged,
  });

  final List<String> categories;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: value ?? '',
      onSelected: (selected) => onChanged(selected.isEmpty ? null : selected),
      itemBuilder: (context) => [
        const PopupMenuItem(value: '', child: Text('Все категории')),
        for (final category in categories)
          PopupMenuItem(value: category, child: Text(category)),
      ],
      child: _ControlChip(
        icon: Icons.tune_rounded,
        label: value ?? 'Категория',
        active: value != null,
      ),
    );
  }
}

class _ControlChip extends StatelessWidget {
  const _ControlChip({
    required this.icon,
    required this.label,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFEEEEF0) : Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: active ? const Color(0xFFBDBDC3) : const Color(0xFFDEDEE1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 3),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 17),
        ],
      ),
    );
  }
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 38),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: const Color(0xFFB1B1B6)),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.35,
                color: Color(0xFF77777E),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
