import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders catalog screen with unified navigation', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const FashionApp());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.search_rounded), findsWidgets);
  });
}
