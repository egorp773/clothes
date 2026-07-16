import 'dart:convert';
import 'dart:typed_data';

import 'package:clothes/features/visual_search/visual_search_camera_screen.dart';
import 'package:clothes/features/visual_search/visual_search_object_selection_screen.dart';
import 'package:clothes/features/visual_search/visual_search_screen.dart';
import 'package:clothes/features/visual_search/visual_search_service.dart';
import 'package:clothes/models/product.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:image/image.dart' as image_lib;
import 'package:image_picker/image_picker.dart';

void main() {
  test('selected object is cropped before visual search', () async {
    final source = image_lib.Image(width: 100, height: 80);
    final file = XFile.fromData(
      Uint8List.fromList(image_lib.encodeJpg(source)),
      mimeType: 'image/jpeg',
      name: 'source.jpg',
    );

    final cropped = await cropVisualSearchImage(
      file,
      const Rect.fromLTRB(0.25, 0.25, 0.75, 0.75),
    );
    final decoded = image_lib.decodeImage(await cropped.readAsBytes());

    expect(decoded, isNotNull);
    expect(decoded!.width, 50);
    expect(decoded.height, 40);
  });

  test('visual search input is normalized to the server image limit', () async {
    final source = image_lib.Image(width: 1600, height: 800);
    final file = XFile.fromData(
      Uint8List.fromList(image_lib.encodeJpg(source)),
      mimeType: 'image/jpeg',
      name: 'large.jpg',
    );

    final normalized = await normalizeVisualSearchImage(file);
    final decoded = image_lib.decodeImage(await normalized.readAsBytes());

    expect(decoded, isNotNull);
    expect(decoded!.width, 1024);
    expect(decoded.height, 512);
  });

  test('selection reads the full normalized image aspect ratio', () async {
    final source = image_lib.Image(width: 320, height: 640);
    final size = await visualSearchImageSize(
      Uint8List.fromList(image_lib.encodeJpg(source)),
    );

    expect(size, const Size(320, 640));
  });

  testWidgets('photo selection keeps the original design and is manual-only', (
    tester,
  ) async {
    final preview = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: VisualSearchObjectSelectionScreen(
          previewBytes: preview,
          imageSize: const Size(800, 1200),
        ),
      ),
    );

    expect(find.text('Что ищем?'), findsOneWidget);
    expect(find.text('Проведите по вещи, чтобы выделить её'), findsOneWidget);
    expect(find.text('Найти похожее'), findsOneWidget);
    expect(find.text('Искать по всему фото'), findsNothing);
    expect(find.text('Выбрать вручную'), findsNothing);
    expect(find.text('Автовыбор'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);

    var findButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Найти похожее'),
    );
    expect(findButton.onPressed, isNull);

    await tester.dragFrom(const Offset(300, 100), const Offset(180, 220));
    await tester.pump();
    findButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Найти похожее'),
    );
    expect(findButton.onPressed, isNotNull);
  });

  testWidgets('camera-first search shows minimal controls and gallery panel', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VisualSearchCameraScreen(
          initializeHardware: false,
          cameraPreviewOverride: const ColoredBox(color: Colors.black),
          service: _FakeVisualSearchService(),
          onProductTap: (_) {},
          onToggleLike: (_) async {},
        ),
      ),
    );

    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    expect(find.byIcon(Icons.cameraswitch_rounded), findsOneWidget);
    expect(find.byIcon(Icons.flash_off_rounded), findsOneWidget);
    expect(find.text('Наведите на вещь'), findsNothing);
    expect(find.text('Галерея'), findsNothing);
    expect(find.text('Недавние'), findsOneWidget);
    expect(find.text('Найдём похожие товары'), findsOneWidget);
    expect(
      find.text('Сфотографируйте вещь, которую хотите найти'),
      findsOneWidget,
    );
    expect(find.text('Развернуть'), findsOneWidget);

    await tester.tap(find.text('Развернуть'));
    await tester.pumpAndSettle();
    expect(find.text('Свернуть'), findsOneWidget);
  });

  testWidgets('selected photo opens directly into visual search results', (
    tester,
  ) async {
    final image = XFile.fromData(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
      mimeType: 'image/png',
      name: 'query.png',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: VisualSearchScreen(
          initialImage: image,
          service: _FakeVisualSearchService(),
          onProductTap: (_) {},
          onToggleLike: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 похожий товар'), findsOneWidget);
    expect(find.text('Тестовое худи'), findsOneWidget);
    expect(find.text('Выбрать фото'), findsNothing);
  });

  testWidgets('search results reuse the complete catalog product by id', (
    tester,
  ) async {
    final image = XFile.fromData(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
      mimeType: 'image/png',
      name: 'query.png',
    );
    final catalogProduct = Product.fromSupabase({
      'id': 'product',
      'title': 'Complete catalog product',
      'description': 'Complete catalog description',
      'price': 4700,
      'main_image': 'assets/products/try_photo.png',
      'images': <String>['assets/products/try_photo.png'],
      'category': 'clothing',
      'seller_id': 'seller-42',
      'seller_name': 'Catalog seller',
      'seller_handle': '@catalog_seller',
      'location': 'Moscow',
    });
    Product? openedProduct;

    await tester.pumpWidget(
      MaterialApp(
        home: VisualSearchScreen(
          initialImage: image,
          service: _FakeVisualSearchService(),
          catalogProducts: [catalogProduct],
          onProductTap: (product) => openedProduct = product,
          onToggleLike: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Complete catalog product'), findsOneWidget);

    await tester.tap(find.text('Complete catalog product'));
    expect(openedProduct, same(catalogProduct));
    expect(openedProduct?.sellerName, 'Catalog seller');
    expect(openedProduct?.ownerId, 'seller-42');
  });

  testWidgets('shows empty state when relevance filtering returns no items', (
    tester,
  ) async {
    final image = XFile.fromData(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
      mimeType: 'image/png',
      name: 'query.png',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: VisualSearchScreen(
          initialImage: image,
          service: _FakeVisualSearchService(empty: true),
          onProductTap: (_) {},
          onToggleLike: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Похоже, такую вещь у нас ещё никто не выложил'),
      findsOneWidget,
    );
    expect(find.text('21 похожих товаров'), findsNothing);
  });

  testWidgets('shows a separate section for relevant but weak matches', (
    tester,
  ) async {
    final image = XFile.fromData(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
      mimeType: 'image/png',
      name: 'query.png',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: VisualSearchScreen(
          initialImage: image,
          service: _FakeVisualSearchService(similarOnly: true),
          onProductTap: (_) {},
          onToggleLike: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Похоже, такую вещь у нас ещё никто не выложил'),
      findsOneWidget,
    );
    expect(find.text('Смотрите похожее'), findsOneWidget);
    expect(find.text('Тестовое худи'), findsOneWidget);
  });
}

class _FakeVisualSearchService extends VisualSearchService {
  _FakeVisualSearchService({this.empty = false, this.similarOnly = false})
    : super(
        baseUrl: 'https://example.test',
        client: MockClient((_) async => throw UnimplementedError()),
        accessTokenProvider: () => 'token',
      );

  final bool empty;
  final bool similarOnly;

  @override
  Future<VisualSearchResult> search(
    XFile image, {
    VisualSearchFilters filters = const VisualSearchFilters(),
    Uint8List? imageBytes,
  }) async => VisualSearchResult(
    products: empty || similarOnly
        ? const []
        : [
            Product.fromSupabase({
              'id': 'product',
              'title': 'Тестовое худи',
              'price': 3500,
              'main_image': '',
              'images': <String>[],
              'category': 'clothing',
            }),
          ],
    similarProducts: similarOnly
        ? [
            Product.fromSupabase({
              'id': 'similar-product',
              'title': 'Тестовое худи',
              'price': 3500,
              'main_image': '',
              'images': <String>[],
              'category': 'clothing',
            }),
          ]
        : const [],
    matchStatus: similarOnly
        ? 'similar_only'
        : empty
        ? 'none'
        : 'strong',
    category: 'clothing',
    categoryConfidence: 0.8,
    timingsMs: const {'total': 700},
    candidateCount: 40,
    cached: false,
  );

  @override
  void close() {}
}
