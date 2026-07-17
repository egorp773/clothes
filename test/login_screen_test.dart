import 'package:clothes/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the social authentication error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          onClose: () {},
          onYandexTap: () async {},
          onVkTap: () async {},
          onPhoneTap: () {},
          isSigningIn: false,
          authError: 'Не удалось войти через Яндекс ID',
        ),
      ),
    );

    expect(find.byKey(const Key('login-auth-error')), findsOneWidget);
    expect(find.text('Не удалось войти через Яндекс ID'), findsOneWidget);
  });

  testWidgets('disables every login entry point while OAuth is running', (
    tester,
  ) async {
    var yandexCalls = 0;
    var vkCalls = 0;
    var phoneCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          onClose: () {},
          onYandexTap: () async => yandexCalls += 1,
          onVkTap: () async => vkCalls += 1,
          onPhoneTap: () => phoneCalls += 1,
          isSigningIn: true,
        ),
      ),
    );

    expect(find.byKey(const Key('login-auth-loading')), findsOneWidget);
    await tester.tap(find.byKey(const Key('login-yandex')));
    await tester.tap(find.byKey(const Key('login-vk')));
    await tester.tap(find.byKey(const Key('login-phone')));

    expect(yandexCalls, 0);
    expect(vkCalls, 0);
    expect(phoneCalls, 0);
  });
}
