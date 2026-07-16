import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_typography.dart';
import '../data/listing_catalogs.dart';
import '../listing_publish_controller.dart';
import '../widgets/listing_publish_widgets.dart';

const Color _textColor = Color(0xFF0B0B0B);
const Color _secondaryTextColor = Color(0xFF8F8F94);
const Color _borderColor = Color(0xFFE7E7EA);

class ListingBasicsStep extends StatefulWidget {
  const ListingBasicsStep({super.key, required this.controller});

  final ListingPublishController controller;

  @override
  State<ListingBasicsStep> createState() => _ListingBasicsStepState();
}

class _ListingBasicsStepState extends State<ListingBasicsStep> {
  late final TextEditingController _titleController;
  late final TextEditingController _priceController;
  late final TextEditingController _descriptionController;
  String? _syncedDraftId;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _priceController = TextEditingController();
    _descriptionController = TextEditingController();
    _syncTextFromFlow();
    widget.controller.addListener(_handleFlowChanged);
  }

  @override
  void didUpdateWidget(covariant ListingBasicsStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleFlowChanged);
    widget.controller.addListener(_handleFlowChanged);
    _syncedDraftId = null;
    _syncTextFromFlow();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleFlowChanged);
    _titleController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _handleFlowChanged() {
    if (!mounted) return;
    _syncTextFromFlow();
    setState(() {});
  }

  void _syncTextFromFlow() {
    if (!widget.controller.isInitialized) return;
    final draft = widget.controller.draft;
    final isNewDraft = _syncedDraftId != draft.id;
    _syncedDraftId = draft.id;

    // A recovered draft can already contain a seller-entered title.
    _applyExternalText(_titleController, draft.title);
    // Description may be filled asynchronously by analysis while this step is
    // visible, unless the seller has already edited it.
    _applyExternalText(_descriptionController, draft.description);
    // Price has no analysis suggestion. Sync it only when opening/replacing a
    // draft, otherwise a temporarily entered zero would be erased mid-edit.
    if (isNewDraft) {
      _applyExternalText(
        _priceController,
        draft.price > 0 ? draft.price.toString() : '',
      );
    }
  }

  void _applyExternalText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.isInitialized) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF070707),
          ),
        ),
      );
    }

    final draft = widget.controller.draft;
    final priceIsInvalid = _priceController.text.isNotEmpty && draft.price <= 0;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          18,
          8,
          18,
          30 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Основная информация',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 16,
                fontWeight: AppTypography.semiBold,
                color: _textColor,
                height: 1.2,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Заполните только главное — остальные характеристики можно проверить на следующем шаге.',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                fontWeight: AppTypography.medium,
                color: _secondaryTextColor,
                height: 1.35,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 24),
            _FieldLabel(label: 'Название', isRequired: true),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              inputFormatters: [LengthLimitingTextInputFormatter(80)],
              onChanged: widget.controller.setTitle,
              style: _inputStyle,
              decoration: _inputDecoration(
                hintText: 'Например, худи Nike',
                suffixText: '${_titleController.text.length}/80',
              ),
            ),
            const SizedBox(height: 22),
            _FieldLabel(label: 'Цена', isRequired: true),
            const SizedBox(height: 8),
            TextField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: widget.controller.setPrice,
              style: _inputStyle,
              decoration: _inputDecoration(
                hintText: 'Введите цену',
                suffixText: '₽',
                errorText: priceIsInvalid ? 'Цена должна быть больше 0' : null,
              ),
            ),
            const SizedBox(height: 20),
            ListingSelectionRow(
              key: const ValueKey('basic_brand'),
              label: 'Бренд',
              isRequired: true,
              value: draft.brand.isEmpty
                  ? null
                  : ListingCatalogs.brandName(
                      draft.brand,
                      fallback: draft.brand,
                    ),
              placeholder: 'Бренд или «Без бренда»',
              onTap: _showBrandPicker,
            ),
            ListingSelectionRow(
              key: const ValueKey('basic_size'),
              label: 'Размер',
              isRequired: true,
              value: draft.size.isEmpty ? null : _sizeDisplayName(draft.size),
              placeholder: 'Выберите размер',
              onTap: _showSizePicker,
            ),
            ListingSelectionRow(
              key: const ValueKey('basic_condition'),
              label: 'Состояние',
              isRequired: true,
              value: draft.condition.isEmpty
                  ? null
                  : ListingCatalogs.conditionName(draft.condition),
              placeholder: 'Выберите состояние',
              onTap: _showConditionPicker,
            ),
            ListingSelectionRow(
              key: const ValueKey('basic_audience'),
              label: 'Аудитория',
              isRequired: true,
              value: draft.gender.isEmpty
                  ? null
                  : ListingCatalogs.genderName(draft.gender),
              onTap: () => _selectAttribute(
                title: 'Для кого вещь',
                options: ListingCatalogs.genders,
                selected: draft.gender,
                field: 'gender',
              ),
            ),
            if (widget.controller.isAnalyzing) ...[
              const SizedBox(height: 18),
              const Align(
                alignment: Alignment.centerLeft,
                child: ListingAnalysisStatusBadge.processing(
                  label: 'Анализируем фото — предложим данные автоматически',
                ),
              ),
            ],
            const SizedBox(height: 22),
            const _FieldLabel(label: 'Описание (необязательно)'),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('basic_description'),
              controller: _descriptionController,
              minLines: 3,
              maxLines: 7,
              maxLength: 2000,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              onChanged: widget.controller.setDescription,
              style: _inputStyle,
              decoration: _inputDecoration(
                hintText: 'Расскажите о вещи',
                alignLabelWithHint: true,
              ).copyWith(counterText: ''),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectAttribute({
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
      builder: (context) => _CatalogOptionsSheet(
        title: title,
        selectedValue: selected,
        options: options,
      ),
    );
    if (!mounted || value == null) return;
    widget.controller.setAttribute(field, value);
  }

  Future<void> _showBrandPicker() async {
    FocusScope.of(context).unfocus();
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (context) => _CatalogOptionsSheet(
        title: 'Бренд',
        selectedValue: widget.controller.draft.brand,
        options: ListingCatalogs.brands,
      ),
    );
    if (!mounted || selected == null) return;
    if (selected != 'other_brand') {
      widget.controller.setAttribute('brand', selected);
      return;
    }

    final textController = TextEditingController();
    final customBrand = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Введите бренд'),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLength: 80,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'Например, COS'),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(dialogContext, value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () {
              final value = textController.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    textController.dispose();
    if (!mounted || customBrand == null || customBrand.isEmpty) return;
    widget.controller.setAttribute('brand', customBrand);
  }

  Future<void> _showSizePicker() async {
    FocusScope.of(context).unfocus();
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (context) => _SizePickerSheet(
        selectedValue: widget.controller.draft.size,
        category: widget.controller.draft.normalizedCategory,
      ),
    );
    if (!mounted || selected == null || selected.trim().isEmpty) return;
    widget.controller.setSize(selected.trim());
  }

  String _sizeDisplayName(String id) =>
      ListingCatalogs.sizeName(id, fallback: id);

  Future<void> _showConditionPicker() async {
    FocusScope.of(context).unfocus();
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (context) => _CatalogOptionsSheet(
        title: 'Состояние вещи',
        selectedValue: widget.controller.draft.condition,
        options: ListingCatalogs.conditions,
      ),
    );
    if (!mounted || selected == null) return;
    widget.controller.setCondition(selected);
  }
}

const TextStyle _inputStyle = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: 12.5,
  fontWeight: AppTypography.medium,
  color: Color(0xFF111111),
  height: 1.2,
  letterSpacing: 0,
);

InputDecoration _inputDecoration({
  required String hintText,
  String? suffixText,
  String? errorText,
  bool alignLabelWithHint = false,
}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: 12.5,
      fontWeight: AppTypography.medium,
      color: _secondaryTextColor,
      letterSpacing: 0,
    ),
    suffixText: suffixText,
    suffixStyle: const TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: 11.5,
      fontWeight: AppTypography.medium,
      color: _secondaryTextColor,
      letterSpacing: 0,
    ),
    errorText: errorText,
    errorStyle: const TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: 10.5,
      fontWeight: AppTypography.medium,
      color: Color(0xFF706E82),
      letterSpacing: 0,
    ),
    alignLabelWithHint: alignLabelWithHint,
    isDense: true,
    contentPadding: const EdgeInsets.only(bottom: 9),
    enabledBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: _borderColor),
    ),
    focusedBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: _textColor),
    ),
    errorBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: _borderColor),
    ),
    focusedErrorBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: _textColor),
    ),
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, this.isRequired = false});

  final String label;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: label,
        children: [
          if (isRequired)
            const TextSpan(
              text: ' *',
              style: TextStyle(
                color: Color(0xFFE11D2E),
                fontWeight: AppTypography.bold,
              ),
            ),
        ],
      ),
      style: const TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontSize: 12.5,
        fontWeight: AppTypography.semiBold,
        color: _textColor,
        height: 1,
        letterSpacing: 0,
      ),
    );
  }
}

class _SizePickerSheet extends StatefulWidget {
  const _SizePickerSheet({required this.selectedValue, required this.category});

  final String selectedValue;
  final String category;

  @override
  State<_SizePickerSheet> createState() => _SizePickerSheetState();
}

class _SizePickerSheetState extends State<_SizePickerSheet> {
  late final TextEditingController _customSizeController;

  @override
  void initState() {
    super.initState();
    final isKnown = [
      ...ListingCatalogs.universalSizes,
      ...ListingCatalogs.shoeSizes,
    ].any((option) => option.id == widget.selectedValue);
    _customSizeController = TextEditingController(
      text: isKnown ? '' : widget.selectedValue,
    );
  }

  @override
  void dispose() {
    _customSizeController.dispose();
    super.dispose();
  }

  void _submitCustomSize() {
    final value = _customSizeController.text.trim();
    if (value.isEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final isShoes = ListingCatalogs.isShoeCategory(widget.category);
    final usesOneSize = ListingCatalogs.usesOneSize(widget.category);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Размер',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 16,
                    fontWeight: AppTypography.semiBold,
                    color: _textColor,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 20),
                if (!isShoes)
                  _SheetSectionTitle(
                    usesOneSize ? 'Размер аксессуара' : 'Универсальные размеры',
                  ),
                const SizedBox(height: 10),
                if (!isShoes)
                  _SizeOptionsWrap(
                    options:
                        (usesOneSize
                                ? ListingCatalogs.oneSizeOptions
                                : ListingCatalogs.universalSizes)
                            .where((option) => option.id != 'custom')
                            .toList(growable: false),
                    selectedValue: widget.selectedValue,
                  ),
                const SizedBox(height: 22),
                if (widget.category.isEmpty || isShoes)
                  const _SheetSectionTitle('Размеры обуви'),
                const SizedBox(height: 10),
                if (widget.category.isEmpty || isShoes)
                  _SizeOptionsWrap(
                    options: ListingCatalogs.shoeSizes,
                    selectedValue: widget.selectedValue,
                  ),
                const SizedBox(height: 22),
                const _SheetSectionTitle('Свой вариант'),
                const SizedBox(height: 8),
                TextField(
                  controller: _customSizeController,
                  autofocus: false,
                  maxLength: 24,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submitCustomSize(),
                  style: _inputStyle,
                  decoration: InputDecoration(
                    hintText: 'Например, 48–50 или рост 134',
                    hintStyle: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 12,
                      fontWeight: AppTypography.medium,
                      color: _secondaryTextColor,
                    ),
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _textColor),
                    ),
                    suffixIcon: IconButton(
                      tooltip: 'Сохранить размер',
                      onPressed: _customSizeController.text.trim().isEmpty
                          ? null
                          : _submitCustomSize,
                      icon: const Icon(Icons.check_rounded, size: 20),
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

class _SizeOptionsWrap extends StatelessWidget {
  const _SizeOptionsWrap({required this.options, required this.selectedValue});

  final List<CatalogOption> options;
  final String selectedValue;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options
          .map((option) {
            final selected = option.id == selectedValue;
            return Material(
              color: selected ? Colors.black : const Color(0xFFF2F2F4),
              borderRadius: BorderRadius.circular(999),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.pop(context, option.id),
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 38,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    option.name,
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 12.5,
                      fontWeight: AppTypography.medium,
                      color: selected ? Colors.white : const Color(0xFF111111),
                      height: 1,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _SheetSectionTitle extends StatelessWidget {
  const _SheetSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontSize: 12.5,
        fontWeight: AppTypography.semiBold,
        color: _textColor,
        letterSpacing: 0,
      ),
    );
  }
}

class _CatalogOptionsSheet extends StatelessWidget {
  const _CatalogOptionsSheet({
    required this.title,
    required this.selectedValue,
    required this.options,
  });

  final String title;
  final String selectedValue;
  final List<CatalogOption> options;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.76,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
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
                  color: _textColor,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: options.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, color: _borderColor),
                  itemBuilder: (context, index) {
                    final option = options[index];
                    final selected = option.id == selectedValue;
                    return InkWell(
                      onTap: () => Navigator.pop(context, option.id),
                      child: SizedBox(
                        height: 52,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                option.name,
                                style: const TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontSize: 14,
                                  fontWeight: AppTypography.medium,
                                  color: _textColor,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                            if (selected)
                              const Icon(
                                Icons.check_rounded,
                                size: 20,
                                color: _textColor,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
