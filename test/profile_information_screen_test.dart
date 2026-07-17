import 'package:clothes/screens/profile_feature_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FAQ explains views and pickup point addresses', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileInformationScreen(topic: ProfileInformationTopic.faq),
      ),
    );

    expect(find.text('Когда считается просмотр?'), findsOneWidget);
    await tester.tap(find.text('Когда считается просмотр?'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Простое пролистывание каталога'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text('Какой адрес нужен для пункта выдачи?'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Какой адрес нужен для пункта выдачи?'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Домашний адрес и пункт выдачи'),
      findsOneWidget,
    );
  });

  testWidgets('documents screen exposes an honest publication status', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileInformationScreen(
          topic: ProfileInformationTopic.documents,
        ),
      ),
    );

    expect(find.text('Юридические тексты ещё не опубликованы'), findsOneWidget);
    expect(find.text('Политика конфиденциальности'), findsOneWidget);
    expect(find.text('ДО РЕЛИЗА'), findsNWidgets(5));
  });
}
