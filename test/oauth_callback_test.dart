import 'package:clothes/core/oauth_callback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final expectedRedirect = Uri.parse('com.example.clothes://oauth-callback/');

  test('reads a provider-bound one-time exchange code from the callback', () {
    final callback = Uri.parse(
      'com.example.clothes://oauth-callback/'
      '?oauth_code=one-time-code&oauth_provider=yandex',
    );

    final exchange = parseOAuthExchangeCallback(
      callback,
      expectedRedirect: expectedRedirect,
      expectedProvider: 'yandex',
    );

    expect(exchange.code, 'one-time-code');
    expect(exchange.provider, 'yandex');
  });

  test('surfaces provider error returned in OAuth callback', () {
    final callback = Uri.parse(
      'com.example.clothes://oauth-callback/'
      '?error=auth_failed&error_description=Access%20denied',
    );

    expect(
      () => parseOAuthExchangeCallback(
        callback,
        expectedRedirect: expectedRedirect,
        expectedProvider: 'yandex',
      ),
      throwsA(
        isA<OAuthCallbackException>().having(
          (error) => error.message,
          'message',
          'Access denied',
        ),
      ),
    );
  });

  test('rejects callbacks without an exchange code', () {
    final callback = Uri.parse(
      'com.example.clothes://oauth-callback/?oauth_provider=yandex',
    );

    expect(
      () => parseOAuthExchangeCallback(
        callback,
        expectedRedirect: expectedRedirect,
        expectedProvider: 'yandex',
      ),
      throwsA(isA<OAuthCallbackException>()),
    );
  });

  test('rejects a callback intended for another deep-link route', () {
    final callback = Uri.parse(
      'com.example.clothes://login-callback/'
      '?oauth_code=one-time-code&oauth_provider=yandex',
    );

    expect(
      () => parseOAuthExchangeCallback(
        callback,
        expectedRedirect: expectedRedirect,
        expectedProvider: 'yandex',
      ),
      throwsA(isA<OAuthCallbackException>()),
    );
  });

  test('rejects an exchange code issued for another provider', () {
    final callback = Uri.parse(
      'com.example.clothes://oauth-callback/'
      '?oauth_code=one-time-code&oauth_provider=vk',
    );

    expect(
      () => parseOAuthExchangeCallback(
        callback,
        expectedRedirect: expectedRedirect,
        expectedProvider: 'yandex',
      ),
      throwsA(isA<OAuthCallbackException>()),
    );
  });
}
