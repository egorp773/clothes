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
}
