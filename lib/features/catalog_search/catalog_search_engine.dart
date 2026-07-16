import '../../models/product.dart';
import '../listing_publish/data/listing_catalogs.dart';

enum CatalogSearchSuggestionKind {
  brand,
  category,
  characteristic,
  composite,
}

class CatalogSearchSuggestion {
  const CatalogSearchSuggestion({
    required this.label,
    required this.query,
    required this.kind,
  });

  final String label;
  final String query;
  final CatalogSearchSuggestionKind kind;
}

/// Precomputed marketplace-style product search.
///
/// The catalog is normalized once. A submitted query then compares a handful
/// of short token arrays per product. Exact brand/category/color matches are
/// deliberately stronger than title fuzziness and much stronger than a
/// description-only coincidence.
class CatalogSearchIndex {
  CatalogSearchIndex(Iterable<Product> products) {
    for (final product in products) {
      final entry = _ProductSearchEntry.fromProduct(product);
      _entries[product.id] = entry;
      for (final suggestion in entry.suggestions) {
        final key = normalize(suggestion.label);
        if (key.isEmpty) continue;
        final previous = _suggestions[key];
        if (previous == null) {
          _suggestions[key] = _SuggestionCandidate(suggestion);
        } else {
          previous.occurrences += 1;
          if (_suggestionWeight(suggestion.kind) >
              _suggestionWeight(previous.value.kind)) {
            previous.value = suggestion;
          }
        }
      }
    }
  }

  final Map<String, _ProductSearchEntry> _entries = {};
  final Map<String, _SuggestionCandidate> _suggestions = {};

  static String normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-z0-9\u0400-\u04ff]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool matches(Product product, String query) {
    final normalizedQuery = normalize(query);
    if (normalizedQuery.isEmpty) return true;
    return scoreNormalized(product, normalizedQuery) > 0;
  }

  int score(Product product, String query) {
    final normalizedQuery = normalize(query);
    if (normalizedQuery.isEmpty) return 0;
    return scoreNormalized(product, normalizedQuery);
  }

  int scoreNormalized(Product product, String normalizedQuery) {
    final entry =
        _entries[product.id] ?? _ProductSearchEntry.fromProduct(product);
    return entry.score(_PreparedQuery(normalizedQuery));
  }

  List<CatalogSearchSuggestion> suggestions(String query, {int limit = 8}) {
    final normalizedQuery = normalize(query);
    if (normalizedQuery.isEmpty || limit <= 0) return const [];
    final preparedQuery = _PreparedQuery(normalizedQuery);
    final ranked = <({CatalogSearchSuggestion value, int score})>[];

    for (final candidate in _suggestions.values) {
      final score = _suggestionScore(candidate.value.label, preparedQuery);
      if (score == 0) continue;
      ranked.add((
        value: candidate.value,
        score:
            score +
            _suggestionWeight(candidate.value.kind) +
            candidate.occurrences.clamp(0, 20).toInt(),
      ));
    }
    ranked.sort((a, b) {
      final scoreOrder = b.score.compareTo(a.score);
      if (scoreOrder != 0) return scoreOrder;
      final lengthOrder = a.value.label.length.compareTo(b.value.label.length);
      if (lengthOrder != 0) return lengthOrder;
      return a.value.label.compareTo(b.value.label);
    });
    return ranked.take(limit).map((item) => item.value).toList();
  }

  static int _suggestionScore(String value, _PreparedQuery query) {
    final normalized = normalize(value);
    if (normalized == query.rawText) return 1400;
    if (normalized.startsWith(query.rawText)) return 1200;

    final field = _WeightedField(_FieldKind.structured, value);
    var score = 0;
    for (final token in query.tokens) {
      final match = field.match(token);
      if (match == null) return 0;
      score += match.quality.multiplier * 20;
    }
    if (field.canonicalText == query.canonicalText) score += 900;
    return score + 400;
  }

  static int _suggestionWeight(CatalogSearchSuggestionKind kind) =>
      switch (kind) {
        CatalogSearchSuggestionKind.brand => 50,
        CatalogSearchSuggestionKind.category => 45,
        CatalogSearchSuggestionKind.composite => 40,
        CatalogSearchSuggestionKind.characteristic => 25,
      };
}

class _ProductSearchEntry {
  _ProductSearchEntry({required this.fields, required this.suggestions});

  factory _ProductSearchEntry.fromProduct(Product product) {
    final normalizedCategory = product.normalizedCategory.isNotEmpty
        ? product.normalizedCategory
        : ListingCatalogs.normalizeCategory(
            product.itemType.isNotEmpty ? product.itemType : product.category,
          );
    final categoryName = ListingCatalogs.categoryName(
      normalizedCategory,
      fallback: product.category,
    );
    final categoryPath = ListingCatalogs.legacyPathFor(normalizedCategory);
    final subcategory = product.subcategory.isNotEmpty
        ? product.subcategory
        : categoryPath.subcategory;
    final subcategoryName = _subcategoryName(subcategory);
    final brandName = ListingCatalogs.brandName(
      product.normalizedBrand.isNotEmpty
          ? product.normalizedBrand
          : product.brand,
      fallback: product.brand,
    );
    final primaryColor = product.primaryColor.isNotEmpty
        ? product.primaryColor
        : product.color;
    final displayedPrimaryColor = ListingCatalogs.colorName(
      primaryColor,
      fallback: product.color,
    );
    final displayedSecondaryColors = <String>{
      for (final color in product.secondaryColors)
        ListingCatalogs.colorName(color, fallback: color),
    };

    final displayedSize = ListingCatalogs.sizeName(
      product.size,
      fallback: product.size,
    );
    final displayedCondition = ListingCatalogs.conditionName(
      product.condition,
      fallback: product.condition,
    );
    final structured = <String>{
      product.size,
      product.condition,
      product.material,
      product.pattern,
      product.season,
      product.style,
      product.fit,
      product.sleeveLength,
      product.closure,
      displayedSize,
      displayedCondition,
    };
    final suggestionCharacteristics = <String>{
      displayedSize,
      displayedCondition,
      displayedPrimaryColor,
      ...displayedSecondaryColors,
    };
    final attributeLabels = {
      for (final definition in ListingCatalogs.attributesFor(normalizedCategory))
        definition.id: definition.label,
    };
    for (final attribute in product.importantCharacteristics.entries) {
      final displayedValue = ListingCatalogs.attributeValueName(
        attribute.key,
        attribute.value,
        category: normalizedCategory,
        fallback: attribute.value,
      );
      structured
        ..add(attribute.key)
        ..add(attribute.value)
        ..add(displayedValue);
      suggestionCharacteristics.add(displayedValue);
      final label = attributeLabels[attribute.key];
      if (label != null) structured.add(label);
    }

    final colorValues = <String>{
      product.color,
      primaryColor,
      displayedPrimaryColor,
      ...product.secondaryColors,
      ...displayedSecondaryColors,
    };
    final compactBrand = CatalogSearchIndex.normalize(
      brandName,
    ).replaceAll(' ', '');
    final rawFields = <_WeightedField>[
      _WeightedField(_FieldKind.title, product.title),
      _WeightedField(_FieldKind.title, product.detailTitle),
      _WeightedField(_FieldKind.brand, brandName),
      _WeightedField(_FieldKind.brand, product.brand),
      _WeightedField(_FieldKind.brand, product.normalizedBrand),
      if (compactBrand.length >= 2)
        _WeightedField(_FieldKind.brand, compactBrand),
      _WeightedField(_FieldKind.category, categoryName),
      _WeightedField(_FieldKind.category, product.category),
      _WeightedField(_FieldKind.category, normalizedCategory),
      _WeightedField(_FieldKind.category, product.categoryId),
      _WeightedField(_FieldKind.category, product.itemType),
      _WeightedField(_FieldKind.category, subcategory),
      _WeightedField(_FieldKind.category, subcategoryName),
      for (final value in colorValues)
        _WeightedField(_FieldKind.color, value),
      for (final value in structured)
        _WeightedField(_FieldKind.structured, value),
      _WeightedField(_FieldKind.description, product.description),
    ];
    final fieldsByKindAndText = <String, _WeightedField>{};
    for (final field in rawFields) {
      if (field.text.isEmpty) continue;
      fieldsByKindAndText['${field.kind.index}:${field.text}'] = field;
    }

    final suggestions = <CatalogSearchSuggestion>[
      if (_isUsefulSuggestion(brandName))
        CatalogSearchSuggestion(
          label: brandName.trim(),
          query: brandName.trim(),
          kind: CatalogSearchSuggestionKind.brand,
        ),
      if (_isUsefulSuggestion(categoryName))
        CatalogSearchSuggestion(
          label: categoryName.trim(),
          query: categoryName.trim(),
          kind: CatalogSearchSuggestionKind.category,
        ),
      if (_isUsefulSuggestion(subcategoryName) &&
          CatalogSearchIndex.normalize(subcategoryName) !=
              CatalogSearchIndex.normalize(categoryName))
        CatalogSearchSuggestion(
          label: subcategoryName.trim(),
          query: subcategoryName.trim(),
          kind: CatalogSearchSuggestionKind.category,
        ),
      for (final value in suggestionCharacteristics)
        if (_isUsefulSuggestion(value))
          CatalogSearchSuggestion(
            label: value.trim(),
            query: value.trim(),
            kind: CatalogSearchSuggestionKind.characteristic,
          ),
      ..._compositeSuggestions(
        category: normalizedCategory,
        categoryName: categoryName,
        color: displayedPrimaryColor,
        brand: brandName,
      ),
    ];

    return _ProductSearchEntry(
      fields: fieldsByKindAndText.values.toList(),
      suggestions: suggestions,
    );
  }

  final List<_WeightedField> fields;
  final List<CatalogSearchSuggestion> suggestions;

  int score(_PreparedQuery query) {
    if (query.tokens.isEmpty) return 0;
    var tokenScore = 0;
    var matchedTokens = 0;
    var primaryMatchedTokens = 0;
    final matchedPrimaryKinds = <_FieldKind>{};

    for (final token in query.tokens) {
      _TokenMatch? best;
      for (final field in fields) {
        final match = field.match(token);
        if (match != null &&
            (best == null || match.contribution > best.contribution)) {
          best = match;
        }
      }
      if (best == null) continue;
      matchedTokens += 1;
      tokenScore += best.contribution;
      if (best.field.kind != _FieldKind.description) {
        primaryMatchedTokens += 1;
        matchedPrimaryKinds.add(best.field.kind);
      }
    }
    if (matchedTokens == 0) return 0;

    final totalTokens = query.tokens.length;
    final denominator = totalTokens * totalTokens;
    var score = tokenScore;
    score += matchedTokens * matchedTokens * 1200 ~/ denominator;
    score +=
        primaryMatchedTokens * primaryMatchedTokens * 2600 ~/ denominator;
    score += matchedPrimaryKinds.length * 220;

    if (matchedTokens == totalTokens) {
      score += primaryMatchedTokens == totalTokens ? 3400 : 700;
    }

    var bestPhraseScore = 0;
    var bestFieldCoverageScore = 0;
    for (final field in fields) {
      final phraseScore = field.phraseScore(query);
      if (phraseScore > bestPhraseScore) bestPhraseScore = phraseScore;
      if (field.kind == _FieldKind.description) continue;
      var fieldCoverage = 0;
      for (final token in query.tokens) {
        if (field.match(token) != null) fieldCoverage += 1;
      }
      final fieldCoverageScore =
          fieldCoverage * fieldCoverage * field.kind.weight * 2;
      if (fieldCoverageScore > bestFieldCoverageScore) {
        bestFieldCoverageScore = fieldCoverageScore;
      }
    }
    score += bestPhraseScore + bestFieldCoverageScore;
    return score.clamp(1, 1 << 30).toInt();
  }

  static bool _isUsefulSuggestion(String value) {
    final normalized = CatalogSearchIndex.normalize(value);
    return normalized.length >= 2 && normalized != 'не указано';
  }

  static List<CatalogSearchSuggestion> _compositeSuggestions({
    required String category,
    required String categoryName,
    required String color,
    required String brand,
  }) {
    if (!_isUsefulSuggestion(categoryName)) return const [];
    final values = <String>{};
    final colorCategory = _colorCategoryQuery(color, categoryName, category);
    if (_isUsefulSuggestion(colorCategory)) values.add(colorCategory);
    if (_isUsefulSuggestion(brand)) {
      values.add('${brand.trim()} ${categoryName.trim().toLowerCase()}');
      if (_isUsefulSuggestion(colorCategory)) {
        values.add('$colorCategory ${brand.trim()}');
      }
    }
    return [
      for (final value in values)
        CatalogSearchSuggestion(
          label: value,
          query: value,
          kind: CatalogSearchSuggestionKind.composite,
        ),
    ];
  }

  static String _colorCategoryQuery(
    String color,
    String categoryName,
    String category,
  ) {
    if (!_isUsefulSuggestion(color)) return '';
    final form = _adjectiveForm(color, _grammarForCategory(category));
    final label = categoryName.trim().toLowerCase();
    return '${_capitalize(form)} $label';
  }

  static String _adjectiveForm(String value, _RussianGrammar grammar) {
    final word = value.trim().toLowerCase();
    if (grammar == _RussianGrammar.masculine) return word;
    String root;
    if (word.endsWith('ый') || word.endsWith('ой')) {
      root = word.substring(0, word.length - 2);
      return switch (grammar) {
        _RussianGrammar.feminine => '${root}ая',
        _RussianGrammar.neuter => '${root}ое',
        _RussianGrammar.plural => '${root}ые',
        _ => word,
      };
    }
    if (word.endsWith('ий')) {
      root = word.substring(0, word.length - 2);
      return switch (grammar) {
        _RussianGrammar.feminine => '${root}яя',
        _RussianGrammar.neuter => '${root}ее',
        _RussianGrammar.plural => '${root}ие',
        _ => word,
      };
    }
    return word;
  }

  static _RussianGrammar _grammarForCategory(String category) {
    if (_feminineCategories.contains(category)) return _RussianGrammar.feminine;
    if (_neuterCategories.contains(category)) return _RussianGrammar.neuter;
    if (_pluralCategories.contains(category)) return _RussianGrammar.plural;
    return _RussianGrammar.masculine;
  }

  static const _feminineCategories = {
    't_shirt',
    'tank_top',
    'shirt',
    'blouse',
    'sweatshirt',
    'turtleneck',
    'skirt',
    'jacket',
    'bag',
    'beanie',
    'cap',
    'brooch',
  };
  static const _neuterCategories = {
    'hoodie',
    'polo',
    'dress',
    'coat',
    'underwear',
  };
  static const _pluralCategories = {
    'jeans',
    'trousers',
    'joggers',
    'leggings',
    'shorts',
    'socks',
    'tights',
    'sneakers',
    'boots',
    'heels',
    'loafers',
    'sandals',
    'slippers',
    'gloves',
    'eyewear',
    'earrings',
  };

  static String _capitalize(String value) => value.isEmpty
      ? value
      : '${value.substring(0, 1).toUpperCase()}${value.substring(1)}';

  static String _subcategoryName(String value) =>
      switch (CatalogSearchIndex.normalize(value)) {
        'tops' => 'Топы и верх',
        'bottoms' => 'Низ',
        'outerwear' => 'Верхняя одежда',
        'one piece' => 'Платья и комбинезоны',
        'shoes all' => 'Обувь',
        'bags' => 'Сумки и рюкзаки',
        'headwear' => 'Головные уборы',
        'accessories all' => 'Аксессуары',
        'jewelry' => 'Украшения',
        _ => value.trim(),
      };
}

enum _RussianGrammar { masculine, feminine, neuter, plural }

enum _FieldKind { title, brand, category, color, structured, description }

extension on _FieldKind {
  int get weight => switch (this) {
    _FieldKind.title => 135,
    _FieldKind.brand => 170,
    _FieldKind.category => 155,
    _FieldKind.color => 145,
    _FieldKind.structured => 110,
    _FieldKind.description => 10,
  };

  int get rawExactBonus => switch (this) {
    _FieldKind.brand => 900,
    _FieldKind.category => 800,
    _FieldKind.color => 700,
    _FieldKind.title => 400,
    _FieldKind.structured => 350,
    _FieldKind.description => 0,
  };

  int get canonicalExactBonus => rawExactBonus ~/ 2;
}

class _WeightedField {
  _WeightedField(this.kind, String source)
    : text = CatalogSearchIndex.normalize(source),
      rawTokens = CatalogSearchIndex.normalize(source).split(' '),
      canonicalTokens = CatalogSearchIndex.normalize(
        source,
      ).split(' ').map(_SearchLexicon.canonicalToken).toList();

  final _FieldKind kind;
  final String text;
  final List<String> rawTokens;
  final List<String> canonicalTokens;

  String get canonicalText => canonicalTokens.join(' ');

  _TokenMatch? match(_QueryToken query) {
    _MatchQuality? bestQuality;
    for (var index = 0; index < rawTokens.length; index += 1) {
      final raw = rawTokens[index];
      if (raw.isEmpty) continue;
      final canonical = canonicalTokens[index];
      final quality = _matchQuality(query, raw, canonical);
      if (quality != null &&
          (bestQuality == null ||
              quality.multiplier > bestQuality.multiplier)) {
        bestQuality = quality;
      }
    }
    return bestQuality == null ? null : _TokenMatch(this, bestQuality);
  }

  int phraseScore(_PreparedQuery query) {
    if (text == query.rawText) {
      return kind.weight * 8 + kind.rawExactBonus;
    }
    if (text.startsWith(query.rawText)) return kind.weight * 5;
    if (canonicalText == query.canonicalText) {
      return kind.weight * 6 + kind.canonicalExactBonus;
    }
    if (_containsWordPhrase(text, query.rawText)) return kind.weight * 3;
    return 0;
  }

  static _MatchQuality? _matchQuality(
    _QueryToken query,
    String raw,
    String canonical,
  ) {
    if (raw == query.raw) return _MatchQuality.rawExact;
    if (canonical == query.canonical) return _MatchQuality.canonicalExact;
    if (query.canonical.length >= 2 &&
        canonical.startsWith(query.canonical)) {
      return _MatchQuality.prefix;
    }
    if (query.canonical.length >= 4 &&
        canonical.length >= 4 &&
        _isDamerauLevenshteinDistanceOne(query.canonical, canonical)) {
      return _MatchQuality.fuzzy;
    }
    return null;
  }

  static bool _containsWordPhrase(String text, String query) =>
      text.startsWith('$query ') ||
      text.endsWith(' $query') ||
      text.contains(' $query ');
}

enum _MatchQuality { fuzzy, prefix, canonicalExact, rawExact }

extension on _MatchQuality {
  int get multiplier => switch (this) {
    _MatchQuality.fuzzy => 3,
    _MatchQuality.prefix => 6,
    _MatchQuality.canonicalExact => 8,
    _MatchQuality.rawExact => 10,
  };
}

class _TokenMatch {
  const _TokenMatch(this.field, this.quality);

  final _WeightedField field;
  final _MatchQuality quality;

  int get contribution {
    final exactBonus = switch (quality) {
      _MatchQuality.rawExact => field.kind.rawExactBonus,
      _MatchQuality.canonicalExact => field.kind.canonicalExactBonus,
      _ => 0,
    };
    return field.kind.weight * quality.multiplier + exactBonus;
  }
}

class _PreparedQuery {
  _PreparedQuery(this.rawText)
    : tokens = rawText
          .split(' ')
          .where((token) => token.isNotEmpty)
          .map(_QueryToken.new)
          .toList();

  final String rawText;
  final List<_QueryToken> tokens;

  String get canonicalText => tokens.map((token) => token.canonical).join(' ');
}

class _QueryToken {
  _QueryToken(this.raw) : canonical = _SearchLexicon.canonicalToken(raw);

  final String raw;
  final String canonical;
}

abstract final class _SearchLexicon {
  static final RegExp _cyrillic = RegExp(r'[\u0400-\u04ff]');

  static const _aliases = <String, String>{
    'кед': 'кроссовки',
    'кеды': 'кроссовки',
    'кедах': 'кроссовки',
    'кедами': 'кроссовки',
    'сникер': 'кроссовки',
    'сникеры': 'кроссовки',
    'кроссовок': 'кроссовки',
    'джемпер': 'свитер',
    'джемперы': 'свитер',
    'пуловер': 'свитер',
    'пуловеры': 'свитер',
    'штаны': 'брюки',
    'штанов': 'брюки',
    'сумочка': 'сумка',
    'сумочки': 'сумка',
    'футболок': 'футболка',
    'найк': 'nike',
    'найки': 'nike',
    'адидас': 'adidas',
    'адидасы': 'adidas',
    'пума': 'puma',
    'рибок': 'reebok',
    'рибоки': 'reebok',
    'зара': 'zara',
    'юникло': 'uniqlo',
    'манго': 'mango',
    'лакост': 'lacoste',
    'левис': 'levis',
    'levi': 'levis',
    'нью': 'new',
    'баланс': 'balance',
  };

  static const _indeclinable = {
    'худи',
    'пальто',
    'поло',
    'кимоно',
    'пончо',
    'боди',
  };

  static const _suffixes = [
    'иями',
    'ями',
    'ами',
    'ого',
    'его',
    'ому',
    'ему',
    'ыми',
    'ими',
    'ую',
    'юю',
    'ая',
    'яя',
    'ое',
    'ее',
    'ые',
    'ие',
    'ий',
    'ый',
    'ой',
    'ам',
    'ям',
    'ах',
    'ях',
    'ов',
    'ев',
    'ом',
    'ем',
    'а',
    'я',
    'ы',
    'и',
    'у',
    'ю',
    'е',
  ];

  static String canonicalToken(String token) {
    final alias = _aliases[token] ?? token;
    if (!_cyrillic.hasMatch(alias) || _indeclinable.contains(alias)) {
      return alias;
    }
    for (final suffix in _suffixes) {
      if (alias.endsWith(suffix) && alias.length - suffix.length >= 3) {
        return alias.substring(0, alias.length - suffix.length);
      }
    }
    return alias;
  }
}

/// Strict, allocation-free Damerau-Levenshtein check with max distance 1.
/// It handles one substitution, insertion/deletion, or adjacent transposition.
bool _isDamerauLevenshteinDistanceOne(String first, String second) {
  if (first == second) return false;
  final difference = first.length - second.length;
  if (difference.abs() > 1) return false;

  if (difference == 0) {
    final mismatches = <int>[];
    for (var index = 0; index < first.length; index += 1) {
      if (first.codeUnitAt(index) != second.codeUnitAt(index)) {
        mismatches.add(index);
        if (mismatches.length > 2) return false;
      }
    }
    if (mismatches.length == 1) return true;
    if (mismatches.length != 2 || mismatches[1] != mismatches[0] + 1) {
      return false;
    }
    final left = mismatches[0];
    final right = mismatches[1];
    return first.codeUnitAt(left) == second.codeUnitAt(right) &&
        first.codeUnitAt(right) == second.codeUnitAt(left);
  }

  final longer = difference > 0 ? first : second;
  final shorter = difference > 0 ? second : first;
  var longIndex = 0;
  var shortIndex = 0;
  var skipped = false;
  while (longIndex < longer.length && shortIndex < shorter.length) {
    if (longer.codeUnitAt(longIndex) == shorter.codeUnitAt(shortIndex)) {
      longIndex += 1;
      shortIndex += 1;
      continue;
    }
    if (skipped) return false;
    skipped = true;
    longIndex += 1;
  }
  return true;
}

class _SuggestionCandidate {
  _SuggestionCandidate(this.value);

  CatalogSearchSuggestion value;
  int occurrences = 1;
}
