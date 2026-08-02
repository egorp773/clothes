import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_appearance.dart';

const russianMonthNames = <String>[
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

const _loopCycles = 1000;

String formatRussianDate(DateTime date) {
  return '${date.day} ${russianMonthNames[date.month - 1]} ${date.year}';
}

Future<DateTime?> showBirthDateWheelPicker(
  BuildContext context, {
  DateTime? initialDate,
  DateTime? today,
}) {
  final maximumDate = DateUtils.dateOnly(today ?? DateTime.now());
  final minimumDate = DateTime(1900);
  final fallbackDate = DateTime(
    maximumDate.year - 18,
    maximumDate.month,
    maximumDate.day,
  );
  final effectiveInitialDate = _clampDate(
    DateUtils.dateOnly(initialDate ?? fallbackDate),
    minimumDate,
    maximumDate,
  );

  return showModalBottomSheet<DateTime>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (sheetContext) => BirthDateWheelPicker(
      initialDate: effectiveInitialDate,
      minimumDate: minimumDate,
      maximumDate: maximumDate,
      onCancel: () => Navigator.of(sheetContext).pop(),
      onConfirm: (date) => Navigator.of(sheetContext).pop(date),
    ),
  );
}

class BirthDateWheelPicker extends StatefulWidget {
  BirthDateWheelPicker({
    super.key,
    required this.initialDate,
    required this.minimumDate,
    required this.maximumDate,
    required this.onCancel,
    required this.onConfirm,
  }) : assert(!maximumDate.isBefore(minimumDate));

  final DateTime initialDate;
  final DateTime minimumDate;
  final DateTime maximumDate;
  final VoidCallback onCancel;
  final ValueChanged<DateTime> onConfirm;

  @override
  State<BirthDateWheelPicker> createState() => _BirthDateWheelPickerState();
}

class _BirthDateWheelPickerState extends State<BirthDateWheelPicker> {
  static const _itemExtent = 44.0;

  late final List<int> _years;
  late final FixedExtentScrollController _dayController;
  late final FixedExtentScrollController _monthController;
  late final FixedExtentScrollController _yearController;
  late int _day;
  late int _month;
  late int _year;

  DateTime get _minimumDate => DateUtils.dateOnly(widget.minimumDate);
  DateTime get _maximumDate => DateUtils.dateOnly(widget.maximumDate);
  DateTime get _selectedDate => DateTime(_year, _month, _day);

  String? get _validationMessage {
    final selected = _selectedDate;
    if (selected.isAfter(_maximumDate)) {
      return 'Дата рождения не может быть в будущем';
    }
    if (selected.isBefore(_minimumDate)) {
      return 'Выберите дату не раньше 1900 года';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final initial = _clampDate(
      DateUtils.dateOnly(widget.initialDate),
      _minimumDate,
      _maximumDate,
    );
    _day = initial.day;
    _month = initial.month;
    _year = initial.year;
    _years = <int>[
      for (var year = _maximumDate.year; year >= _minimumDate.year; year--)
        year,
    ];

    _dayController = FixedExtentScrollController(
      initialItem: _loopingInitialItem(_day - 1, 31),
    );
    _monthController = FixedExtentScrollController(
      initialItem: _loopingInitialItem(_month - 1, 12),
    );
    _yearController = FixedExtentScrollController(
      initialItem: _loopingInitialItem(_years.indexOf(_year), _years.length),
    );
  }

  @override
  void dispose() {
    _dayController.dispose();
    _monthController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final validationMessage = _validationMessage;
    return Material(
      color: Colors.transparent,
      child: Container(
        key: const Key('birth-date-wheel-sheet'),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  TextButton(
                    key: const Key('birth-date-cancel'),
                    onPressed: widget.onCancel,
                    child: const Text('Отмена'),
                  ),
                  Expanded(
                    child: Text(
                      'Дата рождения',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: palette.ink,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const Key('birth-date-confirm'),
                    onPressed: validationMessage == null
                        ? () => widget.onConfirm(_selectedDate)
                        : null,
                    child: const Text('Готово'),
                  ),
                ],
              ),
            ),
            Text(
              formatRussianDate(_selectedDate),
              key: const Key('birth-date-selection'),
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: palette.muted,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: const [
                Expanded(child: _WheelLabel('день')),
                Expanded(flex: 2, child: _WheelLabel('месяц')),
                Expanded(child: _WheelLabel('год')),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 198,
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      height: _itemExtent,
                      decoration: BoxDecoration(
                        color: palette.surfaceMuted,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: palette.border),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _buildPicker(
                          key: const Key('birth-date-day-picker'),
                          controller: _dayController,
                          children: [
                            for (var day = 1; day <= 31; day++)
                              _WheelItem(day.toString().padLeft(2, '0')),
                          ],
                          onSelectedItemChanged: (index) =>
                              _updateSelection(day: index + 1),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: _buildPicker(
                          key: const Key('birth-date-month-picker'),
                          controller: _monthController,
                          children: [
                            for (final month in russianMonthNames)
                              _WheelItem(month),
                          ],
                          onSelectedItemChanged: (index) =>
                              _updateSelection(month: index + 1),
                        ),
                      ),
                      Expanded(
                        child: _buildPicker(
                          key: const Key('birth-date-year-picker'),
                          controller: _yearController,
                          children: [
                            for (final year in _years)
                              _WheelItem(year.toString()),
                          ],
                          onSelectedItemChanged: (index) =>
                              _updateSelection(year: _years[index]),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: validationMessage == null
                  ? const SizedBox(key: Key('birth-date-valid'), height: 20)
                  : SizedBox(
                      key: const Key('birth-date-error'),
                      height: 20,
                      child: Text(
                        validationMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFF453A),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPicker({
    required Key key,
    required FixedExtentScrollController controller,
    required List<Widget> children,
    required ValueChanged<int> onSelectedItemChanged,
  }) {
    return CupertinoPicker(
      key: key,
      scrollController: controller,
      itemExtent: _itemExtent,
      looping: true,
      useMagnifier: true,
      magnification: 1.06,
      diameterRatio: 1.25,
      squeeze: 1.05,
      selectionOverlay: null,
      backgroundColor: Colors.transparent,
      onSelectedItemChanged: onSelectedItemChanged,
      children: children,
    );
  }

  void _updateSelection({int? day, int? month, int? year}) {
    final nextMonth = month ?? _month;
    final nextYear = year ?? _year;
    final requestedDay = day ?? _day;
    final nextDay = math.min(requestedDay, _daysInMonth(nextYear, nextMonth));
    final shouldSyncDay =
        requestedDay != nextDay || (day == null && _day != nextDay);

    setState(() {
      _day = nextDay;
      _month = nextMonth;
      _year = nextYear;
    });

    if (shouldSyncDay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_dayController.hasClients) return;
        _jumpToNearestItem(_dayController, _day - 1, 31);
      });
    }
  }
}

class _WheelLabel extends StatelessWidget {
  const _WheelLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: 'Montserrat',
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: context.appPalette.muted,
      ),
    );
  }
}

class _WheelItem extends StatelessWidget {
  const _WheelItem(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: context.appPalette.ink,
        ),
      ),
    );
  }
}

DateTime _clampDate(DateTime value, DateTime minimum, DateTime maximum) {
  if (value.isBefore(minimum)) return minimum;
  if (value.isAfter(maximum)) return maximum;
  return value;
}

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

int _loopingInitialItem(int logicalIndex, int itemCount) {
  return itemCount * _loopCycles + logicalIndex;
}

void _jumpToNearestItem(
  FixedExtentScrollController controller,
  int logicalIndex,
  int itemCount,
) {
  final current = controller.selectedItem;
  final cycleStart = current - (current % itemCount);
  final candidates = <int>[
    cycleStart + logicalIndex - itemCount,
    cycleStart + logicalIndex,
    cycleStart + logicalIndex + itemCount,
  ];
  candidates.sort((a, b) => (a - current).abs().compareTo((b - current).abs()));
  controller.jumpToItem(candidates.first);
}
