import 'package:clothes/core/app_appearance.dart';
import 'package:clothes/models/profile_feature.dart';
import 'package:clothes/screens/product_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _openRouteKey = Key('open-product-route');
const _underlayKey = Key('product-route-underlay');
const _routePageKey = Key('product-route-page');
const _routeActionKey = Key('product-route-action');
const _underlayColor = Color(0xFF8D2148);

void main() {
  test('product route has a stable non-opaque modal contract', () {
    final route = buildProductRoute<void>(
      settings: const RouteSettings(name: '/product/test'),
      builder: (_) => const SizedBox.shrink(),
    );

    expect(route, isA<ProductPageRoute<void>>());
    expect(route.settings.name, '/product/test');
    expect(route.opaque, isFalse);
    expect(route.maintainState, isTrue);
    expect(route.allowSnapshotting, isFalse);
    expect(route.barrierDismissible, isFalse);
    expect(route.barrierColor, Colors.transparent);
    expect(
      route.canTransitionFrom(
        MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()),
      ),
      isFalse,
    );
  });

  testWidgets('product route keeps its underlay live and blocks tap-through', (
    tester,
  ) async {
    await tester.pumpWidget(
      _RouteHarness(routeBuilder: (_) => const _TransparentRoutePage()),
    );

    final harness = tester.state<_RouteHarnessState>(
      find.byType(_RouteHarness),
    );
    final underlayElement = tester.element(find.byKey(_underlayKey));
    await tester.tap(find.byKey(_openRouteKey));
    await tester.pumpAndSettle();

    expect(find.byKey(_underlayKey), findsOneWidget);
    expect(tester.element(find.byKey(_underlayKey)), same(underlayElement));
    expect(find.byKey(_routePageKey), findsOneWidget);
    _expectUnderlayPaintedAtRest(tester);

    harness.underlayTaps = 0;
    await tester.tapAt(const Offset(20, 100));
    await tester.pump();
    expect(harness.underlayTaps, 0);

    await tester.tap(find.byKey(_routeActionKey));
    await tester.pump();
    expect(harness.routeActionTaps, 1);
    expect(harness.underlayTaps, 0);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.element(find.byKey(_underlayKey)), same(underlayElement));
  });

  testWidgets('product route supports the native iOS edge swipe', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _RouteHarness(
        platform: TargetPlatform.iOS,
        routeBuilder: (_) => const _TransparentRoutePage(),
      ),
    );

    await tester.tap(find.byKey(_openRouteKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_routePageKey), findsOneWidget);
    _expectUnderlayPaintedAtRest(tester);

    await tester.timedDragFrom(
      const Offset(1, 400),
      const Offset(330, 0),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(_routePageKey), findsNothing);
    expect(find.byKey(_underlayKey), findsOneWidget);
  });

  for (final glassEnabled in [false, true]) {
    testWidgets(
      'product controls remain tappable with glass ${glassEnabled ? 'on' : 'off'}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        var contactCalls = 0;
        const settings = AppAppearanceSettings();
        final effectiveSettings = settings.copyWith(
          liquidGlassEnabled: glassEnabled,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(Brightness.light, settings: effectiveSettings),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    key: _openRouteKey,
                    onPressed: () {
                      Navigator.of(context).push(
                        buildProductRoute<void>(
                          builder: (_) => _buildProductScreen(
                            onContactSeller: () => contactCalls++,
                          ),
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(_openRouteKey));
        await tester.pumpAndSettle();

        final scaffold = tester.widget<Scaffold>(
          find.byKey(productScreenScaffoldKey),
        );
        expect(scaffold.backgroundColor, Colors.transparent);
        expect(find.byKey(productScreenContentKey), findsOneWidget);
        expect(find.byKey(productScreenFooterKey), findsOneWidget);

        await tester.tap(find.byKey(productScreenMessageButtonKey));
        await tester.pump();
        expect(contactCalls, 1);

        await tester.tap(find.byKey(productScreenBackButtonKey));
        await tester.pumpAndSettle();
        expect(find.byType(ProductScreen), findsNothing);
      },
    );
  }
}

class _RouteHarness extends StatefulWidget {
  const _RouteHarness({
    required this.routeBuilder,
    this.platform = TargetPlatform.android,
  });

  final WidgetBuilder routeBuilder;
  final TargetPlatform platform;

  @override
  State<_RouteHarness> createState() => _RouteHarnessState();
}

class _RouteHarnessState extends State<_RouteHarness> {
  int underlayTaps = 0;
  int routeActionTaps = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(platform: widget.platform),
      home: Builder(
        builder: (context) => Scaffold(
          backgroundColor: _underlayColor,
          body: GestureDetector(
            key: _underlayKey,
            behavior: HitTestBehavior.opaque,
            onTap: () => underlayTaps++,
            child: Center(
              child: FilledButton(
                key: _openRouteKey,
                onPressed: () {
                  Navigator.of(
                    context,
                  ).push(buildProductRoute<void>(builder: widget.routeBuilder));
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _expectUnderlayPaintedAtRest(WidgetTester tester) {
  final underlay = find.byKey(_underlayKey);
  final fades = tester.widgetList<FadeTransition>(
    find.ancestor(of: underlay, matching: find.byType(FadeTransition)),
  );
  for (final fade in fades) {
    expect(
      fade.opacity.value,
      closeTo(1, 0.000001),
      reason:
          'A settled Product route must not fade the catalog out behind its '
          'transparent gap.',
    );
  }

  final slides = tester.widgetList<SlideTransition>(
    find.ancestor(of: underlay, matching: find.byType(SlideTransition)),
  );
  expect(
    fades.isNotEmpty || slides.isNotEmpty,
    isTrue,
    reason: 'The harness should exercise a platform page transition.',
  );
  for (final slide in slides) {
    expect(
      slide.position.value.distance,
      closeTo(0, 0.000001),
      reason:
          'A settled Product route must not leave the catalog translated '
          'behind its transparent gap.',
    );
  }
}

class _TransparentRoutePage extends StatelessWidget {
  const _TransparentRoutePage();

  @override
  Widget build(BuildContext context) {
    final harness = context.findAncestorStateOfType<_RouteHarnessState>()!;
    return Scaffold(
      key: _routePageKey,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned(
            left: 40,
            right: 40,
            bottom: 40,
            child: GestureDetector(
              key: _routeActionKey,
              behavior: HitTestBehavior.opaque,
              onTap: () => harness.routeActionTaps++,
              child: const ColoredBox(
                color: Colors.white,
                child: SizedBox(height: 80),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

ProductScreen _buildProductScreen({required VoidCallback onContactSeller}) {
  return ProductScreen(
    product: const ProductDetailData(
      id: 'product-route-test',
      title: 'Test jacket',
      description: 'Product route test description',
      price: '10 000',
      priceValue: 10000,
      image: '',
      images: [],
      category: 'Jackets',
      brand: 'Test',
      color: 'Black',
      sellerName: 'Seller',
      sellerHandle: '@seller',
      size: 'M',
      condition: 'New',
      location: 'Moscow',
      isLiked: false,
    ),
    onLike: () {},
    onContactSeller: onContactSeller,
    onOpenSeller: () {},
    onOpenReviews: () {},
    relatedProducts: const [],
    onRelatedProductTap: (_) {},
    deliveryProfile: const DeliveryProfile(),
    onSaveDeliveryProfile: (_) async {},
    onCreateDeliveryOrder:
        ({required deliveryService, required deliveryPrice}) async => null,
  );
}
