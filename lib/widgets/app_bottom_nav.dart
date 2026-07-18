import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
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

class _NavigationMaterial extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final glassEnabled = context.appGlass.enabled;
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
      child: Row(
        children: [
          _NavItem(
            index: 0,
            currentIndex: currentIndex,
            icon: _NavIconKind.home,
            label: 'Главная',
            progress: progress,
            onTap: onTabSelected,
          ),
          _NavItem(
            index: 1,
            currentIndex: currentIndex,
            icon: _NavIconKind.hanger,
            label: 'Образы',
            progress: progress,
            onTap: onTabSelected,
          ),
          _NavItem(
            index: 2,
            currentIndex: currentIndex,
            icon: _NavIconKind.gridPlus,
            label: 'Создать',
            progress: progress,
            emphasize: true,
            onTap: (_) => onCreateTap(),
          ),
          _NavItem(
            index: 3,
            currentIndex: currentIndex,
            icon: _NavIconKind.chat,
            label: 'Чаты',
            progress: progress,
            onTap: onTabSelected,
          ),
          _NavItem(
            index: 4,
            currentIndex: currentIndex,
            icon: _NavIconKind.profile,
            label: 'Профиль',
            progress: progress,
            onTap: onTabSelected,
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.index,
    required this.currentIndex,
    required this.icon,
    required this.label,
    required this.progress,
    required this.onTap,
    this.emphasize = false,
  });

  final int index;
  final int currentIndex;
  final _NavIconKind icon;
  final String label;
  final double progress;
  final bool emphasize;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = currentIndex == index;
    final palette = context.appPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedFill = palette.ink.withValues(alpha: isDark ? 0.13 : 0.085);
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
                  child: Container(
                    width: indicatorWidth,
                    height: indicatorHeight,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isActive ? selectedFill : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isActive
                            ? palette.ink.withValues(
                                alpha: isDark ? 0.12 : 0.07,
                              )
                            : Colors.transparent,
                        width: 0.6,
                      ),
                    ),
                    child: _NavIcon(
                      kind: icon,
                      isActive: isActive,
                      emphasize: emphasize,
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
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive ? palette.ink : palette.muted,
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
    final color = isActive ? palette.ink : palette.muted;
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
