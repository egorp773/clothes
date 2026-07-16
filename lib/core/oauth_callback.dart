class OAuthSessionTokens {
  const OAuthSessionTokens({
    required this.accessToken,
    required this.refreshToken,
  });

  final String accessToken;
  final String refreshToken;
}

class OAuthCallbackException implements Exception {
  const OAuthCallbackException(this.message);

  final String message;

  @override
  String toString() => message;
}

OAuthSessionTokens parseOAuthCallback(
  Uri callback, {
  required Uri expectedRedirect,
}) {
  if (!_matchesRedirect(callback, expectedRedirect)) {
    throw const OAuthCallbackException(
      'Приложение получило неверный адрес возврата',
    );
  }

  final parameters = <String, String>{
    ...callback.queryParameters,
    ..._fragmentParameters(callback.fragment),
  };
  final error = parameters['error']?.trim();
  final errorDescription = parameters['error_description']?.trim();
  if ((error?.isNotEmpty ?? false) || (errorDescription?.isNotEmpty ?? false)) {
    throw OAuthCallbackException(
      errorDescription?.isNotEmpty == true ? errorDescription! : error!,
    );
  }

  final accessToken = parameters['access_token']?.trim() ?? '';
  final refreshToken = parameters['refresh_token']?.trim() ?? '';
  if (accessToken.isEmpty || refreshToken.isEmpty) {
    throw const OAuthCallbackException('Сервис входа не вернул сессию');
  }

  return OAuthSessionTokens(
    accessToken: accessToken,
    refreshToken: refreshToken,
  );
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

Map<String, String> _fragmentParameters(String fragment) {
  if (fragment.isEmpty) return const {};
  try {
    return Uri.splitQueryString(fragment);
  } on FormatException {
    throw const OAuthCallbackException(
      'Сервис входа вернул некорректный ответ',
    );
  }
}
