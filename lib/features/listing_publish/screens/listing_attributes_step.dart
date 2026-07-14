import 'package:flutter/material.dart';

import '../../../core/app_typography.dart';
import '../data/listing_catalogs.dart';
import '../listing_publish_controller.dart';
import '../widgets/listing_publish_widgets.dart';

class ListingAttributesStep extends StatelessWidget {
  const ListingAttributesStep({super.key, required this.controller});

  final ListingPublishController controller;

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft;
    final definitions = ListingCatalogs.attributesFor(draft.normalizedCategory);
    final categoryName = ListingCatalogs.nameOf(draft.normalizedCategory);

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        const Text(
          'Проверьте характеристики',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 16,
            fontWeight: AppTypography.semiBold,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Только важное для категории «$categoryName». Предложения по фото можно изменить или оставить пустыми.',
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: AppTypography.medium,
            height: 1.35,
            color: Color(0xFF8F8F94),
          ),
        ),
        if (controller.isAnalyzing) ...[
          const SizedBox(height: 14),
          const Align(
            alignment: Alignment.centerLeft,
            child: ListingAnalysisStatusBadge.processing(
              label: 'Анализ ещё идёт, ждать не обязательно',
            ),
          ),
        ],
        const SizedBox(height: 18),
        ...definitions.map(
          (definition) => ListingSelectionRow(
            key: ValueKey('attribute_${definition.id}'),
            label: definition.label,
            value: _displayValue(definition.id),
            placeholder: 'Не указано',
            status: _status(definition.id),
            onTap: () => _choose(context, definition),
          ),
        ),
        if (definitions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Text(
              'Для этой категории дополнительных характеристик нет.',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                color: Color(0xFF8F8F94),
              ),
            ),
          ),
        const SizedBox(height: 18),
        const Text(
          'Замеры не обязательны. Покупатель сможет запросить их у вас в чате.',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 11.5,
            height: 1.4,
            color: Color(0xFF8F8F94),
          ),
        ),
      ],
    );
  }

  String? _displayValue(String field) {
    final value = _value(field);
    return value.isEmpty
        ? null
        : ListingCatalogs.nameOf(value, fallback: value);
  }

  String _value(String field) => switch (field) {
    'material' => controller.draft.material,
    'pattern' => controller.draft.pattern,
    'season' => controller.draft.season,
    'style' => controller.draft.style,
    'fit' => controller.draft.fit,
    'sleeve_length' => controller.draft.sleeveLength,
    'closure' => controller.draft.closure,
    'collar' => controller.draft.collar,
    'rise' => controller.draft.rise,
    _ => controller.draft.categoryAttributes[field] ?? '',
  };

  Widget? _status(String field) {
    final prediction = controller.predictionFor(field);
    if (prediction?.predictedValue?.isEmpty ?? true) return null;
    if (prediction!.wasEdited || prediction.userConfirmed) return null;
    return const ListingAnalysisStatusBadge.needsReview(label: 'Предложено');
  }

  Future<void> _choose(
    BuildContext context,
    ListingAttributeDefinition definition,
  ) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AttributeOptionsSheet(
        title: definition.label,
        options: definition.options,
        selected: _value(definition.id),
      ),
    );
    if (value != null) {
      controller.setAttribute(definition.id, value == _clearValue ? '' : value);
    }
  }
}

const _clearValue = '__clear__';

class _AttributeOptionsSheet extends StatelessWidget {
  const _AttributeOptionsSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<CatalogOption> options;
  final String selected;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.72,
    ),
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 16,
              fontWeight: AppTypography.semiBold,
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: options.length + 1,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    minTileHeight: 50,
                    title: const Text(
                      'Не указывать',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 14,
                        color: Color(0xFF706E82),
                      ),
                    ),
                    trailing: selected.isEmpty
                        ? const Icon(Icons.check_rounded, size: 20)
                        : null,
                    onTap: () => Navigator.pop(context, _clearValue),
                  );
                }
                final option = options[index - 1];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  minTileHeight: 50,
                  title: Text(
                    option.name,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 14,
                      fontWeight: AppTypography.medium,
                    ),
                  ),
                  trailing: option.id == selected
                      ? const Icon(Icons.check_rounded, size: 20)
                      : null,
                  onTap: () => Navigator.pop(context, option.id),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
