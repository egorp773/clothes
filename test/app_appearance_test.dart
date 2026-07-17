import 'package:clothes/core/app_appearance.dart';
import 'package:clothes/screens/appearance_editor_screen.dart';
import 'package:clothes/screens/profile_feature_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('appearance settings preserve future-friendly fields', () {
    const settings = AppAppearanceSettings(
      theme: AppThemePreference.dark,
      background: AppBackgroundStyle.plain,
    );

    final restored = AppAppearanceSettings.fromJson(settings.toJson());

    expect(restored.theme, AppThemePreference.dark);
    expect(restored.background, AppBackgroundStyle.plain);
    expect(settings.toJson()['version'], 4);
  });

  test('appearance controller persists selected theme', () async {
    final controller = AppAppearanceController();
    await controller.setTheme(AppThemePreference.dark);

    final restored = AppAppearanceController();
    await restored.load();

    expect(restored.settings.theme, AppThemePreference.dark);
    expect(restored.themeMode, ThemeMode.dark);
    controller.dispose();
    restored.dispose();
  });

  test('dark app theme exposes the dark design palette', () {
    final theme = buildAppTheme(Brightness.dark);
    final palette = theme.extension<AppPalette>();

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppPalette.dark.page);
    expect(palette, AppPalette.dark);
  });

  test('liquid glass composes with light and dark themes', () async {
    final controller = AppAppearanceController();
    await controller.setTheme(AppThemePreference.light);
    await controller.setLiquidGlass(true);
    final lightTheme = buildAppTheme(
      Brightness.light,
      settings: controller.settings,
    );

    expect(controller.themeMode, ThemeMode.light);
    expect(controller.settings.liquidGlassEnabled, isTrue);
    expect(lightTheme.brightness, Brightness.light);
    expect(
      lightTheme.extension<AppPalette>()!.ink.computeLuminance(),
      lessThan(.5),
    );
    expect(lightTheme.extension<AppPalette>()!.accent, const Color(0xFF333B45));
    expect(lightTheme.extension<AppGlassStyle>()?.enabled, isTrue);

    await controller.setTheme(AppThemePreference.dark);
    final darkTheme = buildAppTheme(
      Brightness.dark,
      settings: controller.settings,
    );

    expect(controller.themeMode, ThemeMode.dark);
    expect(darkTheme.brightness, Brightness.dark);
    expect(
      darkTheme.extension<AppPalette>()!.ink.computeLuminance(),
      greaterThan(.5),
    );
    expect(darkTheme.extension<AppPalette>()!.accent, const Color(0xFFD9DEE5));
    expect(darkTheme.extension<AppGlassStyle>()?.enabled, isTrue);
    controller.dispose();
  });

  test(
    'legacy liquid glass theme migrates to dark theme with glass enabled',
    () {
      final settings = AppAppearanceSettings.fromJson(<String, Object>{
        'theme': 'liquidGlass',
      });

      expect(settings.theme, AppThemePreference.dark);
      expect(settings.liquidGlassEnabled, isTrue);
    },
  );

  test('custom theme keeps background controls and contrast mode', () async {
    const settings = AppAppearanceSettings(
      theme: AppThemePreference.custom,
      liquidGlassEnabled: true,
      background: AppBackgroundStyle.pattern,
      customDark: false,
      accentColorValue: 0xFF67D7FF,
      backgroundColorValue: 0xFFEDF5F8,
      pattern: AppPatternStyle.waves,
      patternColorValue: 0xFF38506A,
      patternIntensity: 0.42,
    );
    final controller = AppAppearanceController();
    await controller.updateSettings(settings);

    expect(controller.themeMode, ThemeMode.light);
    expect(controller.settings.pattern, AppPatternStyle.waves);
    expect(controller.settings.patternColor, const Color(0xFF38506A));
    expect(
      buildAppTheme(
        Brightness.light,
        settings: settings,
      ).extension<AppPalette>()!.accent,
      const Color(0xFF67D7FF),
    );
    controller.dispose();
  });

  testWidgets('profile settings opens preset and custom theme choices', (
    tester,
  ) async {
    AppThemePreference? selected;
    AppAppearanceSettings? savedCustomTheme;
    bool? glassEnabled;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: ProfileSettingsScreen(
          appearance: const AppAppearanceSettings(),
          onThemePreferenceChanged: (value) => selected = value,
          onLiquidGlassChanged: (value) => glassEnabled = value,
          onCustomAppearanceSaved: (settings, _) async {
            savedCustomTheme = settings;
          },
          onEditProfile: () {},
          onNotificationSettings: () {},
          onAddresses: () {},
          onSupport: () {},
          onFaq: () {},
          onDocuments: () {},
        ),
      ),
    );

    expect(find.byKey(const Key('profile-theme-system')), findsNothing);
    await tester.tap(find.byKey(const Key('profile-appearance-selector')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-theme-system')), findsOneWidget);
    expect(find.byKey(const Key('profile-theme-light')), findsOneWidget);
    expect(find.byKey(const Key('profile-theme-dark')), findsOneWidget);
    expect(find.byKey(const Key('profile-theme-custom')), findsOneWidget);
    expect(
      find.byKey(const Key('profile-liquid-glass-toggle')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('profile-theme-liquidGlass')), findsNothing);

    await tester.tap(find.byKey(const Key('profile-liquid-glass-toggle')));
    await tester.pumpAndSettle();
    expect(glassEnabled, isTrue);

    await tester.tap(find.byKey(const Key('profile-theme-dark')));
    await tester.pumpAndSettle();
    expect(selected, AppThemePreference.dark);

    await tester.tap(find.byKey(const Key('profile-appearance-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-theme-custom')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('appearance-editor-preview')), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('appearance-accent-color')),
    );
    await tester.tap(find.byKey(const Key('appearance-accent-color')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-color-picker-sheet')), findsOneWidget);
    expect(find.byKey(const Key('app-color-picker-sv')), findsOneWidget);
    expect(find.byKey(const Key('app-color-picker-hue')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('app-color-picker-hex')),
      '123ABC',
    );
    await tester.tap(find.byKey(const Key('app-color-picker-apply')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('appearance-editor-pattern-mode')),
    );
    await tester.tap(find.byKey(const Key('appearance-editor-pattern-mode')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('appearance-pattern-confetti')),
    );
    await tester.tap(find.byKey(const Key('appearance-pattern-confetti')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('appearance-editor-apply')));
    await tester.pumpAndSettle();
    expect(savedCustomTheme?.accentColor, const Color(0xFF123ABC));
    expect(savedCustomTheme?.pattern, AppPatternStyle.confetti);
  });

  testWidgets('an existing wallpaper can be removed from a custom theme', (
    tester,
  ) async {
    AppearanceEditorResult? editorResult;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open-appearance-editor'),
                onPressed: () async {
                  editorResult = await Navigator.of(context)
                      .push<AppearanceEditorResult>(
                        MaterialPageRoute(
                          builder: (_) => const AppearanceEditorScreen(
                            initialSettings: AppAppearanceSettings(
                              theme: AppThemePreference.custom,
                              background: AppBackgroundStyle.photo,
                              wallpaperPath: 'missing-wallpaper.jpg',
                            ),
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

    await tester.tap(find.byKey(const Key('open-appearance-editor')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('appearance-editor-remove-photo')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(
      find.byKey(const Key('appearance-editor-remove-photo')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appearance-editor-remove-photo')));
    await tester.pump();
    expect(
      find.byKey(const Key('appearance-editor-remove-photo')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('appearance-editor-apply')));
    await tester.pumpAndSettle();
    expect(editorResult?.settings.background, AppBackgroundStyle.plain);
    expect(editorResult?.settings.wallpaperPath, isEmpty);
  });
}
