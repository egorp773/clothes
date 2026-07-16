import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_search_engine.dart';

class CatalogSearchHistory {
  CatalogSearchHistory({this.maxEntries = 8});

  static const storageKey = 'catalog_recent_search_queries_v1';

  final int maxEntries;

  Future<List<String>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getStringList(storageKey) ?? const <String>[];
    final seen = <String>{};
    final result = <String>[];
    for (final value in stored) {
      final displayValue = _displayValue(value);
      final normalized = CatalogSearchIndex.normalize(displayValue);
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      result.add(displayValue);
      if (result.length >= maxEntries) break;
    }
    return result;
  }

  Future<List<String>> add(String query) async {
    final value = _displayValue(query);
    final normalized = CatalogSearchIndex.normalize(value);
    if (normalized.isEmpty) return load();

    final current = await load();
    final updated = <String>[
      value,
      ...current.where(
        (item) => CatalogSearchIndex.normalize(item) != normalized,
      ),
    ].take(maxEntries).toList();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(storageKey, updated);
    return updated;
  }

  Future<List<String>> remove(String query) async {
    final normalized = CatalogSearchIndex.normalize(query);
    final updated = (await load())
        .where((item) => CatalogSearchIndex.normalize(item) != normalized)
        .toList();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(storageKey, updated);
    return updated;
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(storageKey);
  }

  static String _displayValue(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');
}
