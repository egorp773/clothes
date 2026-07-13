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

  test('only a confident localized region is auto-cropped', () {
    expect(
      shouldAutoCropVisualSearchRegion(
        const VisualSearchRegion(
          id: 'jacket',
          confidence: 0.9,
          bounds: Rect.fromLTRB(0.2, 0.15, 0.75, 0.8),
        ),
      ),
      isTrue,
    );
    expect(
      shouldAutoCropVisualSearchRegion(
        const VisualSearchRegion(
          id: 'frame',
          confidence: 0.9,
          bounds: Rect.fromLTRB(0.02, 0.02, 0.98, 0.98),
        ),
      ),
      isFalse,
    );
    expect(
      shouldAutoCropVisualSearchRegion(
        const VisualSearchRegion(
          id: 'uncertain',
          confidence: 0.45,
          bounds: Rect.fromLTRB(0.2, 0.15, 0.75, 0.8),
        ),
      ),
      isFalse,
    );
    expect(
      shouldAutoCropVisualSearchRegion(
        const VisualSearchRegion(
          id: 'bottom-ui',
          confidence: 0.96,
          bounds: Rect.fromLTRB(0, 0.62, 1, 1),
        ),
      ),
      isFalse,
    );
    expect(
      shouldOfferVisualSearchSelection(const [
        VisualSearchRegion(
          id: 'bottom-ui',
          confidence: 0.96,
          bounds: Rect.fromLTRB(0, 0.62, 1, 1),
        ),
      ]),
      isTrue,
    );
  });

  testWidgets('multi-object photo offers boxes, chips, and manual selection', (
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
          regions: const [
            VisualSearchRegion(
              id: 'jacket',
              label: 'jacket',
              confidence: 0.9,
              bounds: Rect.fromLTRB(0.08, 0.1, 0.62, 0.56),
            ),
            VisualSearchRegion(
              id: 'unknown',
              confidence: 0.82,
              bounds: Rect.fromLTRB(0.55, 0.48, 0.92, 0.91),
            ),
          ],
        ),
      ),
    );

    expect(find.text('Что ищем?'), findsOneWidget);
    expect(find.text('Выберите вещь на фото'), findsOneWidget);
    expect(find.text('Куртка'), findsWidgets);
    expect(find.text('Предмет 2'), findsWidgets);
    expect(find.text('Искать по всему фото'), findsOneWidget);
    expect(find.text('Выбрать вручную'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Куртка'));
    await tester.pump();
    final findButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Найти похожее'),
    );
    expect(findButton.onPressed, isNotNull);

    await tester.tap(find.text('Выбрать вручную'));
    await tester.pump();
    expect(find.text('Проведите по вещи, чтобы выделить её'), findsOneWidget);
    expect(find.text('К найденным вещам'), findsOneWidget);
    final manualFindButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Найти похожее'),
    );
    expect(manualFindButton.onPressed, isNotNull);
  });

  testWidgets('tap chooses the most specific overlapping clothing region', (
    tester,
  ) async {
    final preview = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: VisualSearchObjectSelectionScreen(
          previewBytes: preview,
          imageSize: const Size(100, 100),
          regions: const [
            VisualSearchRegion(
              id: 'upper',
              label: 'upper_clothing',
              confidence: 0.88,
              bounds: Rect.fromLTRB(0.1, 0.1, 0.9, 0.45),
            ),
            VisualSearchRegion(
              id: 'full',
              label: 'full_clothing',
              confidence: 0.92,
              bounds: Rect.fromLTRB(0.1, 0.05, 0.9, 0.9),
            ),
          ],
        ),
      ),
    );

    await tester.tapAt(const Offset(400, 150));
    await tester.pump();

    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Верх'))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Одежда'))
          .selected,
      isFalse,
    );
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

    expect(find.text('Похожих товаров пока не найдено'), findsOneWidget);
    expect(find.text('21 похожих товаров'), findsNothing);
  });
}

class _FakeVisualSearchService extends VisualSearchService {
  _FakeVisualSearchService({this.empty = false})
    : super(
        baseUrl: 'https://example.test',
        client: MockClient((_) async => throw UnimplementedError()),
        accessTokenProvider: () => 'token',
      );

  final bool empty;

  @override
  Future<VisualSearchResult> search(
    XFile image, {
    VisualSearchFilters filters = const VisualSearchFilters(),
    Uint8List? imageBytes,
  }) async => VisualSearchResult(
    products: empty
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
    category: 'clothing',
    categoryConfidence: 0.8,
    timingsMs: const {'total': 700},
    candidateCount: 40,
    cached: false,
  );

  @override
  void close() {}
}
