import 'package:flutter/material.dart';

import '../core/app_appearance.dart';
import 'app_glass_surface.dart';

class CreateEntrySheet extends StatelessWidget {
  const CreateEntrySheet({
    super.key,
    required this.onCreateOutfit,
    required this.onPublishOutfit,
    required this.onCreateItem,
  });

  final VoidCallback onCreateOutfit;
  final VoidCallback onPublishOutfit;
  final VoidCallback onCreateItem;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final palette = context.appPalette;
    final glassEnabled = context.appGlass.enabled;

    final content = Container(
      decoration: BoxDecoration(
        color: glassEnabled ? Colors.transparent : palette.surfaceRaised,
        borderRadius: BorderRadius.circular(32),
        boxShadow: glassEnabled
            ? null
            : [
                BoxShadow(
                  color: palette.shadow,
                  blurRadius: 40,
                  offset: const Offset(0, -8),
                ),
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: palette.border,
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Что хотите создать?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: palette.ink,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _CreateOption(
                  icon: Icons.shopping_bag_outlined,
                  title: 'Опубликовать вещь',
                  subtitle: 'Продайте отдельную вещь в каталоге',
                  onTap: onCreateItem,
                ),
                const SizedBox(height: 14),
                _CreateOption(
                  icon: Icons.photo_library_outlined,
                  title: 'Опубликовать образ',
                  subtitle: 'Покажите свой образ миру',
                  onTap: onPublishOutfit,
                ),
                const SizedBox(height: 14),
                _CreateOption(
                  icon: Icons.checkroom_outlined,
                  title: 'Создать образ',
                  subtitle: 'Сохраните образ из своих вещей',
                  onTap: onCreateOutfit,
                ),
              ],
            ),
          ),
          SizedBox(height: 20 + bottomInset),
        ],
      ),
    );

    if (!glassEnabled) return content;
    return AppGlassSurface(
      role: AppGlassRole.sheet,
      grouped: false,
      interactiveGlint: false,
      density: 0.98,
      borderRadius: BorderRadius.circular(32),
      child: content,
    );
  }
}

class _CreateOption extends StatelessWidget {
  const _CreateOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final glassEnabled = context.appGlass.enabled;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 78,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: glassEnabled
              ? palette.ink.withValues(alpha: 0.055)
              : palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: glassEnabled
                ? palette.ink.withValues(alpha: 0.12)
                : palette.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: palette.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: palette.ink),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 13,
                      color: palette.muted,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 22, color: palette.muted),
          ],
        ),
      ),
    );
  }
}
