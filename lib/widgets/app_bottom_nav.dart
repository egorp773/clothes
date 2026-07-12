import 'package:flutter/material.dart';

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
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8E8EE), width: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
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
      ),
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
    return Expanded(
      child: InkResponse(
        onTap: () => onTap(index),
        radius: 28,
        splashColor: Colors.black12,
        highlightColor: Colors.transparent,
        child: Center(
          child: _NavIcon(kind: icon, isActive: isActive),
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
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        splashColor: Colors.black12,
        highlightColor: Colors.transparent,
        child: Center(
          child: AnimatedScale(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            scale: isActive ? 1.06 : 1,
            child: _NavIcon(kind: _NavIconKind.gridPlus, isActive: isActive),
          ),
        ),
      ),
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
    final color = switch (kind) {
      _NavIconKind.hanger =>
        isActive ? const Color(0xFF9AA0A7) : const Color(0xFFB3B8BE),
      _ => isActive ? const Color(0xFF7A8189) : const Color(0xFF9AA0A7),
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
