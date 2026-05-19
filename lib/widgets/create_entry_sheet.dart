import 'package:flutter/material.dart';

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

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
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
              color: const Color(0xFFE0E0E2),
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Что хотите создать?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: Color(0xFF111111),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 78,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE9E9EC)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Color(0xFFF6F6F7),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: const Color(0xFF111111)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF111111),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF8E8E94),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 22, color: Color(0xFFB8B8BE)),
          ],
        ),
      ),
    );
  }
}
