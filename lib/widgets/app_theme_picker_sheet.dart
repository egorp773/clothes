import 'package:flutter/material.dart';

import '../core/app_appearance.dart';
import '../core/app_typography.dart';
import 'app_glass_surface.dart';

@immutable
class AppThemePickerResult {
  const AppThemePickerResult.theme(this.theme) : liquidGlassEnabled = null;
  const AppThemePickerResult.liquidGlass(this.liquidGlassEnabled)
    : theme = null;

  final AppThemePreference? theme;
  final bool? liquidGlassEnabled;
}

Future<AppThemePickerResult?> showAppThemePicker({
  required BuildContext context,
  required AppThemePreference value,
  required bool liquidGlassEnabled,
  required ValueChanged<bool> onLiquidGlassChanged,
}) {
  return showModalBottomSheet<AppThemePickerResult>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (context) => AppThemePickerSheet(
      value: value,
      liquidGlassEnabled: liquidGlassEnabled,
      onLiquidGlassChanged: onLiquidGlassChanged,
    ),
  );
}

class AppThemePickerSheet extends StatefulWidget {
  const AppThemePickerSheet({
    super.key,
    required this.value,
    required this.liquidGlassEnabled,
    required this.onLiquidGlassChanged,
  });

  final AppThemePreference value;
  final bool liquidGlassEnabled;
  final ValueChanged<bool> onLiquidGlassChanged;

  @override
  State<AppThemePickerSheet> createState() => _AppThemePickerSheetState();
}

class _AppThemePickerSheetState extends State<AppThemePickerSheet> {
  late bool _liquidGlassEnabled = widget.liquidGlassEnabled;

  @override
  void didUpdateWidget(covariant AppThemePickerSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.liquidGlassEnabled != widget.liquidGlassEnabled) {
      _liquidGlassEnabled = widget.liquidGlassEnabled;
    }
  }

  void _toggleLiquidGlass() {
    final enabled = !_liquidGlassEnabled;
    setState(() => _liquidGlassEnabled = enabled);
    widget.onLiquidGlassChanged(enabled);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    const options = <(AppThemePreference, IconData, String)>[
      (
        AppThemePreference.system,
        Icons.brightness_auto_rounded,
        'Как выбрано на устройстве',
      ),
      (AppThemePreference.light, Icons.light_mode_outlined, 'Чистая и светлая'),
      (AppThemePreference.dark, Icons.dark_mode_outlined, 'Мягкий графит'),
      (AppThemePreference.custom, Icons.palette_outlined, 'Цвета, фон и узоры'),
    ];

    final content = SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.muted.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 17),
            Text(
              'Тема приложения',
              style: TextStyle(
                fontSize: 19,
                fontWeight: AppTypography.bold,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 8),
            _LiquidGlassOption(
              key: const Key('profile-liquid-glass-toggle'),
              enabled: _liquidGlassEnabled,
              onTap: _toggleLiquidGlass,
            ),
            const SizedBox(height: 12),
            for (final option in options)
              AppGlassPressable(
                key: Key('profile-theme-${option.$1.name}'),
                pressedScale: 0.985,
                onTap: () => Navigator.pop(
                  context,
                  AppThemePickerResult.theme(option.$1),
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 62,
                  margin: const EdgeInsets.only(bottom: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: widget.value == option.$1
                        ? palette.surfaceMuted.withValues(alpha: 0.72)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: widget.value == option.$1
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: palette.surfaceMuted,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(option.$2, size: 20, color: palette.ink),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _themePreferenceLabel(option.$1),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: AppTypography.semiBold,
                                color: palette.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              option.$3,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: palette.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.value == option.$1)
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: palette.ink,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 15,
                            color: palette.surface,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (context.appGlass.enabled) {
      return AppGlassSurface(
        density: 0.92,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: content,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: content,
    );
  }
}

class _LiquidGlassOption extends StatelessWidget {
  const _LiquidGlassOption({
    super.key,
    required this.enabled,
    required this.onTap,
  });

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controlColor = isDark
        ? const Color(0xFFF1F1F2)
        : const Color(0xFF27282A);

    return Semantics(
      button: true,
      toggled: enabled,
      label: 'Жидкое стекло',
      child: AppGlassPressable(
        onTap: onTap,
        pressedScale: 0.975,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          height: 78,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            gradient: enabled
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: isDark ? 0.16 : 0.72),
                      palette.surfaceRaised.withValues(alpha: 0.82),
                      const Color(
                        0xFF909093,
                      ).withValues(alpha: isDark ? 0.2 : 0.13),
                    ],
                  )
                : null,
            color: enabled ? null : palette.surfaceMuted,
            borderRadius: BorderRadius.circular(21),
            border: Border.all(
              color: enabled
                  ? Colors.white.withValues(alpha: isDark ? 0.42 : 0.78)
                  : palette.border,
            ),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.24 : 0.1,
                      ),
                      blurRadius: 22,
                      spreadRadius: -10,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              _GlassGlyph(enabled: enabled),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Liquid Glass',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: AppTypography.bold,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      enabled
                          ? 'Включено · мягкое стекло и размытие'
                          : 'Премиальный эффект поверх темы',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: palette.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 46,
                height: 28,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: enabled ? controlColor : palette.border,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: enabled
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.16),
                            blurRadius: 9,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  alignment: enabled
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: enabled
                          ? (isDark ? const Color(0xFF28282A) : Colors.white)
                          : palette.surfaceRaised,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassGlyph extends StatelessWidget {
  const _GlassGlyph({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.translate(
            offset: const Offset(-4, 3),
            child: Transform.rotate(
              angle: -0.12,
              child: Container(
                width: 30,
                height: 34,
                decoration: BoxDecoration(
                  color: palette.ink.withValues(alpha: enabled ? 0.08 : 0.05),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: palette.ink.withValues(alpha: 0.13),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(4, -2),
            child: Container(
              width: 31,
              height: 35,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: enabled ? 0.42 : 0.14),
                    palette.surfaceRaised.withValues(alpha: 0.58),
                  ],
                ),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: Colors.white.withValues(alpha: enabled ? 0.5 : 0.18),
                ),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: palette.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _themePreferenceLabel(AppThemePreference value) => switch (value) {
  AppThemePreference.system => 'Системная',
  AppThemePreference.light => 'Светлая',
  AppThemePreference.dark => 'Тёмная',
  AppThemePreference.custom => 'Своя тема',
};
