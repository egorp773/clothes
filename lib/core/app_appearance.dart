import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_typography.dart';
import 'appearance_wallpaper_store.dart';

enum AppThemePreference { system, light, dark, custom }

enum AppBackgroundStyle { plain, pattern, photo }

enum AppPatternStyle { dots, diagonal, waves, grid, doodles, confetti, bubbles }

typedef AppAppearanceSaver =
    Future<void> Function(AppAppearanceSettings settings, XFile? wallpaper);

@immutable
class AppAppearanceSettings {
  const AppAppearanceSettings({
    this.theme = AppThemePreference.system,
    this.liquidGlassEnabled = false,
    this.background = AppBackgroundStyle.plain,
    this.customDark = true,
    this.accentColorValue = 0xFFC1FF36,
    this.backgroundColorValue = 0xFF202228,
    this.pattern = AppPatternStyle.doodles,
    this.patternColorValue = 0xFFF2F2F4,
    this.patternIntensity = 0.34,
    this.photoDim = 0.48,
    this.photoBlur = 0,
    this.wallpaperPath = '',
  });

  final AppThemePreference theme;
  final bool liquidGlassEnabled;
  final AppBackgroundStyle background;
  final bool customDark;
  final int accentColorValue;
  final int backgroundColorValue;
  final AppPatternStyle pattern;
  final int patternColorValue;
  final double patternIntensity;
  final double photoDim;
  final double photoBlur;
  final String wallpaperPath;

  Color get accentColor => Color(accentColorValue);
  Color get backgroundColor => Color(backgroundColorValue);
  Color get patternColor => Color(patternColorValue);

  AppAppearanceSettings copyWith({
    AppThemePreference? theme,
    bool? liquidGlassEnabled,
    AppBackgroundStyle? background,
    bool? customDark,
    int? accentColorValue,
    int? backgroundColorValue,
    AppPatternStyle? pattern,
    int? patternColorValue,
    double? patternIntensity,
    double? photoDim,
    double? photoBlur,
    String? wallpaperPath,
  }) {
    return AppAppearanceSettings(
      theme: theme ?? this.theme,
      liquidGlassEnabled: liquidGlassEnabled ?? this.liquidGlassEnabled,
      background: background ?? this.background,
      customDark: customDark ?? this.customDark,
      accentColorValue: accentColorValue ?? this.accentColorValue,
      backgroundColorValue: backgroundColorValue ?? this.backgroundColorValue,
      pattern: pattern ?? this.pattern,
      patternColorValue: patternColorValue ?? this.patternColorValue,
      patternIntensity: (patternIntensity ?? this.patternIntensity).clamp(0, 1),
      photoDim: (photoDim ?? this.photoDim).clamp(0, 0.9),
      photoBlur: (photoBlur ?? this.photoBlur).clamp(0, 18),
      wallpaperPath: wallpaperPath ?? this.wallpaperPath,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'version': 4,
    'theme': theme.name,
    'liquid_glass': liquidGlassEnabled,
    'background': background.name,
    'custom_dark': customDark,
    'accent_color': accentColorValue,
    'background_color': backgroundColorValue,
    'pattern': pattern.name,
    'pattern_color': patternColorValue,
    'pattern_intensity': patternIntensity,
    'photo_dim': photoDim,
    'photo_blur': photoBlur,
    'wallpaper_path': wallpaperPath,
  };

  factory AppAppearanceSettings.fromJson(Map<String, dynamic> json) {
    final customDark = json['custom_dark'] as bool? ?? true;
    final legacyLiquidGlass = json['theme'] == 'liquidGlass';
    return AppAppearanceSettings(
      theme: legacyLiquidGlass
          ? AppThemePreference.dark
          : AppThemePreference.values.firstWhere(
              (value) => value.name == json['theme'],
              orElse: () => AppThemePreference.system,
            ),
      liquidGlassEnabled: json['liquid_glass'] as bool? ?? legacyLiquidGlass,
      background: AppBackgroundStyle.values.firstWhere(
        (value) => value.name == json['background'],
        orElse: () => AppBackgroundStyle.plain,
      ),
      customDark: customDark,
      accentColorValue: _jsonInt(json['accent_color'], 0xFFC1FF36),
      backgroundColorValue: _jsonInt(json['background_color'], 0xFF202228),
      pattern: AppPatternStyle.values.firstWhere(
        (value) => value.name == json['pattern'],
        orElse: () => AppPatternStyle.doodles,
      ),
      patternColorValue: _jsonInt(
        json['pattern_color'],
        customDark ? 0xFFF2F2F4 : 0xFF4D5562,
      ),
      patternIntensity: _jsonDouble(
        json['pattern_intensity'],
        0.34,
      ).clamp(0, 1),
      photoDim: _jsonDouble(json['photo_dim'], 0.48).clamp(0, 0.9),
      photoBlur: _jsonDouble(json['photo_blur'], 0).clamp(0, 18),
      wallpaperPath: json['wallpaper_path'] as String? ?? '',
    );
  }
}

int _jsonInt(Object? value, int fallback) =>
    value is num ? value.toInt() : fallback;

double _jsonDouble(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;

class AppAppearanceController extends ChangeNotifier {
  static const _storageKey = 'appearance_settings_v1';

  AppAppearanceSettings _settings = const AppAppearanceSettings();
  AppAppearanceSettings get settings => _settings;

  ThemeMode get themeMode => switch (_settings.theme) {
    AppThemePreference.system => ThemeMode.system,
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
    AppThemePreference.custom =>
      _settings.customDark ? ThemeMode.dark : ThemeMode.light,
  };

  Future<void> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final stored = preferences.getString(_storageKey);
      if (stored == null) return;
      final decoded = jsonDecode(stored);
      if (decoded is! Map<String, dynamic>) return;
      _settings = AppAppearanceSettings.fromJson(decoded);
      notifyListeners();
    } catch (_) {
      // Keep safe defaults when an old or partially written value is found.
    }
  }

  Future<void> setTheme(AppThemePreference theme) async {
    if (_settings.theme == theme) return;
    _settings = _settings.copyWith(theme: theme);
    notifyListeners();
    await _persist();
  }

  Future<void> setLiquidGlass(bool enabled) async {
    if (_settings.liquidGlassEnabled == enabled) return;
    _settings = _settings.copyWith(liquidGlassEnabled: enabled);
    notifyListeners();
    await _persist();
  }

  Future<void> applyCustomTheme(
    AppAppearanceSettings settings,
    XFile? wallpaper,
  ) async {
    final previousWallpaper = _settings.wallpaperPath;
    var next = settings.copyWith(theme: AppThemePreference.custom);
    if (wallpaper != null) {
      final storedPath = await storeAppearanceWallpaper(wallpaper);
      if (storedPath != null) {
        next = next.copyWith(
          background: AppBackgroundStyle.photo,
          wallpaperPath: storedPath,
        );
      } else {
        next = next.copyWith(
          background: _settings.wallpaperPath.isEmpty
              ? AppBackgroundStyle.plain
              : AppBackgroundStyle.photo,
          wallpaperPath: _settings.wallpaperPath,
        );
      }
    }
    if (previousWallpaper.isNotEmpty &&
        previousWallpaper != next.wallpaperPath) {
      await deleteAppearanceWallpaper(previousWallpaper);
    }
    _settings = next;
    notifyListeners();
    await _persist();
  }

  Future<void> updateSettings(AppAppearanceSettings settings) async {
    if (_settings == settings) return;
    _settings = settings;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(_settings.toJson()));
  }
}

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.page,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceMuted,
    required this.border,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.shadow,
  });

  final Color page;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceMuted;
  final Color border;
  final Color ink;
  final Color muted;
  final Color accent;
  final Color shadow;

  static const light = AppPalette(
    page: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF4F4F6),
    border: Color(0xFFE5E5E9),
    ink: Color(0xFF111113),
    muted: Color(0xFF77777F),
    accent: Color(0xFFB6FF00),
    shadow: Color(0x14000000),
  );

  static const dark = AppPalette(
    page: Color(0xFF17181B),
    surface: Color(0xFF1E2024),
    surfaceRaised: Color(0xFF25272C),
    surfaceMuted: Color(0xFF2D3036),
    border: Color(0xFF3B3E45),
    ink: Color(0xFFF2F2F4),
    muted: Color(0xFFB1B2B8),
    accent: Color(0xFFC1FF36),
    shadow: Color(0x40000000),
  );

  @override
  AppPalette copyWith({
    Color? page,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceMuted,
    Color? border,
    Color? ink,
    Color? muted,
    Color? accent,
    Color? shadow,
  }) {
    return AppPalette(
      page: page ?? this.page,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      accent: accent ?? this.accent,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      page: Color.lerp(page, other.page, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get appPalette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}

@immutable
class AppGlassStyle extends ThemeExtension<AppGlassStyle> {
  const AppGlassStyle({
    required this.enabled,
    required this.blur,
    required this.materialTint,
    required this.rimColor,
    required this.depthColor,
    required this.shadowColor,
    required this.accentGlint,
  });

  final bool enabled;
  final double blur;
  final Color materialTint;
  final Color rimColor;
  final Color depthColor;
  final Color shadowColor;
  final Color accentGlint;

  static const disabled = AppGlassStyle(
    enabled: false,
    blur: 0,
    materialTint: Colors.transparent,
    rimColor: Colors.transparent,
    depthColor: Colors.transparent,
    shadowColor: Colors.transparent,
    accentGlint: Colors.transparent,
  );

  factory AppGlassStyle.liquid({
    required Brightness brightness,
    required Color accent,
  }) {
    final isDark = brightness == Brightness.dark;
    final neutralGlint = isDark
        ? const Color(0xFFF3F4F6)
        : const Color(0xFF5A5C61);
    return AppGlassStyle(
      enabled: true,
      blur: isDark ? 22 : 20,
      materialTint: isDark ? const Color(0xFF25262A) : const Color(0xFFFAFAFC),
      rimColor: isDark ? const Color(0xFFF4F4F6) : const Color(0xFFFFFFFF),
      depthColor: isDark ? const Color(0xFF08090B) : const Color(0xFF303238),
      shadowColor: isDark ? const Color(0xFF000000) : const Color(0xFF20242A),
      // Accent is deliberately almost neutral. It supplies a tiny optical
      // glint without tinting the material or the content underneath it.
      accentGlint: Color.lerp(neutralGlint, accent.withValues(alpha: 1), 0.07)!,
    );
  }

  @override
  AppGlassStyle copyWith({
    bool? enabled,
    double? blur,
    Color? materialTint,
    Color? rimColor,
    Color? depthColor,
    Color? shadowColor,
    Color? accentGlint,
  }) => AppGlassStyle(
    enabled: enabled ?? this.enabled,
    blur: blur ?? this.blur,
    materialTint: materialTint ?? this.materialTint,
    rimColor: rimColor ?? this.rimColor,
    depthColor: depthColor ?? this.depthColor,
    shadowColor: shadowColor ?? this.shadowColor,
    accentGlint: accentGlint ?? this.accentGlint,
  );

  @override
  AppGlassStyle lerp(covariant AppGlassStyle? other, double t) {
    if (other == null) return this;
    return AppGlassStyle(
      enabled: t < 0.5 ? enabled : other.enabled,
      blur: blur + (other.blur - blur) * t,
      materialTint: Color.lerp(materialTint, other.materialTint, t)!,
      rimColor: Color.lerp(rimColor, other.rimColor, t)!,
      depthColor: Color.lerp(depthColor, other.depthColor, t)!,
      shadowColor: Color.lerp(shadowColor, other.shadowColor, t)!,
      accentGlint: Color.lerp(accentGlint, other.accentGlint, t)!,
    );
  }
}

extension AppGlassContext on BuildContext {
  AppGlassStyle get appGlass =>
      Theme.of(this).extension<AppGlassStyle>() ?? AppGlassStyle.disabled;
}

ThemeData buildAppTheme(
  Brightness brightness, {
  AppAppearanceSettings settings = const AppAppearanceSettings(),
}) {
  final isGlass = settings.liquidGlassEnabled;
  final effectiveBrightness = brightness;
  final isDark = effectiveBrightness == Brightness.dark;
  final palette = _resolvePalette(effectiveBrightness, settings);
  final onAccent = _readableOn(palette.accent);
  final base = ThemeData(
    brightness: effectiveBrightness,
    useMaterial3: true,
    fontFamily: AppTypography.fontFamily,
    colorScheme: ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: effectiveBrightness,
      primary: settings.theme == AppThemePreference.custom || isDark
          ? palette.accent
          : const Color(0xFF111113),
      onPrimary: settings.theme == AppThemePreference.custom || isDark
          ? onAccent
          : Colors.white,
      surface: palette.surface,
    ),
  );
  final textTheme = _appTextTheme(
    base.textTheme,
  ).apply(bodyColor: palette.ink, displayColor: palette.ink);

  return base.copyWith(
    scaffoldBackgroundColor: palette.page,
    canvasColor: palette.surface,
    cardColor: palette.surfaceRaised,
    dividerColor: palette.border,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    iconTheme: IconThemeData(color: palette.ink),
    iconButtonTheme: const IconButtonThemeData(
      style: ButtonStyle(
        overlayColor: WidgetStatePropertyAll<Color>(Colors.transparent),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll<Color>(palette.ink),
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll<Color>(palette.ink),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: palette.border),
        ),
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(palette.ink),
        foregroundColor: WidgetStatePropertyAll<Color>(
          _readableOn(palette.ink),
        ),
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(palette.ink),
        foregroundColor: WidgetStatePropertyAll<Color>(
          _readableOn(palette.ink),
        ),
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.page,
      foregroundColor: palette.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      systemOverlayStyle: isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surfaceRaised,
      modalBackgroundColor: palette.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surfaceRaised,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surfaceMuted,
      hintStyle: TextStyle(color: palette.muted),
      labelStyle: TextStyle(color: palette.muted),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.ink, width: 1.2),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.accent
            : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll<Color>(onAccent),
      side: BorderSide(color: palette.border, width: 1.3),
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.accent
            : palette.surfaceMuted,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? onAccent : palette.muted,
      ),
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    ),
    extensions: <ThemeExtension<dynamic>>[
      palette,
      isGlass
          ? AppGlassStyle.liquid(
              brightness: effectiveBrightness,
              accent: palette.accent,
            )
          : AppGlassStyle.disabled,
    ],
  );
}

AppPalette _resolvePalette(
  Brightness brightness,
  AppAppearanceSettings settings,
) {
  final base = brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light;
  final isDark = brightness == Brightness.dark;
  var resolved = base;
  if (settings.theme == AppThemePreference.custom) {
    final tint = settings.backgroundColor;
    Color mixed(Color color, double amount) => Color.lerp(color, tint, amount)!;
    final hasWallpaper = settings.background != AppBackgroundStyle.plain;
    resolved = base.copyWith(
      page: mixed(
        base.page,
        isDark ? 0.23 : 0.1,
      ).withValues(alpha: hasWallpaper ? (isDark ? 0.74 : 0.78) : 1),
      surface: mixed(base.surface, isDark ? 0.18 : 0.07),
      surfaceRaised: mixed(base.surfaceRaised, isDark ? 0.16 : 0.05),
      surfaceMuted: mixed(base.surfaceMuted, isDark ? 0.2 : 0.09),
      border: mixed(base.border, isDark ? 0.12 : 0.05),
      accent: settings.accentColor,
    );
  }
  if (settings.liquidGlassEnabled &&
      settings.theme != AppThemePreference.custom) {
    resolved = resolved.copyWith(
      accent: isDark ? const Color(0xFFD9DEE5) : const Color(0xFF333B45),
    );
  }
  // Liquid glass is an effect for floating controls, not a transparent skin
  // for the whole application. Content keeps its normal readable palette.
  return resolved;
}

Color _readableOn(Color color) {
  final luminance = color.computeLuminance();
  final blackContrast = (luminance + 0.05) / 0.05;
  final whiteContrast = 1.05 / (luminance + 0.05);
  return blackContrast >= whiteContrast
      ? const Color(0xFF121316)
      : Colors.white;
}

TextTheme _appTextTheme(TextTheme base) {
  TextStyle? medium(TextStyle? style) => style?.copyWith(
    fontFamily: AppTypography.fontFamily,
    fontWeight: AppTypography.medium,
    letterSpacing: 0,
  );

  return base.copyWith(
    displayLarge: medium(base.displayLarge),
    displayMedium: medium(base.displayMedium),
    displaySmall: medium(base.displaySmall),
    headlineLarge: medium(base.headlineLarge),
    headlineMedium: medium(base.headlineMedium),
    headlineSmall: medium(base.headlineSmall),
    titleLarge: medium(base.titleLarge),
    titleMedium: medium(base.titleMedium),
    titleSmall: medium(base.titleSmall),
    bodyLarge: medium(base.bodyLarge),
    bodyMedium: medium(base.bodyMedium),
    bodySmall: medium(base.bodySmall),
    labelLarge: medium(base.labelLarge),
    labelMedium: medium(base.labelMedium),
    labelSmall: medium(base.labelSmall),
  );
}
