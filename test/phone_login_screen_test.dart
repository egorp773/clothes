import 'package:clothes/screens/phone_login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('requests and verifies a phone OTP', (tester) async {
    var requestedPhone = '';
    var verifiedPhone = '';
    var verifiedCode = '';
    var closed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: PhoneLoginScreen(
          onBack: () {},
          onClose: () => closed = true,
          onRequestCode: (phone) async {
            requestedPhone = phone;
            return null;
          },
          onVerifyCode: (phone, code) async {
            verifiedPhone = phone;
            verifiedCode = code;
            return null;
          },
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '9991234567');
    await tester.tap(find.text('ПОЛУЧИТЬ КОД'));
    await tester.pump();

    expect(requestedPhone, '+79991234567');
    expect(find.text('введите код подтверждения'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('ВОЙТИ'));
    await tester.pump();

    expect(verifiedPhone, '+79991234567');
    expect(verifiedCode, '123456');
    expect(closed, isTrue);
  });

  testWidgets('does not request a code for an incomplete phone', (
    tester,
  ) async {
    var requestCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PhoneLoginScreen(
          onBack: () {},
          onClose: () {},
          onRequestCode: (_) async {
            requestCount += 1;
            return null;
          },
          onVerifyCode: (_, _) async => null,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '999');
    await tester.tap(find.text('ПОЛУЧИТЬ КОД'));
    await tester.pump();

    expect(requestCount, 0);
    expect(find.text('Введите 10 цифр номера телефона'), findsOneWidget);
  });

  testWidgets('accepts a pasted phone with the Russian country code', (
    tester,
  ) async {
    var requestedPhone = '';
    await tester.pumpWidget(
      MaterialApp(
        home: PhoneLoginScreen(
          onBack: () {},
          onClose: () {},
          onRequestCode: (phone) async {
            requestedPhone = phone;
            return null;
          },
          onVerifyCode: (_, _) async => null,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '+7 (999) 123-45-67');
    await tester.tap(find.text('ПОЛУЧИТЬ КОД'));
    await tester.pump();

    expect(requestedPhone, '+79991234567');
    expect(find.text('введите код подтверждения'), findsOneWidget);
  });

  testWidgets('recovers after a request callback throws', (tester) async {
    var requestCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PhoneLoginScreen(
          onBack: () {},
          onClose: () {},
          onRequestCode: (_) async {
            requestCount += 1;
            if (requestCount == 1) throw StateError('offline');
            return null;
          },
          onVerifyCode: (_, _) async => null,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '9991234567');
    await tester.tap(find.text('ПОЛУЧИТЬ КОД'));
    await tester.pump();

    expect(
      find.text('Не удалось отправить код. Попробуйте ещё раз'),
      findsOneWidget,
    );
    expect(find.text('ПОЛУЧИТЬ КОД'), findsOneWidget);

    await tester.tap(find.text('ПОЛУЧИТЬ КОД'));
    await tester.pump();
    expect(requestCount, 2);
    expect(find.text('введите код подтверждения'), findsOneWidget);
  });
}
