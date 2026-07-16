import 'package:clothes/core/oauth_callback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final expectedRedirect = Uri.parse('com.example.clothes://oauth-callback/');

  test('reads Supabase session tokens from OAuth callback fragment', () {
    final callback = Uri.parse(
      'com.example.clothes://oauth-callback/'
      '#access_token=access.jwt&refresh_token=refresh-token'
      '&expires_in=3600&token_type=bearer',
    );

    final tokens = parseOAuthCallback(
      callback,
      expectedRedirect: expectedRedirect,
    );

    expect(tokens.accessToken, 'access.jwt');
    expect(tokens.refreshToken, 'refresh-token');
  });

  test('surfaces provider error returned in OAuth callback', () {
    final callback = Uri.parse(
      'com.example.clothes://oauth-callback/'
      '#error=auth_failed&error_description=Access%20denied',
    );

    expect(
      () => parseOAuthCallback(callback, expectedRedirect: expectedRedirect),
      throwsA(
        isA<OAuthCallbackException>().having(
          (error) => error.message,
          'message',
          'Access denied',
        ),
      ),
    );
  });

  test('rejects callbacks without a complete Supabase session', () {
    final callback = Uri.parse(
      'com.example.clothes://oauth-callback/#access_token=access.jwt',
    );

    expect(
      () => parseOAuthCallback(callback, expectedRedirect: expectedRedirect),
      throwsA(isA<OAuthCallbackException>()),
    );
  });

  test('rejects a callback intended for another deep-link route', () {
    final callback = Uri.parse(
      'com.example.clothes://login-callback/'
      '#access_token=access.jwt&refresh_token=refresh-token',
    );

    expect(
      () => parseOAuthCallback(callback, expectedRedirect: expectedRedirect),
      throwsA(isA<OAuthCallbackException>()),
    );
  });
}
