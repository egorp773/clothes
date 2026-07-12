import 'package:flutter/material.dart';

import '../../../core/app_typography.dart';
import '../data/listing_catalogs.dart';
import '../listing_publish_controller.dart';
import '../models/listing_draft.dart';
import '../widgets/listing_publish_widgets.dart';

class ListingAttributesStep extends StatefulWidget {
  const ListingAttributesStep({super.key, required this.controller});

  final ListingPublishController controller;

  @override
  State<ListingAttributesStep> createState() => _ListingAttributesStepState();
}

class _ListingAttributesStepState extends State<ListingAttributesStep> {
  bool _showMore = false;

  ListingPublishController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft;
    final subcategories =
        ListingCatalogs.subcategoriesByCategory[draft.category] ?? const [];
    final itemTypes =
        ListingCatalogs.itemTypesBySubcategory[draft.subcategory] ?? const [];

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
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Сначала обязательные поля. Автоматические варианты можно изменить.',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: AppTypography.medium,
            height: 1.35,
            letterSpacing: 0,
            color: Color(0xFF8F8F94),
          ),
        ),
        const SizedBox(height: 18),
        const Row(
          children: [
            Expanded(
              child: Text(
                'Обязательные',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 15,
                  fontWeight: AppTypography.semiBold,
                  letterSpacing: 0,
                ),
              ),
            ),
            Text(
              '* обязательное поле',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 10.5,
                fontWeight: AppTypography.semiBold,
                letterSpacing: 0,
                color: Color(0xFFE11D2E),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ListingSelectionRow(
          label: 'Пол',
          isRequired: true,
          value: _name(draft.gender),
          status: _status('gender'),
          onTap: () => _choose(
            context,
            title: 'Пол',
            options: ListingCatalogs.genders,
            selected: draft.gender,
            onSelected: (value) => controller.setAttribute('gender', value),
          ),
        ),
        ListingSelectionRow(
          label: 'Категория',
          isRequired: true,
          value: _name(draft.category),
          status: _status('category'),
          onTap: () => _choose(
            context,
            title: 'Категория',
            options: ListingCatalogs.categories,
            selected: draft.category,
            onSelected: (value) => controller.setAttribute('category', value),
          ),
        ),
        ListingSelectionRow(
          label: 'Подкатегория',
          isRequired: true,
          value: _name(draft.subcategory),
          placeholder: draft.category.isEmpty
              ? 'Сначала выберите категорию'
              : 'Выберите',
          enabled: draft.category.isNotEmpty,
          status: _status('subcategory'),
          onTap: () => _choose(
            context,
            title: 'Подкатегория',
            options: subcategories,
            selected: draft.subcategory,
            onSelected: (value) =>
                controller.setAttribute('subcategory', value),
          ),
        ),
        ListingSelectionRow(
          label: 'Тип вещи',
          isRequired: true,
          value: _name(draft.itemType),
          placeholder: draft.subcategory.isEmpty
              ? 'Сначала выберите подкатегорию'
              : 'Выберите',
          enabled: draft.subcategory.isNotEmpty,
          status: _status('item_type'),
          onTap: () => _choose(
            context,
            title: 'Тип вещи',
            options: itemTypes,
            selected: draft.itemType,
            onSelected: (value) => controller.setAttribute('item_type', value),
          ),
        ),
        ListingSelectionRow(
          label: 'Основной цвет',
          isRequired: true,
          valueWidget: draft.primaryColor.isEmpty
              ? null
              : _ColorSwatches(colorIds: _displayedPrimaryColors(draft)),
          status: _status('primary_color'),
          onTap: () => _choose(
            context,
            title: 'Основной цвет',
            options: ListingCatalogs.colors,
            selected: draft.primaryColor,
            onSelected: (value) =>
                controller.setAttribute('primary_color', value),
          ),
        ),
        ListingSelectionRow(
          label: 'Бренд',
          isRequired: true,
          value: _name(draft.brand),
          placeholder: 'Укажите бренд или выберите «Без бренда»',
          status: _status('brand'),
          onTap: () => _choose(
            context,
            title: 'Бренд',
            options: ListingCatalogs.brands,
            selected: draft.brand,
            onSelected: (value) => controller.setAttribute('brand', value),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 46,
          child: OutlinedButton(
            onPressed: () => setState(() => _showMore = !_showMore),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF111111),
              side: const BorderSide(color: Color(0xFFE7E7EA)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _showMore ? 'Скрыть подробности' : 'Подробнее',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontWeight: AppTypography.semiBold,
                    fontSize: 13,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  _showMore
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          crossFadeState: _showMore
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 22),
              const Text(
                'Дополнительные характеристики',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 15,
                  fontWeight: AppTypography.semiBold,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 4),
              ListingSelectionRow(
                label: 'Дополнительные цвета',
                valueWidget: draft.secondaryColors.isEmpty
                    ? null
                    : _ColorSwatches(colorIds: draft.secondaryColors),
                placeholder: 'Можно выбрать несколько',
                status: _status('secondary_colors'),
                onTap: () => _chooseSecondaryColors(context),
              ),
              ListingSelectionRow(
                label: 'Материал',
                value: _name(draft.material),
                status: _status('material'),
                onTap: () => _choose(
                  context,
                  title: 'Материал',
                  options: ListingCatalogs.materials,
                  selected: draft.material,
                  onSelected: (value) =>
                      controller.setAttribute('material', value),
                ),
              ),
              ListingSelectionRow(
                label: 'Рисунок или принт',
                value: _name(draft.pattern),
                status: _status('pattern'),
                onTap: () => _choose(
                  context,
                  title: 'Рисунок или принт',
                  options: ListingCatalogs.patterns,
                  selected: draft.pattern,
                  onSelected: (value) =>
                      controller.setAttribute('pattern', value),
                ),
              ),
              ListingSelectionRow(
                label: 'Сезон',
                value: _name(draft.season),
                status: _status('season'),
                onTap: () => _choose(
                  context,
                  title: 'Сезон',
                  options: ListingCatalogs.seasons,
                  selected: draft.season,
                  onSelected: (value) =>
                      controller.setAttribute('season', value),
                ),
              ),
              ListingSelectionRow(
                label: 'Стиль',
                value: _name(draft.style),
                status: _status('style'),
                onTap: () => _choose(
                  context,
                  title: 'Стиль',
                  options: ListingCatalogs.styles,
                  selected: draft.style,
                  onSelected: (value) =>
                      controller.setAttribute('style', value),
                ),
              ),
              ListingSelectionRow(
                label: 'Крой',
                value: _name(draft.fit),
                status: _status('fit'),
                onTap: () => _choose(
                  context,
                  title: 'Крой',
                  options: ListingCatalogs.fits,
                  selected: draft.fit,
                  onSelected: (value) => controller.setAttribute('fit', value),
                ),
              ),
              ListingSelectionRow(
                label: 'Длина рукава',
                value: _name(draft.sleeveLength),
                status: _status('sleeve_length'),
                onTap: () => _choose(
                  context,
                  title: 'Длина рукава',
                  options: ListingCatalogs.sleeveLengths,
                  selected: draft.sleeveLength,
                  onSelected: (value) =>
                      controller.setAttribute('sleeve_length', value),
                ),
              ),
              ListingSelectionRow(
                label: 'Застёжка',
                value: _name(draft.closure),
                status: _status('closure'),
                showDivider: false,
                onTap: () => _choose(
                  context,
                  title: 'Застёжка',
                  options: ListingCatalogs.closures,
                  selected: draft.closure,
                  onSelected: (value) =>
                      controller.setAttribute('closure', value),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String? _name(String id) =>
      id.isEmpty ? null : ListingCatalogs.nameOf(id, fallback: id);

  List<String> _displayedPrimaryColors(ListingDraft draft) {
    if (draft.primaryColor != 'multicolor') return [draft.primaryColor];
    if (draft.secondaryColors.isNotEmpty) return draft.secondaryColors;
    return const ['red', 'orange', 'yellow', 'green', 'blue', 'purple'];
  }

  Widget? _status(String field) {
    final prediction = controller.predictionFor(field);
    if (prediction?.needsReview != true || prediction!.wasEdited) return null;
    return const ListingAnalysisStatusBadge.needsReview();
  }

  Future<void> _choose(
    BuildContext context, {
    required String title,
    required List<CatalogOption> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) async {
    if (options.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _OptionsSheet(
        title: title,
        options: options,
        selected: selected,
        onSelected: (value) {
          onSelected(value);
          Navigator.pop(sheetContext);
        },
      ),
    );
  }

  Future<void> _chooseSecondaryColors(BuildContext context) async {
    final selected = Set<String>.of(controller.draft.secondaryColors);
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
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
                const Text(
                  'Дополнительные цвета',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 16,
                    fontWeight: AppTypography.semiBold,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 3.4,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: ListingCatalogs.colors.length,
                    itemBuilder: (context, index) {
                      final option = ListingCatalogs.colors[index];
                      final active = selected.contains(option.id);
                      final disabled =
                          option.id == controller.draft.primaryColor;
                      return FilterChip(
                        selected: active,
                        onSelected: disabled
                            ? null
                            : (_) => setSheetState(() {
                                active
                                    ? selected.remove(option.id)
                                    : selected.add(option.id);
                              }),
                        label: Text(option.name),
                        avatar: option.color == null
                            ? null
                            : CircleAvatar(backgroundColor: option.color),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(sheetContext, selected.toList()),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black,
                    ),
                    child: const Text('Готово'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null) controller.setSecondaryColors(result);
  }
}

class _ColorSwatches extends StatelessWidget {
  const _ColorSwatches({required this.colorIds});

  final List<String> colorIds;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 4,
    children: colorIds
        .map(_colorFor)
        .whereType<Color>()
        .map(
          (color) => Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFD9D9DE)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        )
        .toList(growable: false),
  );

  static Color? _colorFor(String id) {
    for (final option in ListingCatalogs.colors) {
      if (option.id == id) return option.color;
    }
    return null;
  }
}

class _OptionsSheet extends StatelessWidget {
  const _OptionsSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final String title;
  final List<CatalogOption> options;
  final String selected;
  final ValueChanged<String> onSelected;

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
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: options.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final option = options[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  minTileHeight: 50,
                  leading: option.color == null
                      ? null
                      : Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: option.color,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE0E0E4)),
                          ),
                        ),
                  title: Text(
                    option.name,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 14,
                      fontWeight: AppTypography.medium,
                      letterSpacing: 0,
                    ),
                  ),
                  trailing: option.id == selected
                      ? const Icon(Icons.check_rounded, size: 20)
                      : null,
                  onTap: () => onSelected(option.id),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
