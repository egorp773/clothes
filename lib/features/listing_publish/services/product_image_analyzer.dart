class AnalyzedField<T> {
  const AnalyzedField({
    required this.value,
    required this.confidence,
    required this.source,
  }) : assert(confidence >= 0 && confidence <= 1);

  final T? value;
  final double confidence;
  final String source;

  bool get hasValue => value != null;
  bool get needsReview => hasValue && confidence < 0.65;

  Map<String, dynamic> toJson() => {
    'value': value,
    'confidence': confidence,
    'source': source,
  };

  factory AnalyzedField.fromJson(
    Map<String, dynamic> json,
    T? Function(Object? value) decodeValue,
  ) => AnalyzedField<T>(
    value: decodeValue(json['value']),
    confidence: ((json['confidence'] as num?)?.toDouble() ?? 0).clamp(0, 1),
    source: json['source'] as String? ?? 'unknown',
  );
}

const _emptyField = AnalyzedField<String>(
  value: null,
  confidence: 0,
  source: 'not_detected',
);

class ProductAnalysisResult {
  const ProductAnalysisResult({
    required this.section,
    required this.category,
    required this.subcategory,
    required this.itemType,
    required this.gender,
    required this.primaryColor,
    required this.secondaryColors,
    required this.brand,
    required this.material,
    required this.pattern,
    required this.season,
    required this.style,
    required this.suggestedTitle,
    required this.suggestedDescription,
    this.analysisId,
    this.enrichmentStatus = 'completed',
    this.fit = _emptyField,
    this.sleeveLength = _emptyField,
    this.closure = _emptyField,
    this.suggestedSize = _emptyField,
  });

  final AnalyzedField<String> section;
  final AnalyzedField<String> category;
  final AnalyzedField<String> subcategory;
  final AnalyzedField<String> itemType;
  final AnalyzedField<String> gender;
  final AnalyzedField<String> primaryColor;
  final List<AnalyzedField<String>> secondaryColors;
  final AnalyzedField<String> brand;
  final AnalyzedField<String> material;
  final AnalyzedField<String> pattern;
  final AnalyzedField<String> season;
  final AnalyzedField<String> style;
  final AnalyzedField<String> fit;
  final AnalyzedField<String> sleeveLength;
  final AnalyzedField<String> closure;
  final AnalyzedField<String> suggestedTitle;
  final AnalyzedField<String> suggestedDescription;
  final String? analysisId;
  final String enrichmentStatus;
  final AnalyzedField<String> suggestedSize;

  Map<String, AnalyzedField<String>> get scalarFields => {
    'section': section,
    'category': category,
    'subcategory': subcategory,
    'item_type': itemType,
    'gender': gender,
    'primary_color': primaryColor,
    'brand': brand,
    'material': material,
    'pattern': pattern,
    'season': season,
    'style': style,
    'fit': fit,
    'sleeve_length': sleeveLength,
    'closure': closure,
  };

  Map<String, dynamic> toJson() => {
    ...scalarFields.map((key, value) => MapEntry(key, value.toJson())),
    'secondary_colors': secondaryColors
        .map((field) => field.toJson())
        .toList(growable: false),
    'suggested_title': suggestedTitle.toJson(),
    'suggested_description': suggestedDescription.toJson(),
    'suggested_size': suggestedSize.toJson(),
  };

  factory ProductAnalysisResult.fromJson(Map<String, dynamic> json) {
    AnalyzedField<String> field(String name) {
      final value = json[name];
      if (value is! Map) return _emptyField;
      return AnalyzedField<String>.fromJson(
        Map<String, dynamic>.from(value),
        (raw) => raw is String ? raw : null,
      );
    }

    final secondary = json['secondary_colors'];
    return ProductAnalysisResult(
      section: field('section'),
      category: field('category'),
      subcategory: field('subcategory'),
      itemType: field('item_type'),
      gender: field('gender'),
      primaryColor: field('primary_color'),
      secondaryColors: secondary is List
          ? secondary
                .whereType<Map>()
                .map(
                  (value) => AnalyzedField<String>.fromJson(
                    Map<String, dynamic>.from(value),
                    (raw) => raw is String ? raw : null,
                  ),
                )
                .toList(growable: false)
          : const [],
      brand: field('brand'),
      material: field('material'),
      pattern: field('pattern'),
      season: field('season'),
      style: field('style'),
      fit: field('fit'),
      sleeveLength: field('sleeve_length'),
      closure: field('closure'),
      suggestedTitle: field('suggested_title'),
      suggestedDescription: field('suggested_description'),
      analysisId: json['analysis_id'] as String?,
      enrichmentStatus: json['enrichment_status'] as String? ?? 'completed',
      suggestedSize: field('suggested_size'),
    );
  }
}

abstract class ProductImageAnalyzer {
  Future<ProductAnalysisResult> analyze({
    required List<String> imageUrls,
    String? listingId,
  });

  Future<ProductAnalysisResult?> getAnalysis(String analysisId) async => null;
}

class ProductImageAnalysisException implements Exception {
  const ProductImageAnalysisException(this.message);

  final String message;

  @override
  String toString() => 'ProductImageAnalysisException: $message';
}
