import 'package:clothes/features/catalog_search/catalog_search_engine.dart';
import 'package:clothes/features/catalog_search/catalog_search_history.dart';
import 'package:clothes/features/catalog_search/catalog_search_sheet.dart';
import 'package:clothes/models/product.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('selecting a live suggestion returns and applies its query', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final product = Product(
      id: 'nike-hoodie',
      title: 'Nike Hoodie',
      detailTitle: 'Nike Hoodie',
      price: '1 000 ₽',
      detailPrice: '1000',
      priceValue: 1000,
      image: '',
      category: 'Худи',
      brand: 'Nike',
      size: 'M',
      color: 'Чёрный',
      condition: 'Новое',
      dotsOnDark: false,
      normalizedCategory: 'hoodie',
      normalizedBrand: 'nike',
    );
    String? selectedQuery;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  selectedQuery = await showModalBottomSheet<String>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => CatalogSearchSheet(
                      initialQuery: '',
                      index: CatalogSearchIndex([product]),
                      history: CatalogSearchHistory(),
                    ),
                  );
                },
                child: const Text('Открыть поиск'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть поиск'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('catalog-search-field')),
      'nik',
    );
    await tester.pump();

    expect(find.text('Nike'), findsOneWidget);
    expect(find.text('Nike Hoodie'), findsNothing);
    await tester.tap(find.text('Nike'));
    await tester.pumpAndSettle();

    expect(selectedQuery, 'Nike');
  });
}
