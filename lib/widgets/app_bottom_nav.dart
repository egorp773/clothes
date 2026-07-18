import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/app_appearance.dart';
import 'app_glass_surface.dart';

/// The app's floating navigation capsule.
///
/// [compactListenable] changes only the navigation subtree. The catalog can
/// therefore react to scroll direction without rebuilding the shell or its
/// indexed pages on every scroll update.
class AppBottomNav extends StatefulWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.onCreateTap,
    this.compactListenable,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onCreateTap;
  final ValueListenable<bool>? compactListenable;

  @override
  State<AppBottomNav> createState() => _AppBottomNavState();
}

class _AppBottomNavState extends State<AppBottomNav>
    with SingleTickerProviderStateMixin {
  late final AnimationController _collapseController;

  bool get _shouldBeCompact => widget.compactListenable?.value ?? false;

  @override
  void initState() {
    super.initState();
    _collapseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: _shouldBeCompact ? 1 : 0,
    );
    widget.compactListenable?.addListener(_handleCompactChanged);
  }

  @override
  void didUpdateWidget(covariant AppBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.compactListenable != widget.compactListenable) {
      oldWidget.compactListenable?.removeListener(_handleCompactChanged);
      widget.compactListenable?.addListener(_handleCompactChanged);
      _handleCompactChanged();
    }
  }

  void _handleCompactChanged() {
    if (!mounted) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final target = _shouldBeCompact ? 1.0 : 0.0;
    if (reduceMotion) {
      _collapseController.value = target;
      return;
    }
    _collapseController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    widget.compactListenable?.removeListener(_handleCompactChanged);
    _collapseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const Key('app-bottom-nav'),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: SizedBox(
          // Keep the Scaffold bottom-navigation slot stable. Only the capsule
          // inside this box changes height, so scroll collapse does not
          // relayout the page body on every animation tick.
          height: 60,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return AnimatedBuilder(
                animation: _collapseController,
                builder: (context, _) {
                  // [animateTo] already applies the motion curve. Transforming
                  // the value again makes the capsule snap almost fully closed
                  // halfway through the transition and then crawl to its target.
                  final progress = _collapseController.value;
                  final availableWidth = constraints.maxWidth;
                  final expandedWidth = (availableWidth - 24)
                      .clamp(280.0, 430.0)
                      .toDouble();
                  final compactWidth = (availableWidth - 56)
                      .clamp(264.0, 340.0)
                      .toDouble();
                  final width = lerpDouble(
                    expandedWidth,
                    compactWidth,
                    progress,
                  )!;
                  final height = lerpDouble(60, 52, progress)!;

                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      key: const Key('app-bottom-nav-panel'),
                      width: width,
                      height: height,
                      child: AppGlassSurface(
                        role: AppGlassRole.navigation,
                        interactive: true,
                        borderRadius: BorderRadius.circular(999),
                        child: _NavigationMaterial(
                          progress: progress,
                          currentIndex: widget.currentIndex,
                          onTabSelected: widget.onTabSelected,
                          onCreateTap: widget.onCreateTap,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavigationMaterial extends StatefulWidget {
  const _NavigationMaterial({
    required this.progress,
    required this.currentIndex,
    required this.onTabSelected,
    required this.onCreateTap,
  });

  final double progress;
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onCreateTap;

  @override
  State<_NavigationMaterial> createState() => _NavigationMaterialState();
}

class _NavigationMaterialState extends State<_NavigationMaterial>
    with SingleTickerProviderStateMixin {
  static const _itemCount = 5;
  static const _createIndex = 2;

  late final AnimationController _settleController;
  late final ValueNotifier<_NavLensVisual> _lens;
  late _NavLensVisual _settleBegin;
  double _settleTarget = 0;
  int _visualIndex = 0;
  int? _activePointer;
  Offset? _pointerOrigin;
  Duration? _lastMoveTime;
  double _filteredVelocity = 0;
  bool _dragging = false;

  static double _centerForIndex(int index) => (index + 0.5) / _itemCount;

  int _safeIndex(int index) => index.clamp(0, _itemCount - 1).toInt();

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    _visualIndex = _safeIndex(widget.currentIndex);
    _lens = ValueNotifier<_NavLensVisual>(
      _NavLensVisual.resting(_centerForIndex(_visualIndex)),
    );
    _settleBegin = _lens.value;
    _settleTarget = _lens.value.position;
    _settleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addListener(_tickSettleAnimation);
  }

  @override
  void didUpdateWidget(covariant _NavigationMaterial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex &&
        _activePointer == null) {
      _setVisualIndex(_safeIndex(widget.currentIndex));
      _settleToIndex(widget.currentIndex);
    }
  }

  void _tickSettleAnimation() {
    final raw = _settleController.value;
    final travel = Curves.easeOutBack.transform(raw);
    final decay = Curves.easeOutCubic.transform(raw);
    final distance = _settleTarget - _settleBegin.position;
    final travelPeak = 4 * raw * (1 - raw);
    final travelStretch = (distance.abs() * 1.45 * travelPeak).clamp(0.0, 0.7);
    _lens.value = _NavLensVisual(
      position: lerpDouble(
        _settleBegin.position,
        _settleTarget,
        travel,
      )!.clamp(0.045, 0.955),
      stretch: (lerpDouble(_settleBegin.stretch, 0, decay)! + travelStretch)
          .clamp(0.0, 1.0),
      direction: distance.abs() < 0.001
          ? _settleBegin.direction
          : distance.sign,
      pressure: lerpDouble(_settleBegin.pressure, 0, decay)!,
    );
  }

  double _fractionFor(Offset position) {
    final width = context.size?.width ?? 1;
    return (position.dx / width).clamp(0.055, 0.945);
  }

  int _indexForFraction(double fraction) {
    return (fraction * _itemCount).floor().clamp(0, _itemCount - 1);
  }

  int _releaseIndexForFraction(double fraction) {
    final nearest = _indexForFraction(fraction);
    if (nearest != _createIndex) return nearest;
    if (_filteredVelocity > 24 || _lens.value.direction > 0) return 3;
    if (_filteredVelocity < -24 || _lens.value.direction < 0) return 1;
    final current = _safeIndex(widget.currentIndex);
    return current == _createIndex ? 1 : current;
  }

  void _setVisualIndex(int index) {
    final safeIndex = _safeIndex(index);
    if (_visualIndex == safeIndex || !mounted) return;
    setState(() => _visualIndex = safeIndex);
  }

  void _settleToIndex(int index) {
    final safeIndex = _safeIndex(index);
    final target = _centerForIndex(safeIndex);
    _settleController.stop();
    if (_reduceMotion) {
      _lens.value = _NavLensVisual.resting(target);
      return;
    }
    _settleBegin = _lens.value;
    _settleTarget = target;
    final travel = (target - _settleBegin.position).abs();
    _settleController.duration = Duration(
      milliseconds: (215 + travel * 210).round().clamp(220, 360),
    );
    _settleController.forward(from: 0);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _settleController.stop();
    _activePointer = event.pointer;
    _pointerOrigin = event.localPosition;
    _lastMoveTime = event.timeStamp;
    _filteredVelocity = 0;
    _dragging = false;
    _lens.value = _lens.value.copyWith(pressure: 1, stretch: 0);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_activePointer != event.pointer || _pointerOrigin == null) return;
    final travel = event.localPosition - _pointerOrigin!;
    if (!_dragging) {
      // Match Flutter's tap slop. Once this activates, the child tap recognizer
      // has also yielded, so releasing cannot fire a tap and a drag selection.
      if (travel.dx.abs() <= kTouchSlop ||
          travel.dx.abs() < travel.dy.abs() * 1.05) {
        return;
      }
      _dragging = true;
    }

    final elapsed = event.timeStamp - (_lastMoveTime ?? event.timeStamp);
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final rawVelocity = seconds > 0 ? event.delta.dx / seconds : 0.0;
    _filteredVelocity = lerpDouble(_filteredVelocity, rawVelocity, 0.42)!;
    _lastMoveTime = event.timeStamp;

    final fraction = _fractionFor(event.localPosition);
    final direction = _filteredVelocity.abs() > 24
        ? _filteredVelocity.sign
        : event.delta.dx.abs() > 0.01
        ? event.delta.dx.sign
        : _lens.value.direction;
    final stretch = _reduceMotion
        ? 0.0
        : (_filteredVelocity.abs() / 1550).clamp(0.0, 1.0);
    _lens.value = _NavLensVisual(
      position: fraction,
      stretch: stretch,
      direction: direction,
      pressure: 1,
    );
    // The action item may preview as the lens passes through it, but it is
    // never invoked from a drag release.
    _setVisualIndex(_indexForFraction(fraction));
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_activePointer != event.pointer) return;
    final wasDragging = _dragging;
    final target = _releaseIndexForFraction(_fractionFor(event.localPosition));
    _clearPointerState();
    if (!wasDragging) {
      // The item's tap recognizer owns a normal tap and starts its animation
      // after this raw pointer callback.
      _settleToIndex(widget.currentIndex);
      return;
    }
    _commitTabSelection(target);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_activePointer != event.pointer) return;
    _clearPointerState();
    _setVisualIndex(widget.currentIndex);
    _settleToIndex(widget.currentIndex);
  }

  void _clearPointerState() {
    _activePointer = null;
    _pointerOrigin = null;
    _lastMoveTime = null;
    _filteredVelocity = 0;
    _dragging = false;
  }

  void _handleItemTap(int index) {
    if (_dragging) return;
    final target = _safeIndex(index);
    _setVisualIndex(target);
    _settleToIndex(target);
    if (target == _createIndex) {
      widget.onCreateTap();
      _restoreActualIndexAfterParentFrame(target);
      return;
    }
    widget.onTabSelected(target);
    _restoreActualIndexAfterParentFrame(target);
  }

  void _commitTabSelection(int index) {
    assert(index != _createIndex);
    final target = _safeIndex(index);
    _setVisualIndex(target);
    _settleToIndex(target);
    widget.onTabSelected(target);
    _restoreActualIndexAfterParentFrame(target);
  }

  void _restoreActualIndexAfterParentFrame(int requestedIndex) {
    // Authentication or a dismissed create action can legitimately leave the
    // actual tab unchanged. After the parent rebuilds, return the lens instead
    // of leaving a false selected state behind.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _activePointer != null) return;
      final actual = _safeIndex(widget.currentIndex);
      if (actual == requestedIndex) return;
      _setVisualIndex(actual);
      _settleToIndex(actual);
    });
  }

  @override
  void dispose() {
    _settleController.dispose();
    _lens.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final glassEnabled = context.appGlass.enabled;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      key: const Key('app-bottom-nav-material'),
      decoration: BoxDecoration(
        color: glassEnabled ? Colors.transparent : palette.surface,
        borderRadius: BorderRadius.circular(999),
        border: glassEnabled
            ? null
            : Border.all(color: palette.border, width: 0.7),
        boxShadow: glassEnabled
            ? null
            : [
                BoxShadow(
                  color: palette.shadow,
                  blurRadius: 22,
                  spreadRadius: -8,
                  offset: const Offset(0, 9),
                ),
              ],
      ),
      child: Listener(
        key: const Key('bottom-nav-drag-region'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    key: const Key('bottom-nav-liquid-lens'),
                    painter: _NavLensPainter(
                      lens: _lens,
                      palette: palette,
                      glassEnabled: glassEnabled,
                      isDark: isDark,
                      progress: widget.progress,
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                _NavItem(
                  index: 0,
                  currentIndex: widget.currentIndex,
                  visualIndex: _visualIndex,
                  icon: _NavIconKind.home,
                  label: 'Главная',
                  progress: widget.progress,
                  onTap: _handleItemTap,
                ),
                _NavItem(
                  index: 1,
                  currentIndex: widget.currentIndex,
                  visualIndex: _visualIndex,
                  icon: _NavIconKind.hanger,
                  label: 'Образы',
                  progress: widget.progress,
                  onTap: _handleItemTap,
                ),
                _NavItem(
                  index: 2,
                  currentIndex: widget.currentIndex,
                  visualIndex: _visualIndex,
                  icon: _NavIconKind.gridPlus,
                  label: 'Создать',
                  progress: widget.progress,
                  emphasize: true,
                  onTap: _handleItemTap,
                ),
                _NavItem(
                  index: 3,
                  currentIndex: widget.currentIndex,
                  visualIndex: _visualIndex,
                  icon: _NavIconKind.chat,
                  label: 'Чаты',
                  progress: widget.progress,
                  onTap: _handleItemTap,
                ),
                _NavItem(
                  index: 4,
                  currentIndex: widget.currentIndex,
                  visualIndex: _visualIndex,
                  icon: _NavIconKind.profile,
                  label: 'Профиль',
                  progress: widget.progress,
                  onTap: _handleItemTap,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

@immutable
class _NavLensVisual {
  const _NavLensVisual({
    required this.position,
    required this.stretch,
    required this.direction,
    required this.pressure,
  });

  factory _NavLensVisual.resting(double position) =>
      _NavLensVisual(position: position, stretch: 0, direction: 1, pressure: 0);

  final double position;
  final double stretch;
  final double direction;
  final double pressure;

  _NavLensVisual copyWith({
    double? position,
    double? stretch,
    double? direction,
    double? pressure,
  }) {
    return _NavLensVisual(
      position: position ?? this.position,
      stretch: stretch ?? this.stretch,
      direction: direction ?? this.direction,
      pressure: pressure ?? this.pressure,
    );
  }
}

class _NavLensPainter extends CustomPainter {
  _NavLensPainter({
    required this.lens,
    required this.palette,
    required this.glassEnabled,
    required this.isDark,
    required this.progress,
  }) : super(repaint: lens);

  final ValueListenable<_NavLensVisual> lens;
  final AppPalette palette;
  final bool glassEnabled;
  final bool isDark;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final visual = lens.value;
    final baseWidth = lerpDouble(43, 40, progress)!;
    final baseHeight = lerpDouble(34, 38, progress)!;
    final width = baseWidth + visual.pressure * 3 + visual.stretch * 19;
    final height = baseHeight + visual.pressure * 2 - visual.stretch * 2.5;
    final center = Offset(
      size.width * visual.position + visual.direction * visual.stretch * 2.5,
      lerpDouble(size.height / 2 - 5, size.height / 2, progress)!,
    );
    final rect = Rect.fromCenter(center: center, width: width, height: height);
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(height * 0.52));

    final haloAlpha =
        (glassEnabled ? 0.14 : 0.09) +
        visual.pressure * 0.05 +
        visual.stretch * 0.035;
    canvas.drawRRect(
      shape.inflate(1.3 + visual.pressure),
      Paint()
        ..isAntiAlias = true
        ..color = palette.accentSoft.withValues(alpha: haloAlpha)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          5 + visual.pressure * 2,
        ),
    );

    final neutralAlpha = isDark ? 0.15 : 0.085;
    final accentAlpha = isDark ? 0.42 : 0.32;
    canvas.drawRRect(
      shape,
      Paint()
        ..isAntiAlias = true
        ..shader = LinearGradient(
          begin: Alignment(-0.9 - visual.direction * visual.stretch * 0.25, -1),
          end: Alignment(0.9 + visual.direction * visual.stretch * 0.25, 1),
          colors: [
            palette.ink.withValues(alpha: neutralAlpha * 0.72),
            palette.accentSoft.withValues(
              alpha: accentAlpha + visual.pressure * 0.025,
            ),
            palette.ink.withValues(alpha: neutralAlpha),
          ],
          stops: const [0, 0.48, 1],
        ).createShader(rect),
    );

    canvas.drawRRect(
      shape.deflate(0.55),
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.24 : 0.52),
            palette.accentBorder.withValues(alpha: isDark ? 0.18 : 0.14),
            palette.ink.withValues(alpha: isDark ? 0.14 : 0.07),
          ],
        ).createShader(rect),
    );

    final highlight = Rect.fromLTWH(
      rect.left + width * 0.22,
      rect.top + 1.4,
      width * 0.56,
      1,
    );
    canvas.drawLine(
      highlight.centerLeft,
      highlight.centerRight,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 0.8
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: isDark ? 0.22 : 0.56),
            Colors.transparent,
          ],
        ).createShader(highlight),
    );
  }

  @override
  bool shouldRepaint(covariant _NavLensPainter oldDelegate) {
    return lens != oldDelegate.lens ||
        palette != oldDelegate.palette ||
        glassEnabled != oldDelegate.glassEnabled ||
        isDark != oldDelegate.isDark ||
        progress != oldDelegate.progress;
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.index,
    required this.currentIndex,
    required this.visualIndex,
    required this.icon,
    required this.label,
    required this.progress,
    required this.onTap,
    this.emphasize = false,
  });

  final int index;
  final int currentIndex;
  final int visualIndex;
  final _NavIconKind icon;
  final String label;
  final double progress;
  final bool emphasize;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = currentIndex == index;
    final isVisuallyActive = visualIndex == index;
    final palette = context.appPalette;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final iconOffset = lerpDouble(-5, 0, progress)!;
    final indicatorWidth = lerpDouble(emphasize ? 40 : 38, 36, progress)!;
    final indicatorHeight = lerpDouble(33, 36, progress)!;

    return Expanded(
      child: Semantics(
        button: true,
        selected: isActive,
        label: label,
        child: AppGlassPressable(
          onTap: () => onTap(index),
          pressedScale: 0.92,
          child: SizedBox.expand(
            key: Key('bottom-nav-item-$index'),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              alignment: Alignment.center,
              children: [
                Transform.translate(
                  offset: Offset(0, iconOffset),
                  child: AnimatedScale(
                    key: Key('bottom-nav-visual-$index'),
                    scale: isVisuallyActive ? 1.07 : 1,
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOutBack,
                    child: Container(
                      key: Key('bottom-nav-indicator-$index'),
                      width: indicatorWidth,
                      height: indicatorHeight,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.transparent,
                          width: 0.6,
                        ),
                      ),
                      child: _NavIcon(
                        kind: icon,
                        isActive: isVisuallyActive,
                        emphasize: emphasize,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 2,
                  right: 2,
                  bottom: lerpDouble(4, -15, progress)!,
                  child: Text(
                    label,
                    key: Key('bottom-nav-label-$index'),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9.5,
                      height: 1,
                      fontWeight: isVisuallyActive
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isVisuallyActive ? palette.ink : palette.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _NavIconKind { home, hanger, gridPlus, chat, profile }

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.kind,
    required this.isActive,
    required this.emphasize,
  });

  final _NavIconKind kind;
  final bool isActive;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final color = isActive
        ? Color.lerp(palette.ink, palette.accentInk, 0.22)!
        : palette.muted;
    final size = emphasize ? 21.5 : 21.0;
    return switch (kind) {
      _NavIconKind.home => _AssetIcon(
        asset: 'assets/icons/house.png',
        color: color,
        size: size,
      ),
      _NavIconKind.hanger => Icon(
        Icons.checkroom_outlined,
        size: size,
        color: color,
      ),
      _NavIconKind.gridPlus => _AssetIcon(
        asset: 'assets/icons/grid-plus.png',
        color: color,
        size: size,
      ),
      _NavIconKind.chat => _AssetIcon(
        asset: 'assets/icons/chat-bubble.png',
        color: color,
        size: size,
      ),
      _NavIconKind.profile => _AssetIcon(
        asset: 'assets/icons/human.png',
        color: color,
        size: size,
      ),
    };
  }
}

class _AssetIcon extends StatelessWidget {
  const _AssetIcon({
    required this.asset,
    required this.color,
    required this.size,
  });

  final String asset;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.medium,
    );
  }
}
