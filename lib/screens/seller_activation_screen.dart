import 'package:flutter/material.dart';

import '../core/app_appearance.dart';
import '../models/user_entitlements.dart';

Future<SellerType?> showSellerTypePicker(
  BuildContext context, {
  SellerType? selected,
  String title = 'Тип продавца',
}) {
  return showModalBottomSheet<SellerType>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) =>
        _SellerTypePickerSheet(selected: selected, title: title),
  );
}

class _SellerTypePickerSheet extends StatelessWidget {
  const _SellerTypePickerSheet({required this.selected, required this.title});

  final SellerType? selected;
  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.45,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Выбор сохранится в профиле. Его можно изменить в любой момент.',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: palette.muted,
                ),
              ),
              const SizedBox(height: 16),
              for (final type in SellerType.values) ...[
                _SellerTypeTile(
                  type: type,
                  selected: type == selected,
                  onTap: () => Navigator.of(context).pop(type),
                ),
                if (type != SellerType.values.last) const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SellerTypeTile extends StatelessWidget {
  const _SellerTypeTile({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final SellerType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Material(
      color: selected ? palette.surfaceMuted : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: Key('seller-type-${type.wireName}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? palette.ink : palette.border,
              width: selected ? 1.2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  type.displayName,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                  ),
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 21,
                color: selected ? palette.ink : palette.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
