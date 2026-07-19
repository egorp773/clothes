import 'package:clothes/core/app_appearance.dart';
import 'package:clothes/models/created_outfit.dart';
import 'package:clothes/models/product.dart';
import 'package:clothes/screens/outfit_create_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const surfaceSize = Size(430, 900);

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets(
    'light workspace contrasts the white canvas without changing its data',
    (tester) async {
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      CreatedOutfit? publishedOutfit;

      await _pumpEditor(
        tester,
        brightness: Brightness.light,
        onPublish: (outfit) async => publishedOutfit = outfit,
      );

      final workspace = tester.widget<ColoredBox>(
        find.byKey(const Key('outfit-editor-workspace')),
      );
      final canvas = tester.widget<Container>(
        find.byKey(const Key('outfit-editor-canvas')),
      );
      final canvasDecoration = canvas.decoration! as BoxDecoration;
      final canvasForeground = canvas.foregroundDecoration! as BoxDecoration;

      expect(workspace.color, AppPalette.light.surfaceMuted);
      expect(canvasDecoration.color, Colors.white);
      expect(canvasForeground.border, isNotNull);

      await tester.tap(find.text('Далее'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ОПУБЛИКОВАТЬ ОБРАЗ'));
      await tester.pumpAndSettle();

      expect(publishedOutfit, isNotNull);
      expect(publishedOutfit!.previewBackgroundColor, Colors.white.toARGB32());
    },
  );

  testWidgets(
    'dark workspace keeps the dark backdrop while canvas stays white',
    (tester) async {
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpEditor(tester, brightness: Brightness.dark);

      final workspace = tester.widget<ColoredBox>(
        find.byKey(const Key('outfit-editor-workspace')),
      );
      final canvas = tester.widget<Container>(
        find.byKey(const Key('outfit-editor-canvas')),
      );
      final canvasDecoration = canvas.decoration! as BoxDecoration;

      expect(workspace.color, AppPalette.dark.page);
      expect(canvasDecoration.color, Colors.white);
    },
  );

  testWidgets(
    'dropping an item inside the trash removes it and gives haptics',
    (tester) async {
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      final hapticCalls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') hapticCalls.add(call);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await _pumpEditor(
        tester,
        brightness: Brightness.light,
        products: [_dragProduct],
      );
      await _selectProduct(tester, _dragProduct);

      final itemFinder = find.byKey(
        const Key('outfit-canvas-item-drag-product'),
      );
      expect(itemFinder, findsOneWidget);
      expect(
        find.bySemanticsLabel('Перетащите сюда, чтобы удалить вещь'),
        findsNothing,
      );

      final gesture = await tester.startGesture(tester.getCenter(itemFinder));
      await gesture.moveBy(const Offset(24, 0));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Перетащите сюда, чтобы удалить вещь'),
        findsOneWidget,
      );

      final trashFinder = find.byKey(const Key('outfit-editor-trash'));
      await gesture.moveTo(tester.getCenter(trashFinder));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Отпустите, чтобы удалить вещь'),
        findsOneWidget,
      );

      await gesture.up();
      await tester.pumpAndSettle();

      expect(itemFinder, findsNothing);
      expect(find.byKey(const Key('outfit-editor-actions')), findsOneWidget);
      expect(
        hapticCalls.map((call) => call.arguments),
        containsAll(<Object?>[
          'HapticFeedbackType.selectionClick',
          'HapticFeedbackType.mediumImpact',
        ]),
      );
      semantics.dispose();
    },
  );

  testWidgets('ending a gesture outside the trash keeps the item', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();

    await _pumpEditor(
      tester,
      brightness: Brightness.light,
      products: [_dragProduct],
    );
    await _selectProduct(tester, _dragProduct);

    final itemFinder = find.byKey(const Key('outfit-canvas-item-drag-product'));
    final gesture = await tester.startGesture(tester.getCenter(itemFinder));
    await gesture.moveBy(const Offset(32, 16));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Перетащите сюда, чтобы удалить вещь'),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(itemFinder, findsOneWidget);
    expect(
      find.bySemanticsLabel('Перетащите сюда, чтобы удалить вещь'),
      findsNothing,
    );
    semantics.dispose();
  });
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required Brightness brightness,
  List<Product> products = const [],
  Future<void> Function(CreatedOutfit outfit)? onPublish,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(brightness),
      home: OutfitCreateScreen(myProducts: products, onPublish: onPublish),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectProduct(WidgetTester tester, Product product) async {
  await tester.tap(find.text('Добавить одежду'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(product.title));
  await tester.pumpAndSettle();
}

final _dragProduct = Product(
  id: 'drag-product',
  title: 'Тестовая куртка',
  detailTitle: 'Тестовая куртка',
  price: '1 000 ₽',
  detailPrice: '1 000 ₽',
  priceValue: 1000,
  image: 'assets/products/graphic_hoodie.jpg',
  category: 'Одежда',
  brand: 'Test',
  size: 'M',
  color: 'Чёрный',
  condition: 'Новое',
  dotsOnDark: false,
  outfitImages: const ['assets/products/graphic_hoodie.jpg'],
);
