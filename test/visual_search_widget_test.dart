import 'dart:convert';
import 'dart:typed_data';

import 'package:clothes/features/visual_search/visual_search_camera_screen.dart';
import 'package:clothes/features/visual_search/visual_search_object_selection_screen.dart';
import 'package:clothes/features/visual_search/visual_search_screen.dart';
import 'package:clothes/features/visual_search/visual_search_service.dart';
import 'package:clothes/models/product.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:image/image.dart' as image_lib;
import 'package:photo_manager/photo_manager.dart';

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

  test('resolves only known IDs to complete current catalog products', () {
    final catalogProduct = _catalogProduct(
      id: 'known-product',
      title: 'Полная карточка',
      image: 'assets/products/catalog-photo.png',
      sellerName: 'Продавец из каталога',
    );
    final sparseKnown = Product.fromSupabase({
      'product_id': 'known-product',
      'id': 'known-product',
      'title': 'Неполный ответ API',
      'price': 1,
      'matched_image_url': 'https://example.test/wrong-match.jpg',
    });
    final sparseUnknown = Product.fromSupabase({
      'product_id': 'unknown-product',
      'id': 'unknown-product',
      'title': 'Неизвестный товар',
      'price': 1,
      'matched_image_url': 'https://example.test/unknown.jpg',
    });

    final resolved = resolveVisualSearchCatalogProducts(
      searchProducts: [sparseUnknown, sparseKnown, sparseKnown],
      catalogProducts: [catalogProduct],
    );

    expect(resolved, hasLength(1));
    expect(resolved.single, same(catalogProduct));
    expect(resolved.single.image, 'assets/products/catalog-photo.png');
    expect(resolved.single.sellerName, 'Продавец из каталога');
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
          onProductMenu: (_) {},
          onShareProduct: (_) {},
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
          catalogProducts: [
            _catalogProduct(id: 'product', title: 'Тестовое худи'),
          ],
          onProductTap: (_) {},
          onToggleLike: (_) async {},
          onProductMenu: (_) {},
          onShareProduct: (_) {},
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
          service: _FakeVisualSearchService(includeUnknown: true),
          catalogProducts: [catalogProduct],
          onProductTap: (product) => openedProduct = product,
          onToggleLike: (_) async {},
          onProductMenu: (_) {},
          onShareProduct: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Complete catalog product'), findsOneWidget);
    expect(find.text('Неизвестный результат API'), findsNothing);
    expect(find.text('1 похожий товар'), findsOneWidget);

    await tester.tap(find.text('Complete catalog product'));
    expect(openedProduct, same(catalogProduct));
    expect(openedProduct?.sellerName, 'Catalog seller');
    expect(openedProduct?.ownerId, 'seller-42');
    expect(openedProduct?.image, 'assets/products/try_photo.png');
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
          onProductMenu: (_) {},
          onShareProduct: (_) {},
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
          catalogProducts: [
            _catalogProduct(id: 'similar-product', title: 'Тестовое худи'),
          ],
          onProductTap: (_) {},
          onToggleLike: (_) async {},
          onProductMenu: (_) {},
          onShareProduct: (_) {},
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

  testWidgets('camera and gallery permission denial open app settings', (
    tester,
  ) async {
    var settingsCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: VisualSearchCameraScreen(
          service: _FakeVisualSearchService(),
          cameraLoader: () async =>
              throw CameraException('CameraAccessDenied', 'Denied'),
          photoPermissionRequester: () async => PermissionState.denied,
          galleryLoader: () async => const <AssetEntity>[],
          openSettings: () async {
            settingsCalls += 1;
            return true;
          },
          onProductTap: (_) {},
          onToggleLike: (_) async {},
          onProductMenu: (_) {},
          onShareProduct: (_) {},
        ),
      ),
    );
    await _pumpCameraWork(tester);

    expect(find.text('Нет доступа к камере'), findsOneWidget);
    expect(find.text('Нет доступа к фото'), findsOneWidget);

    await tester.tap(find.byKey(const Key('visual-search-camera-settings')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('visual-search-gallery-settings')));
    await tester.pump();

    expect(settingsCalls, 2);
  });

  testWidgets('gallery load error can be retried into an empty state', (
    tester,
  ) async {
    var galleryCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: VisualSearchCameraScreen(
          initializeHardware: false,
          cameraPreviewOverride: const ColoredBox(color: Colors.black),
          service: _FakeVisualSearchService(),
          photoPermissionRequester: () async => PermissionState.authorized,
          galleryLoader: () async {
            galleryCalls += 1;
            if (galleryCalls == 1) throw StateError('Gallery unavailable');
            return const <AssetEntity>[];
          },
          onProductTap: (_) {},
          onToggleLike: (_) async {},
          onProductMenu: (_) {},
          onShareProduct: (_) {},
        ),
      ),
    );
    await _pumpCameraWork(tester);

    expect(find.text('Не удалось загрузить фотографии'), findsOneWidget);
    expect(galleryCalls, 1);

    await tester.tap(find.byKey(const Key('visual-search-gallery-retry')));
    await _pumpCameraWork(tester);

    expect(find.text('Нет фотографий'), findsOneWidget);
    expect(find.text('Не удалось загрузить фотографии'), findsNothing);
    expect(galleryCalls, 2);
  });

  testWidgets('camera capture opens manual object selection', (tester) async {
    var captureCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: VisualSearchCameraScreen(
          initializeHardware: false,
          cameraPreviewOverride: const ColoredBox(color: Colors.black),
          captureImage: () async {
            captureCalls += 1;
            return _visualSearchImage();
          },
          imageNormalizer: (image) async => image,
          service: _FakeVisualSearchService(),
          onProductTap: (_) {},
          onToggleLike: (_) async {},
          onProductMenu: (_) {},
          onShareProduct: (_) {},
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Сделать фото'));
    await _pumpCameraWork(tester, transition: true);

    expect(captureCalls, 1);
    expect(find.byType(VisualSearchObjectSelectionScreen), findsOneWidget);
    expect(find.text('Что ищем?'), findsOneWidget);
  });

  testWidgets('gallery thumbnail opens manual object selection', (
    tester,
  ) async {
    final asset = AssetEntity(
      id: 'asset-1',
      typeInt: AssetType.image.index,
      width: 1200,
      height: 1600,
      createDateSecond: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VisualSearchCameraScreen(
          initializeHardware: false,
          cameraPreviewOverride: const ColoredBox(color: Colors.black),
          service: _FakeVisualSearchService(),
          photoPermissionRequester: () async => PermissionState.authorized,
          galleryLoader: () async => <AssetEntity>[asset],
          thumbnailLoader: (_, _) async => _visualSearchPngBytes(),
          onProductTap: (_) {},
          onToggleLike: (_) async {},
          onProductMenu: (_) {},
          onShareProduct: (_) {},
        ),
      ),
    );
    await _pumpCameraWork(tester);

    await tester.tap(find.byKey(const Key('visual-search-asset-asset-1')));
    await _pumpCameraWork(tester, transition: true);

    expect(find.byType(VisualSearchObjectSelectionScreen), findsOneWidget);
    expect(find.text('Что ищем?'), findsOneWidget);
  });

  testWidgets('search error retries and renders the current catalog product', (
    tester,
  ) async {
    final service = _FakeVisualSearchService(failuresBeforeSuccess: 1);

    await tester.pumpWidget(
      MaterialApp(
        home: VisualSearchScreen(
          initialImage: _visualSearchImage(),
          service: service,
          catalogProducts: [
            _catalogProduct(id: 'product', title: 'Товар после повтора'),
          ],
          onProductTap: (_) {},
          onToggleLike: (_) async {},
          onProductMenu: (_) {},
          onShareProduct: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ошибка поиска'), findsOneWidget);
    expect(service.searchCalls, 1);

    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();

    expect(find.text('Товар после повтора'), findsOneWidget);
    expect(find.text('Ошибка поиска'), findsNothing);
    expect(service.searchCalls, 2);
  });

  testWidgets('result actions do not open detail until the card is tapped', (
    tester,
  ) async {
    final product = _catalogProduct(
      id: 'product',
      title: 'Карточка результата',
    );
    var detailCalls = 0;
    var menuCalls = 0;
    var shareCalls = 0;
    var likeCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: VisualSearchScreen(
          initialImage: _visualSearchImage(),
          service: _FakeVisualSearchService(),
          catalogProducts: [product],
          onProductTap: (_) => detailCalls += 1,
          onToggleLike: (_) async {
            likeCalls += 1;
            product.isLiked = !product.isLiked;
            product.likesCount += product.isLiked ? 1 : -1;
          },
          onProductMenu: (_) => menuCalls += 1,
          onShareProduct: (_) => shareCalls += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(const Key('visual-search-product-product'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    final rect = tester.getRect(card);

    await tester.tapAt(Offset(rect.right - 20, rect.top + 27));
    await tester.pump();
    expect(menuCalls, 1);
    expect(detailCalls, 0);

    await tester.tapAt(Offset(rect.right - 46, rect.bottom - 20));
    await tester.pump();
    expect(likeCalls, 1);
    expect(product.isLiked, isTrue);
    expect(product.likesCount, 1);
    expect(detailCalls, 0);

    await tester.tapAt(Offset(rect.right - 14, rect.bottom - 20));
    await tester.pump();
    expect(shareCalls, 1);
    expect(detailCalls, 0);

    await tester.tap(find.text('Карточка результата'));
    await tester.pump();
    expect(detailCalls, 1);
  });
}

Uint8List _visualSearchPngBytes() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

XFile _visualSearchImage() => XFile.fromData(
  _visualSearchPngBytes(),
  mimeType: 'image/png',
  name: 'query.png',
);

Future<void> _pumpCameraWork(
  WidgetTester tester, {
  bool transition = false,
}) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  if (transition) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

class _FakeVisualSearchService extends VisualSearchService {
  _FakeVisualSearchService({
    this.empty = false,
    this.similarOnly = false,
    this.includeUnknown = false,
    this.failuresBeforeSuccess = 0,
  }) : super(
         baseUrl: 'https://example.test',
         client: MockClient((_) async => throw UnimplementedError()),
         accessTokenProvider: () => 'token',
       );

  final bool empty;
  final bool similarOnly;
  final bool includeUnknown;
  final int failuresBeforeSuccess;
  int searchCalls = 0;

  @override
  Future<VisualSearchResult> search(
    XFile image, {
    VisualSearchFilters filters = const VisualSearchFilters(),
    Uint8List? imageBytes,
  }) async {
    searchCalls += 1;
    if (searchCalls <= failuresBeforeSuccess) {
      throw const VisualSearchException('Ошибка поиска');
    }
    return VisualSearchResult(
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
              if (includeUnknown)
                Product.fromSupabase({
                  'id': 'unknown-product',
                  'title': 'Неизвестный результат API',
                  'price': 10,
                  'main_image': 'https://example.test/wrong-match.jpg',
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
  }

  @override
  void close() {}
}

Product _catalogProduct({
  required String id,
  required String title,
  String image = 'assets/products/try_photo.png',
  String sellerName = 'Каталожный продавец',
}) => Product.fromSupabase({
  'id': id,
  'title': title,
  'description': 'Полное описание товара',
  'price': 3500,
  'main_image': image,
  'images': <String>[image],
  'category': 'clothing',
  'seller_id': 'seller-$id',
  'seller_name': sellerName,
  'seller_handle': '@catalog_seller',
  'location': 'Москва',
});
