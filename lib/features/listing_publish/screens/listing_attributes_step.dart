import 'package:flutter/material.dart';

import '../../../core/app_typography.dart';
import '../data/listing_catalogs.dart';
import '../listing_publish_controller.dart';
import '../widgets/listing_publish_widgets.dart';

const _secondaryText = Color(0xFF8F8F94);
const _border = Color(0xFFE7E7EA);
const _clearValue = '__clear__';

class ListingAttributesStep extends StatefulWidget {
  const ListingAttributesStep({super.key, required this.controller});

  final ListingPublishController controller;

  @override
  State<ListingAttributesStep> createState() => _ListingAttributesStepState();
}

class _ListingAttributesStepState extends State<ListingAttributesStep> {
  late final TextEditingController _defectsController;

  ListingPublishController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _defectsController = TextEditingController(
      text: controller.draft.defectDescription,
    );
    controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant ListingAttributesStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == controller) return;
    oldWidget.controller.removeListener(_handleControllerChanged);
    controller.addListener(_handleControllerChanged);
    _syncDefects();
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);
    _defectsController.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    _syncDefects();
    setState(() {});
  }

  void _syncDefects() {
    final value = controller.draft.defectDescription;
    if (_defectsController.text != value) {
      _defectsController.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft;
    final definitions = ListingCatalogs.attributesFor(draft.normalizedCategory);
    final categoryName = draft.normalizedCategory.isEmpty
        ? ''
        : ListingCatalogs.nameOf(draft.normalizedCategory);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          18,
          8,
          18,
          30 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          const Text(
            'Информация о вещи',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 16,
              fontWeight: AppTypography.semiBold,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Показываем всё, что удалось определить по фото. Проверьте предложения или исправьте их.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: AppTypography.medium,
              height: 1.35,
              color: _secondaryText,
            ),
          ),
          if (controller.isAnalyzing) ...[
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerLeft,
              child: ListingAnalysisStatusBadge.processing(
                label: 'Анализ ещё идёт — поля будут дополняться автоматически',
              ),
            ),
          ],
          const SizedBox(height: 18),
          ListingSelectionRow(
            key: const ValueKey('detail_category'),
            label: 'Категория',
            isRequired: true,
            value: categoryName.isEmpty ? null : categoryName,
            placeholder: 'Выберите тип вещи',
            status: _predictionStatus('normalized_category'),
            onTap: () => _chooseCore(
              title: 'Категория вещи',
              options: ListingCatalogs.finalCategories,
              selected: draft.normalizedCategory,
              field: 'normalized_category',
            ),
          ),
          ListingSelectionRow(
            key: const ValueKey('detail_primary_color'),
            label: 'Основной цвет',
            isRequired: true,
            value: draft.primaryColor.isEmpty
                ? null
                : ListingCatalogs.nameOf(draft.primaryColor),
            placeholder: 'Выберите основной цвет',
            status: _predictionStatus('primary_color'),
            onTap: () => _chooseCore(
              title: 'Основной цвет',
              options: ListingCatalogs.colors,
              selected: draft.primaryColor,
              field: 'primary_color',
            ),
          ),
          ListingSelectionRow(
            key: const ValueKey('detail_secondary_colors'),
            label: 'Дополнительные цвета',
            value: draft.secondaryColors.isEmpty
                ? null
                : draft.secondaryColors.map(ListingCatalogs.nameOf).join(', '),
            placeholder: 'Не указаны',
            status: _predictionStatus('secondary_colors'),
            onTap: _chooseSecondaryColors,
          ),
          const SizedBox(height: 12),
          const Text.rich(
            TextSpan(
              text: 'Дефекты',
              children: [
                TextSpan(
                  text: ' *',
                  style: TextStyle(color: Color(0xFFE11D2E)),
                ),
              ],
            ),
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              fontWeight: AppTypography.semiBold,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Подтвердите, есть ли пятна, повреждения или заметные следы носки.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11.5,
              height: 1.35,
              color: _secondaryText,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const ValueKey('defects_none'),
                label: const Text('Нет дефектов'),
                selected: draft.defectsReviewed && !draft.hasDefects,
                showCheckmark: false,
                selectedColor: Colors.black,
                labelStyle: TextStyle(
                  color: draft.defectsReviewed && !draft.hasDefects
                      ? Colors.white
                      : Colors.black,
                ),
                onSelected: (_) => controller.setHasDefects(false),
              ),
              ChoiceChip(
                key: const ValueKey('defects_yes'),
                label: const Text('Есть дефекты'),
                selected: draft.defectsReviewed && draft.hasDefects,
                showCheckmark: false,
                selectedColor: Colors.black,
                labelStyle: TextStyle(
                  color: draft.defectsReviewed && draft.hasDefects
                      ? Colors.white
                      : Colors.black,
                ),
                onSelected: (_) => controller.setHasDefects(true),
              ),
            ],
          ),
          if (!draft.defectsReviewed) ...[
            const SizedBox(height: 7),
            const Text(
              'Выберите один вариант',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 11,
                color: Color(0xFF706E82),
              ),
            ),
          ],
          if (draft.hasDefects) ...[
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('defects_description'),
              controller: _defectsController,
              minLines: 2,
              maxLines: 5,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              onChanged: controller.setDefectDescription,
              decoration: InputDecoration(
                labelText: 'Описание дефектов *',
                hintText: 'Что повреждено и где находится дефект',
                alignLabelWithHint: true,
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.black),
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),
          const Divider(height: 1, color: _border),
          const SizedBox(height: 20),
          Text(
            categoryName.isEmpty
                ? 'Характеристики'
                : 'Характеристики: $categoryName',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 15,
              fontWeight: AppTypography.semiBold,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Проверьте предложения. Измените значение или выберите «Не указывать», чтобы пропустить. Нажимая «Продолжить», вы принимаете оставшиеся значения.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: AppTypography.medium,
              height: 1.35,
              color: _secondaryText,
            ),
          ),
          const SizedBox(height: 12),
          if (draft.normalizedCategory.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'Сначала выберите категорию — после этого появятся подходящие характеристики.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  height: 1.35,
                  color: _secondaryText,
                ),
              ),
            )
          else
            ...definitions.map(
              (definition) => ListingSelectionRow(
                key: ValueKey('attribute_${definition.id}'),
                label: definition.label,
                value: _displayValue(definition.id),
                placeholder: 'Не указано',
                status: _predictionStatus(definition.id),
                onTap: () => _chooseAttribute(definition),
              ),
            ),
          const SizedBox(height: 18),
          const Text(
            'Замеры необязательны. Покупатель сможет запросить их в чате.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11.5,
              height: 1.4,
              color: _secondaryText,
            ),
          ),
        ],
      ),
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

  Widget? _predictionStatus(String field) {
    if (!_hasPendingSuggestion(field)) return null;
    return const ListingAnalysisStatusBadge.needsReview(label: 'Предложено');
  }

  bool _hasPendingSuggestion(String field) {
    final prediction = controller.predictionFor(field);
    return prediction?.predictedValue?.isNotEmpty == true &&
        prediction?.wasEdited != true &&
        prediction?.userConfirmed != true;
  }

  Future<void> _chooseCore({
    required String title,
    required List<CatalogOption> options,
    required String selected,
    required String field,
  }) async {
    FocusScope.of(context).unfocus();
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (context) => _AttributeOptionsSheet(
        title: title,
        options: options,
        selected: selected,
        allowClear: false,
      ),
    );
    if (!mounted || value == null) return;
    controller.setAttribute(field, value);
  }

  Future<void> _chooseAttribute(ListingAttributeDefinition definition) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (context) => _AttributeOptionsSheet(
        title: definition.label,
        options: definition.options,
        selected: _value(definition.id),
      ),
    );
    if (!mounted || value == null) return;
    controller.setAttribute(definition.id, value == _clearValue ? '' : value);
  }

  Future<void> _chooseSecondaryColors() async {
    final value = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (context) => _SecondaryColorsSheet(
        selectedValues: controller.draft.secondaryColors,
        excludedValue: controller.draft.primaryColor,
      ),
    );
    if (!mounted || value == null) return;
    controller.setSecondaryColors(value);
  }
}

class _AttributeOptionsSheet extends StatelessWidget {
  const _AttributeOptionsSheet({
    required this.title,
    required this.options,
    required this.selected,
    this.allowClear = true,
  });

  final String title;
  final List<CatalogOption> options;
  final String selected;
  final bool allowClear;

  @override
  Widget build(BuildContext context) {
    final itemCount = options.length + (allowClear ? 1 : 0);
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.76,
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
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
                    itemCount: itemCount,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (allowClear && index == 0) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Не указывать',
                            style: TextStyle(color: Color(0xFF706E82)),
                          ),
                          trailing: selected.isEmpty
                              ? const Icon(Icons.check_rounded, size: 20)
                              : null,
                          onTap: () => Navigator.pop(context, _clearValue),
                        );
                      }
                      final option = options[index - (allowClear ? 1 : 0)];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
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
        ),
      ),
    );
  }
}

class _SecondaryColorsSheet extends StatefulWidget {
  const _SecondaryColorsSheet({
    required this.selectedValues,
    required this.excludedValue,
  });

  final List<String> selectedValues;
  final String excludedValue;

  @override
  State<_SecondaryColorsSheet> createState() => _SecondaryColorsSheetState();
}

class _SecondaryColorsSheetState extends State<_SecondaryColorsSheet> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedValues.toSet()..remove(widget.excludedValue);
  }

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.78,
    ),
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
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
            ),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ListingCatalogs.colors
                    .map((option) {
                      final disabled = option.id == widget.excludedValue;
                      return FilterChip(
                        label: Text(option.name),
                        avatar: option.color == null
                            ? null
                            : CircleAvatar(backgroundColor: option.color),
                        selected: _selected.contains(option.id),
                        onSelected: disabled
                            ? null
                            : (selected) => setState(() {
                                selected
                                    ? _selected.add(option.id)
                                    : _selected.remove(option.id);
                              }),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.black),
              onPressed: () => Navigator.pop(context, _selected.toList()),
              child: const Text('Готово'),
            ),
          ),
        ],
      ),
    ),
  );
}
