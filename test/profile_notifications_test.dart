import 'package:clothes/models/profile_feature.dart';
import 'package:clothes/screens/profile_feature_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('notification center groups items and marks all as read', (
    tester,
  ) async {
    var markedAll = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileNotificationsScreen(
          notifications: [
            ProfileNotification(
              id: 'notification-1',
              title: 'Заказ отправлен',
              body: 'Доставка уже в пути',
              kind: 'order',
              createdAt: DateTime.now().toUtc(),
            ),
            ProfileNotification(
              id: 'notification-message',
              title: 'Новое сообщение',
              body: 'Здравствуйте!',
              kind: 'message',
              createdAt: DateTime.now().toUtc(),
            ),
          ],
          onMarkRead: (_) async {},
          onMarkAllRead: () async => markedAll = true,
          onNotificationTap: (_) async {},
        ),
      ),
    );

    expect(find.text('сегодня'), findsOneWidget);
    expect(find.text('Заказ отправлен'), findsOneWidget);
    expect(find.text('Новое сообщение'), findsNothing);
    await tester.tap(find.text('прочитать все'));
    await tester.pump();

    expect(markedAll, isTrue);
    expect(find.text('прочитать все'), findsNothing);
  });
}
