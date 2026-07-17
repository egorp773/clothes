import 'package:flutter/material.dart';

import '../core/app_appearance.dart';
import 'app_glass_surface.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.onCreateTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onCreateTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final navigation = SafeArea(
      top: false,
      child: SizedBox(
        height: context.appGlass.enabled ? 66 : 64,
        child: Row(
          children: [
            _NavItem(
              index: 0,
              currentIndex: currentIndex,
              icon: _NavIconKind.home,
              onTap: onTabSelected,
            ),
            _NavItem(
              index: 1,
              currentIndex: currentIndex,
              icon: _NavIconKind.hanger,
              onTap: onTabSelected,
            ),
            _CreateItem(isActive: currentIndex == 2, onTap: onCreateTap),
            _NavItem(
              index: 3,
              currentIndex: currentIndex,
              icon: _NavIconKind.chat,
              onTap: onTabSelected,
            ),
            _NavItem(
              index: 4,
              currentIndex: currentIndex,
              icon: _NavIconKind.profile,
              onTap: onTabSelected,
            ),
          ],
        ),
      ),
    );

    if (context.appGlass.enabled) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: AppGlassSurface(
          density: 0.96,
          borderRadius: BorderRadius.circular(27),
          child: navigation,
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border, width: 0.8)),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: navigation,
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.index,
    required this.currentIndex,
    required this.icon,
    required this.onTap,
  });

  final int index;
  final int currentIndex;
  final _NavIconKind icon;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = currentIndex == index;
    final label = switch (icon) {
      _NavIconKind.home => 'Главная',
      _NavIconKind.hanger => 'Образы',
      _NavIconKind.chat => 'Сообщения',
      _NavIconKind.profile => 'Профиль',
      _NavIconKind.gridPlus => 'Создать',
    };
    return Expanded(
      child: Semantics(
        button: true,
        selected: isActive,
        label: label,
        child: AppGlassPressable(
          onTap: () => onTap(index),
          child: Center(
            child: _GlassNavIconFrame(
              isActive: isActive,
              child: _NavIcon(kind: icon, isActive: isActive),
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateItem extends StatelessWidget {
  const _CreateItem({required this.isActive, required this.onTap});

  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: isActive,
        label: 'Создать',
        child: AppGlassPressable(
          onTap: onTap,
          child: Center(
            child: AnimatedScale(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              scale: isActive ? 1.06 : 1,
              child: _GlassNavIconFrame(
                isActive: isActive,
                emphasize: true,
                child: _NavIcon(
                  kind: _NavIconKind.gridPlus,
                  isActive: isActive,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassNavIconFrame extends StatelessWidget {
  const _GlassNavIconFrame({
    required this.isActive,
    required this.child,
    this.emphasize = false,
  });

  final bool isActive;
  final bool emphasize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!context.appGlass.enabled) return child;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final visible = isActive || emphasize;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: emphasize ? 48 : 44,
      height: emphasize ? 40 : 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: visible
            ? Colors.white.withValues(
                alpha: isActive
                    ? (isDark ? 0.15 : 0.58)
                    : (isDark ? 0.065 : 0.3),
              )
            : Colors.transparent,
        borderRadius: BorderRadius.circular(emphasize ? 16 : 15),
        border: Border.all(
          color: visible
              ? Colors.white.withValues(
                  alpha: isActive
                      ? (isDark ? 0.28 : 0.72)
                      : (isDark ? 0.1 : 0.34),
                )
              : Colors.transparent,
          width: 0.8,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.1),
                  blurRadius: 12,
                  spreadRadius: -6,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

enum _NavIconKind { home, hanger, gridPlus, chat, profile }

class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.kind, required this.isActive});

  final _NavIconKind kind;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final color = switch (kind) {
      _NavIconKind.hanger =>
        isActive ? palette.ink : palette.muted.withValues(alpha: 0.72),
      _ => isActive ? palette.ink : palette.muted,
    };
    switch (kind) {
      case _NavIconKind.home:
        return _AssetIcon(
          asset: 'assets/icons/house.png',
          color: color,
          size: 21,
        );
      case _NavIconKind.hanger:
        return Icon(Icons.checkroom_outlined, size: 21, color: color);
      case _NavIconKind.gridPlus:
        return _AssetIcon(
          asset: 'assets/icons/grid-plus.png',
          color: color,
          size: 21,
        );
      case _NavIconKind.chat:
        return _AssetIcon(
          asset: 'assets/icons/chat-bubble.png',
          color: color,
          size: 21,
        );
      case _NavIconKind.profile:
        return _AssetIcon(
          asset: 'assets/icons/human.png',
          color: color,
          size: 21,
        );
    }
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
      filterQuality: FilterQuality.high,
    );
  }
}
