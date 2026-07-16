import 'package:clothes/features/catalog_search/catalog_search_engine.dart';
import 'package:clothes/features/catalog_search/catalog_search_history.dart';
import 'package:clothes/models/product.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('normalizes case, yo and repeated separators consistently', () {
    expect(
      CatalogSearchIndex.normalize('  БЕЛЁСЫЙ,   ТРИКОТАЖ '),
      'белесый трикотаж',
    );
  });

  test('covers color, category and brand in a marketplace query', () {
    final fullyCovered = _product(
      id: 'covered',
      title: 'Базовая модель',
      brand: 'Nike',
      normalizedCategory: 't_shirt',
      primaryColor: 'white',
    );
    final descriptionOnly = _product(
      id: 'description',
      title: 'Другая вещь',
      description: 'Белая футболка Nike из новой коллекции',
      brand: 'Puma',
      normalizedCategory: 'hoodie',
      primaryColor: 'black',
    );
    final index = CatalogSearchIndex([fullyCovered, descriptionOnly]);

    expect(index.matches(fullyCovered, 'белая футболка nike'), isTrue);
    expect(
      index.score(fullyCovered, 'белая футболка nike'),
      greaterThan(index.score(descriptionOnly, 'белая футболка nike')),
    );
  });

  test('supports practical Russian word forms and category synonyms', () {
    final shirt = _product(
      id: 'shirt',
      title: 'Базовая модель',
      brand: 'Nike',
      normalizedCategory: 't_shirt',
      primaryColor: 'white',
    );
    final sneakers = _product(
      id: 'sneakers',
      title: 'Спортивная модель',
      normalizedCategory: 'sneakers',
    );
    final index = CatalogSearchIndex([shirt, sneakers]);

    expect(index.matches(shirt, 'белые футболки'), isTrue);
    expect(index.matches(shirt, 'найк'), isTrue);
    expect(index.matches(sneakers, 'кеды'), isTrue);
  });

  test('allows one typo for a token of at least four characters', () {
    final shirt = _product(
      id: 'shirt',
      title: 'Базовая модель',
      brand: 'Nike',
      normalizedCategory: 't_shirt',
    );
    final index = CatalogSearchIndex([shirt]);

    expect(index.matches(shirt, 'футблока'), isTrue);
    expect(index.matches(shirt, 'nkie'), isTrue);
    expect(index.matches(shirt, 'nke'), isFalse);
  });

  test('exact structured fields strongly outrank description matches', () {
    final exactBrand = _product(
      id: 'exact-brand',
      title: 'Базовая модель',
      brand: 'Nike',
    );
    final descriptionBrand = _product(
      id: 'description-brand',
      title: 'Другая модель',
      description: 'В описании случайно несколько раз упомянут Nike Nike Nike',
      brand: 'Puma',
    );
    final index = CatalogSearchIndex([exactBrand, descriptionBrand]);

    expect(
      index.score(exactBrand, 'nike'),
      greaterThan(index.score(descriptionBrand, 'nike')),
    );
  });

  test('full structured coverage cannot be beaten by noisy description', () {
    final structured = _product(
      id: 'structured',
      title: 'Базовая модель',
      brand: 'Nike',
      normalizedCategory: 't_shirt',
      primaryColor: 'white',
    );
    final noisyDescription = _product(
      id: 'noisy',
      title: 'Случайная вещь',
      description: List.filled(20, 'белая футболка nike').join(' '),
      brand: 'Adidas',
      normalizedCategory: 'jeans',
      primaryColor: 'blue',
    );
    final index = CatalogSearchIndex([structured, noisyDescription]);

    expect(
      index.score(structured, 'белая футболка nike'),
      greaterThan(index.score(noisyDescription, 'белая футболка nike')),
    );
  });

  test('suggestions contain taxonomy and composites, not listing titles', () {
    final shirt = _product(
      id: 'shirt',
      title: 'Редкий заголовок конкретного объявления',
      brand: 'Nike',
      normalizedCategory: 't_shirt',
      primaryColor: 'white',
    );
    final index = CatalogSearchIndex([shirt]);

    expect(index.matches(shirt, '   '), isTrue);
    final suggestions = index.suggestions('белая фут');
    expect(
      suggestions.any((suggestion) => suggestion.query == 'Белая футболка'),
      isTrue,
    );
    expect(
      index.suggestions('nik').any((suggestion) => suggestion.query == 'Nike'),
      isTrue,
    );
    expect(
      index.suggestions('редкий').any(
        (suggestion) =>
            suggestion.query == 'Редкий заголовок конкретного объявления',
      ),
      isFalse,
    );
  });

  test('recent queries are persisted, normalized and deduplicated', () async {
    SharedPreferences.setMockInitialValues({});
    final history = CatalogSearchHistory(maxEntries: 3);

    await history.add('  Белый   свитер ');
    await history.add('Кроссовки');
    await history.add('белый свитер');

    expect(await history.load(), ['белый свитер', 'Кроссовки']);
  });
}

Product _product({
  required String id,
  required String title,
  String description = '',
  String brand = '',
  String normalizedCategory = '',
  String primaryColor = '',
  String material = '',
  Map<String, String> categoryAttributes = const {},
}) => Product(
  id: id,
  title: title,
  detailTitle: title,
  description: description,
  price: '1 000 ₽',
  detailPrice: '1000',
  priceValue: 1000,
  image: '',
  category: '',
  brand: brand,
  size: '',
  color: '',
  condition: '',
  dotsOnDark: false,
  normalizedCategory: normalizedCategory,
  normalizedBrand: brand.toLowerCase(),
  primaryColor: primaryColor,
  material: material,
  categoryAttributes: categoryAttributes,
);
