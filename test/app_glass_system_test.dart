import 'package:clothes/core/app_appearance.dart';
import 'package:clothes/widgets/app_appearance_background.dart';
import 'package:clothes/widgets/app_glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('glass roles expose distinct optical weights', () {
    final glass = AppGlassStyle.liquid(
      brightness: Brightness.light,
      accent: const Color(0xFFB6FF00),
    );

    expect(glass.enabled, isTrue);
    expect(
      glass.materialFor(AppGlassRole.navigation).blurSigma,
      greaterThan(glass.materialFor(AppGlassRole.compactButton).blurSigma),
    );
    expect(
      glass.materialFor(AppGlassRole.sheet).tintOpacity,
      greaterThan(glass.materialFor(AppGlassRole.navigation).tintOpacity),
    );
    expect(
      glass.materialFor(AppGlassRole.input).rimOpacity,
      lessThan(glass.materialFor(AppGlassRole.navigation).rimOpacity),
    );
    expect(
      AppGlassStyle.disabled.materialFor(AppGlassRole.input).padding,
      glass.materialFor(AppGlassRole.input).padding,
    );
  });

  test(
    'custom plain color is exact while wallpaper scaffold is transparent',
    () {
      const plain = AppAppearanceSettings(
        theme: AppThemePreference.custom,
        customDark: true,
        background: AppBackgroundStyle.plain,
        backgroundColorValue: 0xFF123456,
      );
      final plainTheme = buildAppTheme(Brightness.dark, settings: plain);
      final plainPalette = plainTheme.extension<AppPalette>()!;
      final plainBackdrop = plainTheme.extension<AppBackdropStyle>()!;

      expect(plainPalette.page, const Color(0xFF123456));
      expect(plainBackdrop.rootColor, const Color(0xFF123456));
      expect(plainBackdrop.scaffoldColor, const Color(0xFF123456));

      const photo = AppAppearanceSettings(
        theme: AppThemePreference.custom,
        customDark: true,
        background: AppBackgroundStyle.photo,
        backgroundColorValue: 0xFF202228,
      );
      final photoTheme = buildAppTheme(Brightness.dark, settings: photo);
      final photoPalette = photoTheme.extension<AppPalette>()!;
      final photoBackdrop = photoTheme.extension<AppBackdropStyle>()!;

      expect(photoBackdrop.hasWallpaper, isTrue);
      expect(photoBackdrop.scaffoldColor, Colors.transparent);
      expect(photoBackdrop.rootColor, const Color(0xFF202228));
      expect(photoPalette.page.a, 1);
      expect(photoBackdrop.contentColor.a, 1);
    },
  );

  testWidgets(
    'root backdrop groups glass and glass does not block child taps',
    (tester) async {
      const settings = AppAppearanceSettings(
        theme: AppThemePreference.custom,
        liquidGlassEnabled: true,
        background: AppBackgroundStyle.pattern,
      );
      var taps = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.dark, settings: settings),
          home: AppAppearanceBackground(
            settings: settings,
            child: Center(
              child: AppGlassSurface(
                role: AppGlassRole.compactButton,
                child: GestureDetector(
                  key: const Key('glass-child-action'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const SizedBox(width: 80, height: 48),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(BackdropGroup), findsOneWidget);
      final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(filter.filter, isNull);
      expect(filter.filterConfig, isNotNull);

      await tester.tap(find.byKey(const Key('glass-child-action')));
      await tester.pump();
      expect(taps, 1);
    },
  );

  testWidgets('photo blur and dim are each composed once at the root', (
    tester,
  ) async {
    const settings = AppAppearanceSettings(
      theme: AppThemePreference.custom,
      background: AppBackgroundStyle.photo,
      backgroundColorValue: 0xFF202228,
      photoBlur: 6,
      photoDim: 0.4,
      wallpaperPath:
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark, settings: settings),
        home: const AppAppearanceBackground(
          settings: settings,
          child: SizedBox.expand(),
        ),
      ),
    );

    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox &&
            widget.color == const Color(0xFF202228).withValues(alpha: 0.4),
      ),
      findsOneWidget,
    );
  });

  testWidgets('disabled glass keeps its padding', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const Center(
          child: AppGlassSurface(
            padding: EdgeInsets.all(12),
            child: SizedBox(key: Key('padded-content'), width: 20, height: 10),
          ),
        ),
      ),
    );

    final padding = find.descendant(
      of: find.byType(AppGlassSurface),
      matching: find.byType(Padding),
    );
    expect(tester.getSize(padding.first), const Size(44, 34));
  });

  testWidgets('AnimatedTheme fully removes glass after switching it off', (
    tester,
  ) async {
    const enabled = AppAppearanceSettings(liquidGlassEnabled: true);
    await tester.pumpWidget(
      MaterialApp(
        themeAnimationDuration: const Duration(milliseconds: 120),
        theme: buildAppTheme(Brightness.light, settings: enabled),
        home: const Center(
          child: AppGlassSurface(child: SizedBox(width: 80, height: 48)),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        themeAnimationDuration: const Duration(milliseconds: 120),
        theme: buildAppTheme(Brightness.light),
        home: const Center(
          child: AppGlassSurface(child: SizedBox(width: 80, height: 48)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsNothing);
    final context = tester.element(find.byType(AppGlassSurface));
    expect(context.appGlass.enabled, isFalse);
  });
}
