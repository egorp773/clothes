import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/app_appearance.dart';

/// A bounded, role-based glass surface.
///
/// The nearest [BackdropGroup] shares backdrop capture between non-overlapping
/// surfaces. Set [grouped] to false for surfaces that genuinely overlap another
/// glass element. Pointer tracking only repaints the local specular painter; it
/// does not claim the gesture arena or distort the content/backdrop.
class AppGlassSurface extends StatefulWidget {
  const AppGlassSurface({
    super.key,
    required this.child,
    this.role = AppGlassRole.floatingControl,
    this.borderRadius,
    this.padding,
    this.density = 0.78,
    this.grouped = true,
    this.interactive,
    this.interactiveGlint = true,
    this.enableRefraction = true,
    this.blendMode = BlendMode.srcOver,
  });

  final Widget child;
  final AppGlassRole role;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;

  /// A compatibility trim for existing call sites. It now adjusts the role
  /// tokens within a narrow range instead of driving opacity directly.
  final double density;

  /// Uses [BackdropFilter.grouped] and the nearest [BackdropGroup]. Disable for
  /// a surface that overlaps another grouped glass surface.
  final bool grouped;

  /// Short alias used by highly interactive surfaces such as navigation.
  /// When provided, it takes precedence over [interactiveGlint].
  final bool? interactive;
  final bool interactiveGlint;

  /// Kept for source compatibility. Refraction is now a non-distorting local
  /// glint, so false simply disables the interactive optical cue.
  final bool enableRefraction;
  final BlendMode blendMode;

  @override
  State<AppGlassSurface> createState() => _AppGlassSurfaceState();
}

class _AppGlassSurfaceState extends State<AppGlassSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glintController;
  final ValueNotifier<Offset?> _glintPosition = ValueNotifier<Offset?>(null);
  int? _activePointer;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _glintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  void _setGlintPosition(Offset position) {
    if (_glintPosition.value == position) return;
    _glintPosition.value = position;
  }

  void _showGlint() {
    if (_glintController.duration == Duration.zero) {
      _glintController.value = 1;
    } else {
      _glintController.forward();
    }
  }

  void _hideGlint() {
    if (_glintController.duration == Duration.zero) {
      _glintController.value = 0;
    } else {
      _glintController.reverse();
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointer = event.pointer;
    _setGlintPosition(event.localPosition);
    _showGlint();
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_activePointer != event.pointer) return;
    _setGlintPosition(event.localPosition);
  }

  void _handlePointerEnd(PointerEvent event) {
    if (_activePointer != event.pointer) return;
    _activePointer = null;
    if (!_hovering) _hideGlint();
  }

  void _handlePointerHover(PointerHoverEvent event) {
    _hovering = true;
    _setGlintPosition(event.localPosition);
    _showGlint();
  }

  void _handlePointerExit(PointerExitEvent event) {
    _hovering = false;
    if (_activePointer == null) _hideGlint();
  }

  @override
  void dispose() {
    _glintController.dispose();
    _glintPosition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glass = context.appGlass;
    final material = glass.materialFor(widget.role);
    final resolvedPadding = widget.padding ?? material.padding;
    final content = Padding(padding: resolvedPadding, child: widget.child);
    if (!glass.enabled) return content;

    final media = MediaQuery.maybeOf(context);
    final reduceMotion = media?.disableAnimations ?? false;
    final highContrast = media?.highContrast ?? false;
    final duration = reduceMotion ? Duration.zero : material.motionDuration;
    if (_glintController.duration != duration) {
      _glintController.duration = duration;
      _glintController.reverseDuration = duration;
    }

    final density = widget.density.clamp(0.0, 1.0).toDouble();
    final opticalScale = (0.9 + density * 0.15) * (highContrast ? 1.08 : 1);
    final radius =
        widget.borderRadius ?? BorderRadius.circular(material.cornerRadius);
    final filterConfig = ImageFilterConfig.blur(
      sigmaX: material.blurSigma,
      sigmaY: material.blurSigma,
      tileMode: TileMode.clamp,
      bounded: true,
    );

    final materialLayer = RepaintBoundary(
      child: CustomPaint(
        painter: _GlassMaterialPainter(
          borderRadius: radius,
          style: glass,
          material: material,
          opticalScale: opticalScale,
          glintPosition: _glintPosition,
          glintAnimation: _glintController,
        ),
      ),
    );
    final glassContent = Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(child: IgnorePointer(child: materialLayer)),
        content,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _GlassRimPainter(
                borderRadius: radius,
                style: glass,
                material: material,
                opticalScale: opticalScale,
              ),
            ),
          ),
        ),
      ],
    );

    final backdrop = widget.grouped
        ? BackdropFilter.grouped(
            filterConfig: filterConfig,
            blendMode: widget.blendMode,
            child: glassContent,
          )
        : BackdropFilter(
            filterConfig: filterConfig,
            blendMode: widget.blendMode,
            child: glassContent,
          );

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: glass.shadowColor.withValues(
              alpha: (material.shadowOpacity * opticalScale).clamp(0, 1),
            ),
            blurRadius: material.shadowBlur,
            spreadRadius: material.shadowSpread,
            offset: material.shadowOffset,
          ),
        ],
      ),
      child: ClipRRect(borderRadius: radius, child: backdrop),
    );

    final tracksPointer =
        (widget.interactive ?? widget.interactiveGlint) &&
        widget.enableRefraction &&
        material.glintOpacity > 0 &&
        !reduceMotion;
    if (tracksPointer) {
      surface = MouseRegion(
        opaque: false,
        onHover: _handlePointerHover,
        onExit: _handlePointerExit,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerEnd,
          onPointerCancel: _handlePointerEnd,
          child: surface,
        ),
      );
    }
    return surface;
  }
}

/// A quiet gel-like press response for controls living on glass.
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
            : Duration(milliseconds: _pressed ? 90 : 240),
        curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

class _GlassMaterialPainter extends CustomPainter {
  _GlassMaterialPainter({
    required this.borderRadius,
    required this.style,
    required this.material,
    required this.opticalScale,
    required this.glintPosition,
    required this.glintAnimation,
  }) : super(repaint: Listenable.merge([glintPosition, glintAnimation]));

  final BorderRadius borderRadius;
  final AppGlassStyle style;
  final AppGlassMaterial material;
  final double opticalScale;
  final ValueNotifier<Offset?> glintPosition;
  final Animation<double> glintAnimation;

  double _alpha(double value) => (value * opticalScale).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final shape = borderRadius.toRRect(rect);

    canvas.drawRRect(
      shape,
      Paint()
        ..isAntiAlias = true
        ..color = style.materialTint.withValues(
          alpha: _alpha(material.tintOpacity),
        ),
    );

    canvas.drawRRect(
      shape,
      Paint()
        ..isAntiAlias = true
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            style.rimColor.withValues(
              alpha: _alpha(material.topHighlightOpacity),
            ),
            style.rimColor.withValues(
              alpha: _alpha(material.topHighlightOpacity * 0.18),
            ),
            Colors.transparent,
          ],
          stops: const [0, 0.3, 0.7],
        ).createShader(rect),
    );

    canvas.drawRRect(
      shape,
      Paint()
        ..isAntiAlias = true
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.transparent,
            style.depthColor.withValues(
              alpha: _alpha(material.bottomDepthOpacity),
            ),
          ],
          stops: const [0, 0.7, 1],
        ).createShader(rect),
    );

    final pointer = glintPosition.value;
    final glintValue = Curves.easeOutCubic.transform(glintAnimation.value);
    if (pointer == null || glintValue <= 0.001) return;
    final center = Alignment(
      (pointer.dx / size.width).clamp(0.0, 1.0) * 2 - 1,
      (pointer.dy / size.height).clamp(0.0, 1.0) * 2 - 1,
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..isAntiAlias = true
        ..shader = RadialGradient(
          center: center,
          radius: material.glintRadius,
          colors: [
            style.accentGlint.withValues(
              alpha: _alpha(material.glintOpacity) * glintValue,
            ),
            style.rimColor.withValues(
              alpha: _alpha(material.glintOpacity * 0.22) * glintValue,
            ),
            Colors.transparent,
          ],
          stops: const [0, 0.36, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _GlassMaterialPainter oldDelegate) {
    return borderRadius != oldDelegate.borderRadius ||
        style != oldDelegate.style ||
        material != oldDelegate.material ||
        opticalScale != oldDelegate.opticalScale ||
        glintPosition != oldDelegate.glintPosition ||
        glintAnimation != oldDelegate.glintAnimation;
  }
}

class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter({
    required this.borderRadius,
    required this.style,
    required this.material,
    required this.opticalScale,
  });

  final BorderRadius borderRadius;
  final AppGlassStyle style;
  final AppGlassMaterial material;
  final double opticalScale;

  double _alpha(double value) => (value * opticalScale).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rimRect = rect.deflate(0.55);
    final rim = borderRadius.toRRect(rimRect);

    canvas.drawRRect(
      rim,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.85
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            style.rimColor.withValues(alpha: _alpha(material.rimOpacity)),
            style.rimColor.withValues(
              alpha: _alpha(material.rimOpacity * 0.38),
            ),
            style.depthColor.withValues(
              alpha: _alpha(material.bottomDepthOpacity * 0.8),
            ),
            style.rimColor.withValues(
              alpha: _alpha(material.rimOpacity * 0.48),
            ),
          ],
          stops: const [0, 0.36, 0.76, 1],
        ).createShader(rect),
    );

    final horizontalInset = (size.shortestSide * 0.2).clamp(10.0, 30.0);
    if (size.width <= horizontalInset * 2) return;
    final highlightRect = Rect.fromLTWH(
      horizontalInset,
      0.8,
      size.width - horizontalInset * 2,
      0.7,
    );
    canvas.drawLine(
      highlightRect.centerLeft,
      highlightRect.centerRight,
      Paint()
        ..strokeWidth = 0.7
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            style.rimColor.withValues(
              alpha: _alpha(material.topHighlightOpacity * 0.72),
            ),
            Colors.transparent,
          ],
        ).createShader(highlightRect),
    );
  }

  @override
  bool shouldRepaint(covariant _GlassRimPainter oldDelegate) {
    return borderRadius != oldDelegate.borderRadius ||
        style != oldDelegate.style ||
        material != oldDelegate.material ||
        opticalScale != oldDelegate.opticalScale;
  }
}
