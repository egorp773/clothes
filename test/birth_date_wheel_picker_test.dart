import 'package:clothes/widgets/birth_date_wheel_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats a date with a Russian month name', () {
    expect(formatRussianDate(DateTime(2001, 8, 2)), '2 августа 2001');
  });

  testWidgets('shows cyclic day, month and year wheels in that order', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BirthDateWheelPicker(
            initialDate: DateTime(2000, 1, 31),
            minimumDate: DateTime(1900),
            maximumDate: DateTime(2026, 8, 2),
            onCancel: () {},
            onConfirm: (_) {},
          ),
        ),
      ),
    );

    final day = find.byKey(const Key('birth-date-day-picker'));
    final month = find.byKey(const Key('birth-date-month-picker'));
    final year = find.byKey(const Key('birth-date-year-picker'));
    expect(day, findsOneWidget);
    expect(month, findsOneWidget);
    expect(year, findsOneWidget);
    expect(tester.getTopLeft(day).dx, lessThan(tester.getTopLeft(month).dx));
    expect(tester.getTopLeft(month).dx, lessThan(tester.getTopLeft(year).dx));

    for (final finder in [day, month, year]) {
      final picker = tester.widget<CupertinoPicker>(finder);
      expect(picker.childDelegate, isA<ListWheelChildLoopingListDelegate>());
    }
    expect(find.text('января'), findsOneWidget);
    expect(find.text('февраля'), findsOneWidget);
  });

  testWidgets('clamps the day when the selected month is shorter', (
    tester,
  ) async {
    DateTime? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BirthDateWheelPicker(
            initialDate: DateTime(2000, 1, 31),
            minimumDate: DateTime(1900),
            maximumDate: DateTime(2026, 8, 2),
            onCancel: () {},
            onConfirm: (date) => confirmed = date,
          ),
        ),
      ),
    );

    final monthPicker = tester.widget<CupertinoPicker>(
      find.byKey(const Key('birth-date-month-picker')),
    );
    monthPicker.onSelectedItemChanged!(1);
    await tester.pump();

    expect(find.text('29 февраля 2000'), findsOneWidget);
    final dayPicker = tester.widget<CupertinoPicker>(
      find.byKey(const Key('birth-date-day-picker')),
    );
    expect(dayPicker.scrollController!.selectedItem % 31, 28);

    final yearPicker = tester.widget<CupertinoPicker>(
      find.byKey(const Key('birth-date-year-picker')),
    );
    yearPicker.onSelectedItemChanged!(2026 - 2001);
    await tester.pump();

    expect(find.text('28 февраля 2001'), findsOneWidget);
    expect(dayPicker.scrollController!.selectedItem % 31, 27);
    await tester.tap(find.byKey(const Key('birth-date-confirm')));
    expect(confirmed, DateTime(2001, 2, 28));
  });

  testWidgets('does not confirm a future date', (tester) async {
    DateTime? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BirthDateWheelPicker(
            initialDate: DateTime(2026, 8, 2),
            minimumDate: DateTime(1900),
            maximumDate: DateTime(2026, 8, 2),
            onCancel: () {},
            onConfirm: (date) => confirmed = date,
          ),
        ),
      ),
    );

    final monthPicker = tester.widget<CupertinoPicker>(
      find.byKey(const Key('birth-date-month-picker')),
    );
    monthPicker.onSelectedItemChanged!(11);
    await tester.pump();

    expect(find.text('Дата рождения не может быть в будущем'), findsOneWidget);
    final confirm = tester.widget<TextButton>(
      find.byKey(const Key('birth-date-confirm')),
    );
    expect(confirm.onPressed, isNull);
    expect(confirmed, isNull);
  });

  testWidgets('an invalid day snaps to the last day of the month', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BirthDateWheelPicker(
            initialDate: DateTime(2001, 2, 28),
            minimumDate: DateTime(1900),
            maximumDate: DateTime(2026, 8, 2),
            onCancel: () {},
            onConfirm: (_) {},
          ),
        ),
      ),
    );

    final dayPicker = tester.widget<CupertinoPicker>(
      find.byKey(const Key('birth-date-day-picker')),
    );
    final currentItem = dayPicker.scrollController!.selectedItem;
    dayPicker.scrollController!.jumpToItem(
      currentItem - (currentItem % 31) + 30,
    );
    dayPicker.onSelectedItemChanged!(30);
    await tester.pump();

    expect(find.text('28 февраля 2001'), findsOneWidget);
    expect(dayPicker.scrollController!.selectedItem % 31, 27);
  });
}
