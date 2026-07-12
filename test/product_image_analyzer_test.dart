import 'package:clothes/features/listing_publish/services/product_image_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes the modular analyzer API response', () {
    final result = ProductAnalysisResult.fromJson({
      'category': {
        'value': 'clothing',
        'confidence': 0.91,
        'source': 'Marqo/marqo-fashionSigLIP',
      },
      'subcategory': {
        'value': 'tops',
        'confidence': 0.91,
        'source': 'Marqo/marqo-fashionSigLIP',
      },
      'item_type': {
        'value': 'hoodie',
        'confidence': 0.91,
        'source': 'Marqo/marqo-fashionSigLIP',
      },
      'primary_color': {
        'value': 'dark_blue',
        'confidence': 0.88,
        'source': 'opencv_masked_lab_hsv_v1',
      },
      'fit': {
        'value': 'oversized',
        'confidence': 0.68,
        'source': 'Qwen/Qwen3-VL-4B-Instruct',
      },
      'suggested_size': {
        'value': 'XL',
        'confidence': 0.82,
        'source': 'paddleocr',
      },
    });

    expect(result.category.value, 'clothing');
    expect(result.itemType.value, 'hoodie');
    expect(result.primaryColor.value, 'dark_blue');
    expect(result.fit.value, 'oversized');
    expect(result.suggestedSize.value, 'XL');
  });

  test('missing optional fields remain null and never invent values', () {
    final result = ProductAnalysisResult.fromJson(const {});

    expect(result.brand.value, isNull);
    expect(result.material.value, isNull);
    expect(result.closure.value, isNull);
    expect(result.brand.confidence, 0);
  });
}
