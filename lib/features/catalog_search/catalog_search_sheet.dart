import 'package:flutter/material.dart';

import '../../core/app_typography.dart';
import 'catalog_search_engine.dart';
import 'catalog_search_history.dart';

class CatalogSearchSheet extends StatefulWidget {
  const CatalogSearchSheet({
    super.key,
    required this.initialQuery,
    required this.index,
    required this.history,
  });

  final String initialQuery;
  final CatalogSearchIndex index;
  final CatalogSearchHistory history;

  @override
  State<CatalogSearchSheet> createState() => _CatalogSearchSheetState();
}

class _CatalogSearchSheetState extends State<CatalogSearchSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );
  List<String> _recentQueries = const [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    _loadHistory();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onQueryChanged)
      ..dispose();
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
    setState(() => _recentQueries = queries);
  }

  void _onQueryChanged() => setState(() {});

  void _submit([String? query]) {
    Navigator.pop(context, (query ?? _controller.text).trim());
  }

  Future<void> _removeRecent(String query) async {
    List<String> queries;
    try {
      queries = await widget.history.remove(query);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _recentQueries = queries);
  }

  Future<void> _clearHistory() async {
    try {
      await widget.history.clear();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _recentQueries = const []);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final availableHeight =
        MediaQuery.sizeOf(context).height - bottomInset - 24;
    final sheetHeight = availableHeight.clamp(280.0, 540.0).toDouble();
    final suggestions = widget.index.suggestions(_controller.text);
    final showRecent = CatalogSearchIndex.normalize(_controller.text).isEmpty;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: sheetHeight,
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('catalog-search-field'),
                          controller: _controller,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            hintText: 'Название, категория или бренд',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _controller.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Очистить',
                                    onPressed: _controller.clear,
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                            filled: true,
                            fillColor: const Color(0xFFF2F2F3),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        key: const Key('catalog-search-submit'),
                        onPressed: _submit,
                        child: const Text('Найти'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: showRecent
                        ? _RecentQueries(
                            queries: _recentQueries,
                            onSelected: _submit,
                            onRemove: _removeRecent,
                            onClear: _clearHistory,
                          )
                        : _SearchSuggestions(
                            suggestions: suggestions,
                            query: _controller.text.trim(),
                            onSelected: _submit,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentQueries extends StatelessWidget {
  const _RecentQueries({
    required this.queries,
    required this.onSelected,
    required this.onRemove,
    required this.onClear,
  });

  final List<String> queries;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onRemove;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (queries.isEmpty) {
      return const _SearchEmptyState(
        icon: Icons.search_rounded,
        text: 'Начните вводить название, бренд или категорию',
      );
    }
    return Column(
      children: [
        _SectionHeader(
          title: 'Недавние запросы',
          action: 'Очистить',
          onTap: onClear,
        ),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.zero,
            itemCount: queries.length,
            itemBuilder: (context, index) {
              final query = queries[index];
              return ListTile(
                key: Key('catalog-recent-$index'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
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
                    fontWeight: AppTypography.medium,
                  ),
                ),
                trailing: IconButton(
                  tooltip: 'Удалить запрос',
                  onPressed: () => onRemove(query),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
                onTap: () => onSelected(query),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SearchSuggestions extends StatelessWidget {
  const _SearchSuggestions({
    required this.suggestions,
    required this.query,
    required this.onSelected,
  });

  final List<CatalogSearchSuggestion> suggestions;
  final String query;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      return _SearchEmptyState(
        icon: Icons.manage_search_rounded,
        text: 'Нажмите «Найти», чтобы искать «$query»',
      );
    }
    return Column(
      children: [
        const _SectionHeader(title: 'Подсказки'),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.zero,
            itemCount: suggestions.length,
            itemBuilder: (context, index) {
              final suggestion = suggestions[index];
              return ListTile(
                key: Key('catalog-suggestion-$index'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                minLeadingWidth: 24,
                leading: Icon(
                  _iconFor(suggestion.kind),
                  size: 21,
                  color: const Color(0xFF77777E),
                ),
                title: Text(
                  suggestion.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    fontWeight: AppTypography.medium,
                  ),
                ),
                subtitle: Text(
                  _kindLabel(suggestion.kind),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8F8F94),
                  ),
                ),
                trailing: const Icon(Icons.north_west_rounded, size: 17),
                onTap: () => onSelected(suggestion.query),
              );
            },
          ),
        ),
      ],
    );
  }

  static IconData _iconFor(CatalogSearchSuggestionKind kind) => switch (kind) {
    CatalogSearchSuggestionKind.brand => Icons.sell_outlined,
    CatalogSearchSuggestionKind.category => Icons.category_outlined,
    CatalogSearchSuggestionKind.characteristic => Icons.tune_rounded,
    CatalogSearchSuggestionKind.composite => Icons.search_rounded,
  };

  static String _kindLabel(CatalogSearchSuggestionKind kind) => switch (kind) {
    CatalogSearchSuggestionKind.brand => 'Бренд',
    CatalogSearchSuggestionKind.category => 'Категория',
    CatalogSearchSuggestionKind.characteristic => 'Характеристика',
    CatalogSearchSuggestionKind.composite => 'Подборка',
  };
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action, this.onTap});

  final String title;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 32,
    child: Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF77777E),
          ),
        ),
        const Spacer(),
        if (action != null)
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(action!),
          ),
      ],
    ),
  );
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: const Color(0xFFB5B5BA)),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13.5,
              color: Color(0xFF77777E),
              height: 1.3,
            ),
          ),
        ],
      ),
    ),
  );
}
