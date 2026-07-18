import 'package:clothes/core/app_appearance.dart';
import 'package:clothes/models/profile_feature.dart';
import 'package:clothes/screens/catalog_screen.dart';
import 'package:clothes/widgets/app_bottom_nav.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('navigation animates from expanded to compact without labels', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    final compact = ValueNotifier<bool>(false);
    addTearDown(compact.dispose);

    await _pumpNavigation(
      tester,
      compact: compact,
      appearance: const AppAppearanceSettings(liquidGlassEnabled: true),
    );

    final panel = find.byKey(const Key('app-bottom-nav-panel'));
    expect(tester.getSize(panel), const Size(366, 60));
    final expandedPanelRect = tester.getRect(panel);
    for (var index = 0; index < 5; index++) {
      expect(
        tester.getRect(find.byKey(Key('bottom-nav-label-$index'))).bottom,
        lessThanOrEqualTo(expandedPanelRect.bottom),
      );
    }

    compact.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    // A single easeOut curve should still leave measurable travel at the
    // midpoint; applying the curve twice effectively snaps to the end here.
    expect(tester.getSize(panel).width, greaterThan(336));
    expect(tester.getSize(panel).width, lessThan(350));

    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.getSize(panel), const Size(334, 52));
    final compactPanelRect = tester.getRect(panel);
    for (var index = 0; index < 5; index++) {
      final itemSize = tester.getSize(
        find.byKey(Key('bottom-nav-item-$index')),
      );
      expect(itemSize.width, greaterThanOrEqualTo(44));
      expect(itemSize.height, greaterThanOrEqualTo(48));
      expect(
        tester.getRect(find.byKey(Key('bottom-nav-label-$index'))).top,
        greaterThanOrEqualTo(compactPanelRect.bottom),
      );
    }
  });

  for (final initiallyCompact in <bool>[false, true]) {
    testWidgets('all navigation items remain tappable when '
        '${initiallyCompact ? 'compact' : 'expanded'}', (tester) async {
      _setViewport(tester, const Size(390, 844));
      final compact = ValueNotifier<bool>(initiallyCompact);
      addTearDown(compact.dispose);
      final selected = <int>[];
      var createTaps = 0;

      await _pumpNavigation(
        tester,
        compact: compact,
        appearance: const AppAppearanceSettings(liquidGlassEnabled: true),
        onTabSelected: selected.add,
        onCreateTap: () => createTaps++,
      );

      for (var index = 0; index < 5; index++) {
        await tester.tap(find.byKey(Key('bottom-nav-item-$index')));
        await tester.pump();
      }

      expect(selected, <int>[0, 1, 3, 4]);
      expect(createTaps, 1);
    });
  }

  testWidgets('catalog scroll hysteresis prevents compact-state jitter', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    final compactChanges = <bool>[];
    final compactState = ValueNotifier<bool>(false);
    final threads = ValueNotifier<int>(0);
    addTearDown(compactState.dispose);
    addTearDown(threads.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: CatalogScreen(
          scale: 1,
          sidePadding: 12,
          products: const [],
          onToggleLike: (_) async {},
          onHideProduct: (_) async {},
          onSubmitContentReport:
              ({
                required targetType,
                required targetId,
                required reason,
                details = '',
              }) async => true,
          onBlockUser: (_) async => true,
          onShareProduct: (_) {},
          onContactSeller: (_) async => null,
          onLoadSellerProfile: (_) async => null,
          onLoadSellerProducts: (_) async => const [],
          onStartDirectChat: (_) async => null,
          onSendMessage: (_, _) async {},
          onProductViewed: (_) {},
          deliveryProfile: const DeliveryProfile(),
          onSaveDeliveryProfile: (_) async {},
          onCreateDeliveryOrder:
              (_, {required deliveryService, required deliveryPrice}) async =>
                  null,
          onLoadReviews: (_) async => const [],
          onCreateReview:
              ({
                required sellerId,
                required productId,
                required productTitle,
                required productImage,
                required rating,
                required text,
                hasPhoto = false,
              }) async {},
          currentUserId: 'viewer',
          threadsListenable: threads,
          resolveThread: (_) => null,
          lastSeenForUser: (_) => null,
          navigationCompactController: compactState,
          onNavigationCompactChanged: compactChanges.add,
        ),
      ),
    );
    await tester.pump();

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    final position = scrollable.position;

    position.jumpTo(80);
    await tester.pump();
    expect(compactChanges, <bool>[true]);
    expect(compactState.value, isTrue);

    // Alternating movement above the noise threshold resets accumulated
    // travel in the other direction and must not make the capsule chatter.
    for (var iteration = 0; iteration < 5; iteration++) {
      position.jumpTo(81.5);
      await tester.pump();
      position.jumpTo(80);
      await tester.pump();
    }
    expect(compactChanges, <bool>[true]);

    // Expanding requires accumulated upward travel, not one tiny reversal.
    position.jumpTo(59);
    await tester.pump();
    expect(compactChanges, <bool>[true]);
    position.jumpTo(56);
    await tester.pump();
    expect(compactChanges, <bool>[true, false]);

    // Returning to the top lock cannot emit duplicate expanded states.
    position.jumpTo(0);
    await tester.pump();
    expect(compactChanges, <bool>[true, false]);

    // A shell-level reset (tab change/re-tap) updates the shared source of
    // truth. Continued downward scrolling must be able to collapse again.
    position.jumpTo(80);
    await tester.pump();
    expect(compactChanges, <bool>[true, false, true]);
    compactState.value = false;
    await tester.pump();
    position.jumpTo(125);
    await tester.pump();
    expect(compactState.value, isTrue);
    expect(compactChanges, <bool>[true, false, true, true]);

    ScrollEndNotification(
      metrics: position,
      context: scrollable.context,
    ).dispatch(scrollable.context);
    await tester.pump(const Duration(milliseconds: 721));
    expect(compactState.value, isFalse);
    expect(compactChanges, <bool>[true, false, true, true, false]);
  });

  testWidgets('glass-off navigation keeps stable fallback and touch targets', (
    tester,
  ) async {
    _setViewport(tester, const Size(320, 568));
    final compact = ValueNotifier<bool>(false);
    addTearDown(compact.dispose);
    final selected = <int>[];

    await _pumpNavigation(
      tester,
      compact: compact,
      appearance: const AppAppearanceSettings(liquidGlassEnabled: false),
      onTabSelected: selected.add,
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('app-bottom-nav-panel'))),
      const Size(296, 60),
    );
    final material = tester.widget<DecoratedBox>(
      find.byKey(const Key('app-bottom-nav-material')),
    );
    final decoration = material.decoration as BoxDecoration;
    expect(decoration.color, AppPalette.light.surface);

    await tester.tap(find.byKey(const Key('bottom-nav-item-4')));
    await tester.pump();
    expect(selected, <int>[4]);

    compact.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      tester.getSize(find.byKey(const Key('app-bottom-nav-panel'))),
      const Size(264, 52),
    );
    expect(tester.takeException(), isNull);
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpNavigation(
  WidgetTester tester, {
  required ValueListenable<bool> compact,
  required AppAppearanceSettings appearance,
  ValueChanged<int>? onTabSelected,
  VoidCallback? onCreateTap,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light, settings: appearance),
      home: BackdropGroup(
        child: Scaffold(
          bottomNavigationBar: AppBottomNav(
            currentIndex: 0,
            compactListenable: compact,
            onTabSelected: onTabSelected ?? (_) {},
            onCreateTap: onCreateTap ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
