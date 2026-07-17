import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/app_appearance.dart';

class AppLiquidGlassBackdrop extends StatelessWidget {
  const AppLiquidGlassBackdrop({
    super.key,
    required this.child,
    required this.brightness,
    required this.accent,
    this.baseColor,
  });

  final Widget child;
  final Brightness brightness;
  final Color accent;
  final Color? baseColor;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _LiquidBackdropPainter(
              brightness: brightness,
              accent: accent,
              baseColor: baseColor,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// A single-pass liquid-glass material for floating controls.
///
/// The content palette stays opaque; this widget owns the blur, tint, depth
/// and edge refraction used by navigation and compact control surfaces.
class AppGlassSurface extends StatefulWidget {
  const AppGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.padding = EdgeInsets.zero,
    this.density = 0.78,
    this.enableRefraction = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final double density;
  final bool enableRefraction;

  @override
  State<AppGlassSurface> createState() => _AppGlassSurfaceState();
}

class _AppGlassSurfaceState extends State<AppGlassSurface> {
  static Future<FragmentProgram>? _lensProgram;
  FragmentShader? _lensShader;
  bool _lensRequested = false;

  bool get _supportsLensShader =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      ImageFilter.isShaderFilterSupported;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_lensRequested &&
        widget.enableRefraction &&
        context.appGlass.enabled &&
        _supportsLensShader) {
      _lensRequested = true;
      _loadLensShader();
    }
  }

  Future<void> _loadLensShader() async {
    try {
      final program = await (_lensProgram ??= FragmentProgram.fromAsset(
        'shaders/liquid_glass_lens.frag',
      ));
      if (!mounted) return;
      setState(() => _lensShader = program.fragmentShader());
    } catch (_) {
      // The layered blur material remains the cross-platform fallback.
    }
  }

  @override
  void dispose() {
    _lensShader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glass = context.appGlass;
    if (!glass.enabled) return widget.child;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final media = MediaQuery.maybeOf(context);
    final strength = (media?.highContrast ?? false)
        ? 1.0
        : widget.density.clamp(0.0, 1.0).toDouble();
    final blur = ImageFilter.blur(
      sigmaX: glass.blur,
      sigmaY: glass.blur,
      tileMode: TileMode.mirror,
    );
    ImageFilter filter = blur;
    final lensShader = _lensShader;
    if (widget.enableRefraction &&
        lensShader != null &&
        ImageFilter.isShaderFilterSupported) {
      lensShader
        ..setFloat(2, 0.72 + strength * 0.28)
        ..setFloat(3, isDark ? 0.7 : 0.52);
      filter = ImageFilter.compose(
        outer: ImageFilter.shader(lensShader),
        inner: blur,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        boxShadow: [
          BoxShadow(
            color: glass.shadowColor.withValues(alpha: isDark ? 0.42 : 0.16),
            blurRadius: 32,
            spreadRadius: -8,
            offset: const Offset(0, 15),
          ),
          BoxShadow(
            color: glass.shadowColor.withValues(alpha: isDark ? 0.24 : 0.09),
            blurRadius: 9,
            spreadRadius: -3,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: BackdropFilter(
          filter: filter,
          child: CustomPaint(
            painter: _GlassMaterialPainter(
              borderRadius: widget.borderRadius,
              style: glass,
              isDark: isDark,
              density: strength,
            ),
            foregroundPainter: _GlassRimPainter(
              borderRadius: widget.borderRadius,
              style: glass,
              isDark: isDark,
              density: strength,
            ),
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// A quiet gel-like press response for controls living on glass.
///
/// It deliberately has no splash, focus ring, or color flash: the control
/// compresses and returns with a soft spring while its glass remains intact.
class AppGlassPressable extends StatefulWidget {
  const AppGlassPressable({
    super.key,
    required this.onTap,
    required this.child,
    this.pressedScale = 0.94,
    this.behavior = HitTestBehavior.opaque,
  });

  final VoidCallback onTap;
  final Widget child;
  final double pressedScale;
  final HitTestBehavior behavior;

  @override
  State<AppGlassPressable> createState() => _AppGlassPressableState();
}

class _AppGlassPressableState extends State<AppGlassPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1,
        duration: reduceMotion
            ? Duration.zero
            : Duration(milliseconds: _pressed ? 90 : 260),
        curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

class _GlassMaterialPainter extends CustomPainter {
  const _GlassMaterialPainter({
    required this.borderRadius,
    required this.style,
    required this.isDark,
    required this.density,
  });

  final BorderRadius borderRadius;
  final AppGlassStyle style;
  final bool isDark;
  final double density;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final shape = borderRadius.toRRect(rect);
    final materialAlpha = isDark ? 0.68 + density * 0.22 : 0.72 + density * 0.2;

    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawRRect(
      shape,
      Paint()..color = style.materialTint.withValues(alpha: materialAlpha),
    );

    // Directional illumination gives the material volume while preserving a
    // neutral base and dependable contrast for the content above it.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            style.rimColor.withValues(alpha: isDark ? 0.18 : 0.34),
            style.rimColor.withValues(alpha: isDark ? 0.045 : 0.08),
            Colors.transparent,
            style.depthColor.withValues(alpha: isDark ? 0.2 : 0.08),
          ],
          stops: const [0, 0.24, 0.58, 1],
        ).createShader(rect),
    );

    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.82, -1.08),
          radius: 1.18,
          colors: [
            style.rimColor.withValues(alpha: isDark ? 0.17 : 0.3),
            style.rimColor.withValues(alpha: isDark ? 0.035 : 0.055),
            Colors.transparent,
          ],
          stops: const [0, 0.38, 1],
        ).createShader(rect),
    );

    // A tiny desaturated glint hints at the selected accent. It never colors
    // the whole material and remains subordinate to the neutral highlights.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(1.05, -1.12),
          radius: 0.58,
          colors: [
            style.accentGlint.withValues(alpha: isDark ? 0.045 : 0.032),
            Colors.transparent,
          ],
        ).createShader(rect),
    );

    // Opposing luminance close to the lower edge simulates displacement of
    // the blurred backdrop without a second BackdropFilter.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(-0.7, 0.55),
          end: Alignment.bottomRight,
          colors: [
            Colors.transparent,
            style.depthColor.withValues(alpha: isDark ? 0.055 : 0.035),
            style.rimColor.withValues(alpha: isDark ? 0.035 : 0.08),
          ],
          stops: const [0, 0.76, 1],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlassMaterialPainter oldDelegate) =>
      borderRadius != oldDelegate.borderRadius ||
      style != oldDelegate.style ||
      isDark != oldDelegate.isDark ||
      density != oldDelegate.density;
}

class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter({
    required this.borderRadius,
    required this.style,
    required this.isDark,
    required this.density,
  });

  final BorderRadius borderRadius;
  final AppGlassStyle style;
  final bool isDark;
  final double density;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final outerRect = rect.deflate(0.55);
    final innerRect = rect.deflate(1.75);
    final rimStrength = 0.78 + density * 0.22;

    canvas.drawRRect(
      borderRadius.toRRect(outerRect),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.05
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            style.rimColor.withValues(
              alpha: (isDark ? 0.62 : 0.92) * rimStrength,
            ),
            style.rimColor.withValues(alpha: isDark ? 0.2 : 0.42),
            style.depthColor.withValues(alpha: isDark ? 0.42 : 0.16),
            style.rimColor.withValues(alpha: isDark ? 0.24 : 0.64),
          ],
          stops: const [0, 0.32, 0.72, 1],
        ).createShader(rect),
    );

    // The opposing inner rim is the inexpensive refraction cue: a bright
    // leading edge followed by a darker displaced edge.
    canvas.drawRRect(
      borderRadius.toRRect(innerRect),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            style.rimColor.withValues(alpha: isDark ? 0.2 : 0.42),
            Colors.transparent,
            style.depthColor.withValues(alpha: isDark ? 0.28 : 0.11),
          ],
          stops: const [0, 0.48, 1],
        ).createShader(rect),
    );

    final highlightInset = (size.shortestSide * 0.13)
        .clamp(9.0, 24.0)
        .toDouble();
    if (size.width > highlightInset * 2) {
      final highlightRect = Rect.fromLTWH(
        highlightInset,
        0.9,
        size.width - highlightInset * 2,
        1,
      );
      canvas.drawLine(
        highlightRect.centerLeft,
        highlightRect.centerRight,
        Paint()
          ..strokeWidth = 1
          ..shader = LinearGradient(
            colors: [
              Colors.transparent,
              style.rimColor.withValues(alpha: isDark ? 0.72 : 0.96),
              Colors.transparent,
            ],
          ).createShader(highlightRect),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlassRimPainter oldDelegate) =>
      borderRadius != oldDelegate.borderRadius ||
      style != oldDelegate.style ||
      isDark != oldDelegate.isDark ||
      density != oldDelegate.density;
}

class _LiquidBackdropPainter extends CustomPainter {
  const _LiquidBackdropPainter({
    required this.brightness,
    required this.accent,
    this.baseColor,
  });

  final Brightness brightness;
  final Color accent;
  final Color? baseColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final isDark = brightness == Brightness.dark;
    final neutral = isDark ? const Color(0xFF151619) : const Color(0xFFF2F3F5);
    final foundation = baseColor == null
        ? neutral
        : Color.lerp(baseColor!.withValues(alpha: 1), neutral, 0.2)!;
    final lifted = Color.lerp(
      foundation,
      isDark ? const Color(0xFF303136) : Colors.white,
      isDark ? 0.2 : 0.34,
    )!;
    final grounded = Color.lerp(
      foundation,
      isDark ? const Color(0xFF08090B) : const Color(0xFFD8DADF),
      isDark ? 0.28 : 0.16,
    )!;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [lifted, foundation, grounded],
          stops: const [0, 0.54, 1],
        ).createShader(rect),
    );

    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.62, -0.95),
          radius: 1.04,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.065 : 0.36),
            Colors.transparent,
          ],
          stops: const [0, 1],
        ).createShader(rect),
    );

    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.72, 1.08),
          radius: 0.94,
          colors: [
            Colors.black.withValues(alpha: isDark ? 0.16 : 0.045),
            Colors.transparent,
          ],
        ).createShader(rect),
    );

    final neutralAccent = Color.lerp(
      isDark ? const Color(0xFFF0F1F3) : const Color(0xFF74767B),
      accent.withValues(alpha: 1),
      0.05,
    )!;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(1.12, -1.12),
          radius: 0.42,
          colors: [
            neutralAccent.withValues(alpha: isDark ? 0.025 : 0.018),
            Colors.transparent,
          ],
        ).createShader(rect),
    );

    final grain = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(
        alpha: isDark ? 0.012 : 0.008,
      );
    for (double y = 11; y < size.height; y += 23) {
      final shift = ((y / 23).round().isEven) ? 0.0 : 9.0;
      for (double x = 7 + shift; x < size.width; x += 23) {
        canvas.drawCircle(Offset(x, y), 0.45, grain);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LiquidBackdropPainter oldDelegate) =>
      brightness != oldDelegate.brightness ||
      accent != oldDelegate.accent ||
      baseColor != oldDelegate.baseColor;
}
