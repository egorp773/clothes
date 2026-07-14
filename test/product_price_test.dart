import 'package:clothes/models/created_outfit.dart';
import 'package:clothes/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes broken product ruble sign from local storage', () {
    final product = Product.fromJson({
      'id': '1',
      'title': 'Item',
      'detailTitle': 'Item',
      'description': '',
      'price': '12 300 ?',
      'detailPrice': '12300',
      'priceValue': 12300,
      'image': 'image.png',
      'category': 'Другое',
      'brand': '',
      'size': 'One Size',
      'color': '',
      'condition': 'Хорошее',
      'dotsOnDark': false,
    });

    expect(product.price, '12 300 \u20BD');
  });

  test('normalizes broken outfit item ruble sign from local storage', () {
    final item = OutfitItem.fromJson({
      'id': '1',
      'name': 'Item',
      'price': '8 400 ?',
      'image': 'image.png',
    });

    expect(item.price, '8 400 \u20BD');
  });

  test('reads enriched product fields without exposing ML metadata', () {
    final product = Product.fromSupabase({
      'id': 'new-product',
      'title': 'Рубашка',
      'price': 3500,
      'brand': 'Saint Laurent',
      'normalized_brand': 'saint_laurent',
      'normalized_category': 'shirt',
      'audience': 'unisex',
      'has_defects': true,
      'defects_description': 'След у нижней пуговицы',
      'product_attributes': [
        {'attribute_key': 'material', 'value': 'cotton'},
        {'attribute_key': 'collar', 'value': 'shirt'},
      ],
    });

    expect(product.category, 'Рубашка');
    expect(product.brand, 'Saint Laurent');
    expect(product.normalizedBrand, 'saint_laurent');
    expect(product.audience, 'unisex');
    expect(product.categoryAttributes['material'], 'cotton');
    expect(product.defectsDescription, 'След у нижней пуговицы');
  });

  test('keeps legacy product category readable', () {
    final product = Product.fromSupabase({
      'id': 'legacy-product',
      'title': 'Футболка',
      'price': 1200,
      'category': 'clothing',
      'item_type': 'tshirt',
      'brand': 'no_brand',
      'material': 'cotton',
    });

    expect(product.normalizedCategory, 't_shirt');
    expect(product.category, 'Футболка');
    expect(product.material, 'cotton');
  });
}
