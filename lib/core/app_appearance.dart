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

enum AppGlassRole {
  navigation,
  toolbar,
  floatingControl,
  card,
  sheet,
  input,
  compactButton,
  overlay,
}

/// Optical and motion tokens for one kind of glass surface.
///
/// Large reading surfaces intentionally use a denser tint and a quieter rim;
/// compact floating controls retain more of the backdrop and slightly more
/// edge light. This keeps glass a hierarchy rather than a global skin.
@immutable
class AppGlassMaterial {
  const AppGlassMaterial({
    required this.blurSigma,
    required this.tintOpacity,
    required this.rimOpacity,
    required this.topHighlightOpacity,
    required this.bottomDepthOpacity,
    required this.shadowOpacity,
    required this.shadowBlur,
    required this.shadowSpread,
    required this.shadowOffset,
    required this.cornerRadius,
    required this.padding,
    required this.motionDuration,
    required this.glintOpacity,
    required this.glintRadius,
  });

  const AppGlassMaterial.disabledGeometry({
    this.cornerRadius = 0,
    this.padding = EdgeInsets.zero,
    this.motionDuration = Duration.zero,
  }) : blurSigma = 0,
       tintOpacity = 0,
       rimOpacity = 0,
       topHighlightOpacity = 0,
       bottomDepthOpacity = 0,
       shadowOpacity = 0,
       shadowBlur = 0,
       shadowSpread = 0,
       shadowOffset = Offset.zero,
       glintOpacity = 0,
       glintRadius = 0;

  final double blurSigma;
  final double tintOpacity;
  final double rimOpacity;
  final double topHighlightOpacity;
  final double bottomDepthOpacity;
  final double shadowOpacity;
  final double shadowBlur;
  final double shadowSpread;
  final Offset shadowOffset;
  final double cornerRadius;
  final EdgeInsets padding;
  final Duration motionDuration;
  final double glintOpacity;
  final double glintRadius;

  static const disabled = AppGlassMaterial.disabledGeometry();

  AppGlassMaterial lerp(AppGlassMaterial other, double t) {
    return AppGlassMaterial(
      blurSigma: blurSigma + (other.blurSigma - blurSigma) * t,
      tintOpacity: tintOpacity + (other.tintOpacity - tintOpacity) * t,
      rimOpacity: rimOpacity + (other.rimOpacity - rimOpacity) * t,
      topHighlightOpacity:
          topHighlightOpacity +
          (other.topHighlightOpacity - topHighlightOpacity) * t,
      bottomDepthOpacity:
          bottomDepthOpacity +
          (other.bottomDepthOpacity - bottomDepthOpacity) * t,
      shadowOpacity: shadowOpacity + (other.shadowOpacity - shadowOpacity) * t,
      shadowBlur: shadowBlur + (other.shadowBlur - shadowBlur) * t,
      shadowSpread: shadowSpread + (other.shadowSpread - shadowSpread) * t,
      shadowOffset: Offset.lerp(shadowOffset, other.shadowOffset, t)!,
      cornerRadius: cornerRadius + (other.cornerRadius - cornerRadius) * t,
      padding: EdgeInsets.lerp(padding, other.padding, t)!,
      motionDuration: Duration(
        microseconds:
            (motionDuration.inMicroseconds +
                    (other.motionDuration.inMicroseconds -
                            motionDuration.inMicroseconds) *
                        t)
                .round(),
      ),
      glintOpacity: glintOpacity + (other.glintOpacity - glintOpacity) * t,
      glintRadius: glintRadius + (other.glintRadius - glintRadius) * t,
    );
  }
}

@immutable
class AppGlassStyle extends ThemeExtension<AppGlassStyle> {
  const AppGlassStyle({
    required this.enabled,
    required this.materialTint,
    required this.rimColor,
    required this.depthColor,
    required this.shadowColor,
    required this.accentGlint,
    required this.navigation,
    required this.toolbar,
    required this.floatingControl,
    required this.card,
    required this.sheet,
    required this.input,
    required this.compactButton,
    required this.overlay,
  });

  final bool enabled;
  final Color materialTint;
  final Color rimColor;
  final Color depthColor;
  final Color shadowColor;
  final Color accentGlint;
  final AppGlassMaterial navigation;
  final AppGlassMaterial toolbar;
  final AppGlassMaterial floatingControl;
  final AppGlassMaterial card;
  final AppGlassMaterial sheet;
  final AppGlassMaterial input;
  final AppGlassMaterial compactButton;
  final AppGlassMaterial overlay;

  /// Kept for source compatibility with callers that only need a representative
  /// blur value. New surfaces should select an explicit [AppGlassRole].
  double get blur => floatingControl.blurSigma;

  static const disabled = AppGlassStyle(
    enabled: false,
    materialTint: Colors.transparent,
    rimColor: Colors.transparent,
    depthColor: Colors.transparent,
    shadowColor: Colors.transparent,
    accentGlint: Colors.transparent,
    navigation: AppGlassMaterial.disabledGeometry(
      cornerRadius: 29,
      motionDuration: Duration(milliseconds: 280),
    ),
    toolbar: AppGlassMaterial.disabledGeometry(
      cornerRadius: 22,
      motionDuration: Duration(milliseconds: 240),
    ),
    floatingControl: AppGlassMaterial.disabledGeometry(
      cornerRadius: 22,
      motionDuration: Duration(milliseconds: 230),
    ),
    card: AppGlassMaterial.disabledGeometry(
      cornerRadius: 24,
      motionDuration: Duration(milliseconds: 220),
    ),
    sheet: AppGlassMaterial.disabledGeometry(
      cornerRadius: 30,
      motionDuration: Duration(milliseconds: 300),
    ),
    input: AppGlassMaterial.disabledGeometry(
      cornerRadius: 24,
      padding: EdgeInsets.symmetric(horizontal: 2),
      motionDuration: Duration(milliseconds: 200),
    ),
    compactButton: AppGlassMaterial.disabledGeometry(
      cornerRadius: 17,
      motionDuration: Duration(milliseconds: 210),
    ),
    overlay: AppGlassMaterial.disabledGeometry(
      cornerRadius: 22,
      motionDuration: Duration(milliseconds: 260),
    ),
  );

  factory AppGlassStyle.liquid({
    required Brightness brightness,
    required Color accent,
  }) {
    final isDark = brightness == Brightness.dark;
    final neutralGlint = isDark
        ? const Color(0xFFF1F2F4)
        : const Color(0xFF747980);
    final tint = isDark ? const Color(0xFF1B1D21) : const Color(0xFFF7F8FA);

    AppGlassMaterial material({
      required double blur,
      required double tintOpacity,
      required double rimOpacity,
      required double highlightOpacity,
      required double depthOpacity,
      required double shadowOpacity,
      required double shadowBlur,
      required double shadowSpread,
      required Offset shadowOffset,
      required double radius,
      required Duration duration,
      required double glintOpacity,
      required double glintRadius,
      EdgeInsets padding = EdgeInsets.zero,
    }) {
      return AppGlassMaterial(
        blurSigma: blur,
        tintOpacity: tintOpacity,
        rimOpacity: rimOpacity,
        topHighlightOpacity: highlightOpacity,
        bottomDepthOpacity: depthOpacity,
        shadowOpacity: shadowOpacity,
        shadowBlur: shadowBlur,
        shadowSpread: shadowSpread,
        shadowOffset: shadowOffset,
        cornerRadius: radius,
        padding: padding,
        motionDuration: duration,
        glintOpacity: glintOpacity,
        glintRadius: glintRadius,
      );
    }

    return AppGlassStyle(
      enabled: true,
      materialTint: tint,
      rimColor: isDark ? const Color(0xFFF4F5F7) : Colors.white,
      depthColor: isDark ? Colors.black : const Color(0xFF30343A),
      shadowColor: isDark ? Colors.black : const Color(0xFF1B2028),
      // The accent contributes only a small, desaturated specular cue.
      accentGlint: Color.lerp(neutralGlint, accent.withValues(alpha: 1), 0.08)!,
      navigation: material(
        blur: 18,
        tintOpacity: isDark ? 0.38 : 0.34,
        rimOpacity: isDark ? 0.24 : 0.27,
        highlightOpacity: isDark ? 0.24 : 0.32,
        depthOpacity: isDark ? 0.16 : 0.09,
        shadowOpacity: isDark ? 0.28 : 0.13,
        shadowBlur: 26,
        shadowSpread: -8,
        shadowOffset: const Offset(0, 12),
        radius: 29,
        duration: const Duration(milliseconds: 280),
        glintOpacity: isDark ? 0.11 : 0.13,
        glintRadius: 0.72,
      ),
      toolbar: material(
        blur: 15,
        tintOpacity: isDark ? 0.43 : 0.4,
        rimOpacity: isDark ? 0.2 : 0.22,
        highlightOpacity: isDark ? 0.2 : 0.26,
        depthOpacity: isDark ? 0.13 : 0.075,
        shadowOpacity: isDark ? 0.2 : 0.09,
        shadowBlur: 20,
        shadowSpread: -7,
        shadowOffset: const Offset(0, 8),
        radius: 22,
        duration: const Duration(milliseconds: 240),
        glintOpacity: isDark ? 0.075 : 0.09,
        glintRadius: 0.66,
      ),
      floatingControl: material(
        blur: 13,
        tintOpacity: isDark ? 0.46 : 0.42,
        rimOpacity: isDark ? 0.22 : 0.24,
        highlightOpacity: isDark ? 0.22 : 0.28,
        depthOpacity: isDark ? 0.14 : 0.08,
        shadowOpacity: isDark ? 0.23 : 0.11,
        shadowBlur: 19,
        shadowSpread: -6,
        shadowOffset: const Offset(0, 8),
        radius: 22,
        duration: const Duration(milliseconds: 230),
        glintOpacity: isDark ? 0.1 : 0.115,
        glintRadius: 0.62,
      ),
      card: material(
        blur: 10,
        tintOpacity: isDark ? 0.56 : 0.53,
        rimOpacity: isDark ? 0.14 : 0.16,
        highlightOpacity: isDark ? 0.14 : 0.19,
        depthOpacity: isDark ? 0.1 : 0.06,
        shadowOpacity: isDark ? 0.16 : 0.07,
        shadowBlur: 16,
        shadowSpread: -6,
        shadowOffset: const Offset(0, 7),
        radius: 24,
        duration: const Duration(milliseconds: 220),
        glintOpacity: isDark ? 0.05 : 0.06,
        glintRadius: 0.8,
      ),
      sheet: material(
        blur: 20,
        tintOpacity: isDark ? 0.68 : 0.64,
        rimOpacity: isDark ? 0.15 : 0.17,
        highlightOpacity: isDark ? 0.16 : 0.2,
        depthOpacity: isDark ? 0.11 : 0.06,
        shadowOpacity: isDark ? 0.28 : 0.14,
        shadowBlur: 30,
        shadowSpread: -10,
        shadowOffset: const Offset(0, -3),
        radius: 30,
        duration: const Duration(milliseconds: 300),
        glintOpacity: isDark ? 0.035 : 0.045,
        glintRadius: 0.95,
      ),
      input: material(
        blur: 11,
        tintOpacity: isDark ? 0.64 : 0.61,
        rimOpacity: isDark ? 0.13 : 0.15,
        highlightOpacity: isDark ? 0.13 : 0.17,
        depthOpacity: isDark ? 0.09 : 0.05,
        shadowOpacity: isDark ? 0.12 : 0.055,
        shadowBlur: 12,
        shadowSpread: -5,
        shadowOffset: const Offset(0, 5),
        radius: 24,
        duration: const Duration(milliseconds: 200),
        glintOpacity: isDark ? 0.035 : 0.045,
        glintRadius: 0.72,
        padding: const EdgeInsets.symmetric(horizontal: 2),
      ),
      compactButton: material(
        blur: 10,
        tintOpacity: isDark ? 0.48 : 0.45,
        rimOpacity: isDark ? 0.2 : 0.22,
        highlightOpacity: isDark ? 0.2 : 0.25,
        depthOpacity: isDark ? 0.12 : 0.07,
        shadowOpacity: isDark ? 0.18 : 0.08,
        shadowBlur: 14,
        shadowSpread: -5,
        shadowOffset: const Offset(0, 6),
        radius: 17,
        duration: const Duration(milliseconds: 210),
        glintOpacity: isDark ? 0.09 : 0.105,
        glintRadius: 0.58,
      ),
      overlay: material(
        blur: 17,
        tintOpacity: isDark ? 0.58 : 0.55,
        rimOpacity: isDark ? 0.17 : 0.19,
        highlightOpacity: isDark ? 0.17 : 0.22,
        depthOpacity: isDark ? 0.11 : 0.065,
        shadowOpacity: isDark ? 0.26 : 0.12,
        shadowBlur: 24,
        shadowSpread: -8,
        shadowOffset: const Offset(0, 10),
        radius: 22,
        duration: const Duration(milliseconds: 260),
        glintOpacity: isDark ? 0.06 : 0.075,
        glintRadius: 0.78,
      ),
    );
  }

  AppGlassMaterial materialFor(AppGlassRole role) => switch (role) {
    AppGlassRole.navigation => navigation,
    AppGlassRole.toolbar => toolbar,
    AppGlassRole.floatingControl => floatingControl,
    AppGlassRole.card => card,
    AppGlassRole.sheet => sheet,
    AppGlassRole.input => input,
    AppGlassRole.compactButton => compactButton,
    AppGlassRole.overlay => overlay,
  };

  @override
  AppGlassStyle copyWith({
    bool? enabled,
    Color? materialTint,
    Color? rimColor,
    Color? depthColor,
    Color? shadowColor,
    Color? accentGlint,
    AppGlassMaterial? navigation,
    AppGlassMaterial? toolbar,
    AppGlassMaterial? floatingControl,
    AppGlassMaterial? card,
    AppGlassMaterial? sheet,
    AppGlassMaterial? input,
    AppGlassMaterial? compactButton,
    AppGlassMaterial? overlay,
  }) => AppGlassStyle(
    enabled: enabled ?? this.enabled,
    materialTint: materialTint ?? this.materialTint,
    rimColor: rimColor ?? this.rimColor,
    depthColor: depthColor ?? this.depthColor,
    shadowColor: shadowColor ?? this.shadowColor,
    accentGlint: accentGlint ?? this.accentGlint,
    navigation: navigation ?? this.navigation,
    toolbar: toolbar ?? this.toolbar,
    floatingControl: floatingControl ?? this.floatingControl,
    card: card ?? this.card,
    sheet: sheet ?? this.sheet,
    input: input ?? this.input,
    compactButton: compactButton ?? this.compactButton,
    overlay: overlay ?? this.overlay,
  );

  @override
  AppGlassStyle lerp(covariant AppGlassStyle? other, double t) {
    if (other == null) return this;
    return AppGlassStyle(
      // Keep the layer alive while transitioning to or from disabled so the
      // optical tokens can fade continuously, but honor both exact endpoints.
      // AnimatedTheme may keep ThemeData.lerp(begin, end, 1) as its final
      // value, so `enabled || other.enabled` would make ON -> OFF stick on.
      enabled: t <= 0
          ? enabled
          : t >= 1
          ? other.enabled
          : enabled || other.enabled,
      materialTint: Color.lerp(materialTint, other.materialTint, t)!,
      rimColor: Color.lerp(rimColor, other.rimColor, t)!,
      depthColor: Color.lerp(depthColor, other.depthColor, t)!,
      shadowColor: Color.lerp(shadowColor, other.shadowColor, t)!,
      accentGlint: Color.lerp(accentGlint, other.accentGlint, t)!,
      navigation: navigation.lerp(other.navigation, t),
      toolbar: toolbar.lerp(other.toolbar, t),
      floatingControl: floatingControl.lerp(other.floatingControl, t),
      card: card.lerp(other.card, t),
      sheet: sheet.lerp(other.sheet, t),
      input: input.lerp(other.input, t),
      compactButton: compactButton.lerp(other.compactButton, t),
      overlay: overlay.lerp(other.overlay, t),
    );
  }
}

extension AppGlassContext on BuildContext {
  AppGlassStyle get appGlass =>
      Theme.of(this).extension<AppGlassStyle>() ?? AppGlassStyle.disabled;
}

/// Separates the single app backdrop from opaque content colors.
///
/// Wallpaper pages use a transparent scaffold so the root image/pattern is not
/// tinted a second time. [contentColor] remains opaque for reading surfaces.
@immutable
class AppBackdropStyle extends ThemeExtension<AppBackdropStyle> {
  const AppBackdropStyle({
    required this.hasWallpaper,
    required this.rootColor,
    required this.scaffoldColor,
    required this.contentColor,
  });

  final bool hasWallpaper;
  final Color rootColor;
  final Color scaffoldColor;
  final Color contentColor;

  factory AppBackdropStyle.resolve({
    required AppAppearanceSettings settings,
    required AppPalette palette,
  }) {
    final hasWallpaper =
        settings.theme == AppThemePreference.custom &&
        settings.background != AppBackgroundStyle.plain;
    final rootColor = settings.theme == AppThemePreference.custom
        ? settings.backgroundColor
        : palette.page;
    return AppBackdropStyle(
      hasWallpaper: hasWallpaper,
      rootColor: rootColor.withValues(alpha: 1),
      scaffoldColor: hasWallpaper
          ? Colors.transparent
          : rootColor.withValues(alpha: 1),
      contentColor: palette.page.withValues(alpha: 1),
    );
  }

  @override
  AppBackdropStyle copyWith({
    bool? hasWallpaper,
    Color? rootColor,
    Color? scaffoldColor,
    Color? contentColor,
  }) => AppBackdropStyle(
    hasWallpaper: hasWallpaper ?? this.hasWallpaper,
    rootColor: rootColor ?? this.rootColor,
    scaffoldColor: scaffoldColor ?? this.scaffoldColor,
    contentColor: contentColor ?? this.contentColor,
  );

  @override
  AppBackdropStyle lerp(covariant AppBackdropStyle? other, double t) {
    if (other == null) return this;
    return AppBackdropStyle(
      hasWallpaper: t < 0.5 ? hasWallpaper : other.hasWallpaper,
      rootColor: Color.lerp(rootColor, other.rootColor, t)!,
      scaffoldColor: Color.lerp(scaffoldColor, other.scaffoldColor, t)!,
      contentColor: Color.lerp(contentColor, other.contentColor, t)!,
    );
  }
}

extension AppBackdropContext on BuildContext {
  AppBackdropStyle get appBackdrop =>
      Theme.of(this).extension<AppBackdropStyle>() ??
      AppBackdropStyle(
        hasWallpaper: false,
        rootColor: appPalette.page.withValues(alpha: 1),
        scaffoldColor: appPalette.page.withValues(alpha: 1),
        contentColor: appPalette.page.withValues(alpha: 1),
      );
}

ThemeData buildAppTheme(
  Brightness brightness, {
  AppAppearanceSettings settings = const AppAppearanceSettings(),
}) {
  final isGlass = settings.liquidGlassEnabled;
  final effectiveBrightness = brightness;
  final isDark = effectiveBrightness == Brightness.dark;
  final palette = _resolvePalette(effectiveBrightness, settings);
  final backdrop = AppBackdropStyle.resolve(
    settings: settings,
    palette: palette,
  );
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
    scaffoldBackgroundColor: backdrop.scaffoldColor,
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
      backgroundColor: backdrop.scaffoldColor,
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
      backdrop,
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
      page: hasWallpaper
          ? mixed(base.page, isDark ? 0.23 : 0.1).withValues(alpha: 1)
          : settings.backgroundColor.withValues(alpha: 1),
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
