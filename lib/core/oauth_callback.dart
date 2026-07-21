class OAuthExchangeCode {
  const OAuthExchangeCode({required this.code, required this.provider});

  final String code;
  final String provider;
}

class OAuthCallbackException implements Exception {
  const OAuthCallbackException(this.message);

  final String message;

  @override
  String toString() => message;
}

OAuthExchangeCode parseOAuthExchangeCallback(
  Uri callback, {
  required Uri expectedRedirect,
  required String expectedProvider,
}) {
  if (!_matchesRedirect(callback, expectedRedirect)) {
    throw const OAuthCallbackException('Unexpected OAuth redirect URI');
  }
  final error =
      callback.queryParameters['error_description']?.trim() ??
      callback.queryParameters['oauth_error']?.trim() ??
      callback.queryParameters['error']?.trim();
  if (error?.isNotEmpty == true) {
    throw OAuthCallbackException(error!);
  }
  final code = callback.queryParameters['oauth_code']?.trim() ?? '';
  final provider =
      callback.queryParameters['oauth_provider']?.trim().toLowerCase() ?? '';
  if (code.isEmpty) {
    throw const OAuthCallbackException('OAuth exchange code is missing');
  }
  if (provider != expectedProvider.trim().toLowerCase()) {
    throw const OAuthCallbackException('Unexpected OAuth provider');
  }
  return OAuthExchangeCode(code: code, provider: provider);
}

bool _matchesRedirect(Uri callback, Uri expectedRedirect) {
  return callback.scheme.toLowerCase() ==
          expectedRedirect.scheme.toLowerCase() &&
      callback.host.toLowerCase() == expectedRedirect.host.toLowerCase() &&
      _normalizedPath(callback.path) == _normalizedPath(expectedRedirect.path);
}

String _normalizedPath(String path) {
  if (path.isEmpty) return '/';
  return path.endsWith('/') ? path : '$path/';
}
