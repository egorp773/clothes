import 'package:clothes/core/app_appearance.dart';
import 'package:clothes/models/app_profile.dart';
import 'package:clothes/models/product.dart';
import 'package:clothes/models/profile_feature.dart';
import 'package:clothes/screens/catalog_screen.dart';
import 'package:clothes/screens/profile_feature_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accent text token preserves contrast for a bright custom color', () {
    const settings = AppAppearanceSettings(
      theme: AppThemePreference.custom,
      customDark: false,
      accentColorValue: 0xFFFFFF00,
      backgroundColorValue: 0xFFFFFFFF,
    );
    final theme = buildAppTheme(Brightness.light, settings: settings);
    final palette = theme.extension<AppPalette>()!;

    expect(palette.accent, const Color(0xFFFFFF00));
    expect(
      _contrastRatio(palette.accentInk, palette.surfaceRaised),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(palette.accentEmphasis, palette.surfaceRaised),
      greaterThanOrEqualTo(4.5),
    );
    expect(palette.accentEmphasis, isNot(palette.ink));
    expect(palette.accentEmphasis, isNot(palette.accent));
    expect(theme.colorScheme.primary, palette.accent);
    expect(theme.colorScheme.onPrimary, palette.onAccent);
    expect(
      theme.filledButtonTheme.style?.backgroundColor?.resolve({}),
      palette.accent,
    );
    expect(
      theme.filledButtonTheme.style?.foregroundColor?.resolve({}),
      palette.onAccent,
    );

    final focusedBorder = theme.inputDecorationTheme.focusedBorder;
    expect(focusedBorder, isA<OutlineInputBorder>());
    expect(
      (focusedBorder! as OutlineInputBorder).borderSide.color,
      palette.accentInk,
    );
  });

  test('liquid glass keeps the brand accent outside the glass material', () {
    const settings = AppAppearanceSettings(liquidGlassEnabled: true);
    final lightTheme = buildAppTheme(Brightness.light, settings: settings);
    final darkTheme = buildAppTheme(Brightness.dark, settings: settings);

    expect(lightTheme.extension<AppPalette>()!.accent, AppPalette.light.accent);
    expect(darkTheme.extension<AppPalette>()!.accent, AppPalette.dark.accent);
    expect(lightTheme.extension<AppGlassStyle>()!.enabled, isTrue);
    expect(darkTheme.extension<AppGlassStyle>()!.enabled, isTrue);
  });

  testWidgets('settings reserve accent for icons and primary selection', (
    tester,
  ) async {
    const settings = AppAppearanceSettings(
      theme: AppThemePreference.custom,
      customDark: true,
      accentColorValue: 0xFF8FD8FF,
      backgroundColorValue: 0xFF181B20,
    );
    final theme = buildAppTheme(Brightness.dark, settings: settings);
    final palette = theme.extension<AppPalette>()!;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: ProfileSettingsScreen(
          appearance: settings,
          onEditProfile: () {},
          onNotificationSettings: () {},
          onAddresses: () {},
          onSupport: () {},
          onFaq: () {},
          onDocuments: () {},
        ),
      ),
    );

    expect(
      tester.widget<Icon>(find.byIcon(Icons.contrast_rounded)).color,
      palette.accentInk,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.person_outline_rounded)).color,
      palette.accentInk,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.chevron_right_rounded).first).color,
      palette.muted,
    );
  });

  testWidgets('catalog tab moves the restrained accent with selection', (
    tester,
  ) async {
    final threads = ChangeNotifier();
    addTearDown(threads.dispose);
    final theme = buildAppTheme(Brightness.light);
    final palette = theme.extension<AppPalette>()!;

    await tester.pumpWidget(MaterialApp(theme: theme, home: _catalog(threads)));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -520));
    await tester.pumpAndSettle();

    Text tabLabel(int index) =>
        tester.widget<Text>(find.byKey(Key('catalog-tab-label-$index')));

    expect(tabLabel(1).style?.color, palette.accentInk);
    expect(tabLabel(0).style?.color, palette.muted);

    tester
        .widget<GestureDetector>(find.byKey(const Key('catalog-tab-0')))
        .onTap!();
    await tester.pumpAndSettle();

    expect(tabLabel(0).style?.color, palette.accentInk);
    expect(tabLabel(1).style?.color, palette.muted);
  });
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

CatalogScreen _catalog(Listenable threads) => CatalogScreen(
  scale: 1,
  sidePadding: 12,
  products: const <Product>[],
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
  onLoadSellerProducts: (_) async => const <Product>[],
  onStartDirectChat: (_) async => null,
  onSendMessage: (_, _) async {},
  onProductViewed: (_) {},
  deliveryProfile: const DeliveryProfile(),
  onSaveDeliveryProfile: (_) async {},
  onCreateDeliveryOrder:
      (_, {required deliveryService, required deliveryPrice}) async => null,
  onLoadReviews: (_) async => const <SellerReview>[],
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
  currentUserId: 'accent-test-user',
  threadsListenable: threads,
  resolveThread: (_) => null,
  lastSeenForUser: (_) => null,
);
