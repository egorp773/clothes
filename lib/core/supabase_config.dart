import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';

class SupabaseConfig {
  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String appUrlScheme = String.fromEnvironment(
    'APP_URL_SCHEME',
    defaultValue: 'com.example.clothes',
  );
  static const String publicWebBaseUrl = String.fromEnvironment(
    'PUBLIC_WEB_BASE_URL',
    defaultValue: 'https://clothes.app',
  );

  static String productShareUrl(String productId) =>
      '${publicWebBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/products/$productId';

  static String outfitShareUrl(String outfitId) =>
      '${publicWebBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/outfits/$outfitId';
  static const String authRedirectUri = '$appUrlScheme://login-callback/';
  static const String oauthRedirectUri = '$appUrlScheme://oauth-callback/';
  static const String yandexProvider = 'custom:yandex';
  static const String yandexAuthUrl = '$url/functions/v1/yandex-auth';
  static const String vkAuthUrl = '$url/functions/v1/vk-auth';
  static const String telegramAuthUrl = '$url/functions/v1/telegram-auth';
  static const String telegramBotId = String.fromEnvironment('TELEGRAM_BOT_ID');
  static const String telegramOrigin = url;
  static bool _isInitialized = false;
  static String? _configurationError;

  static bool isValidConfiguration({
    required String url,
    required String anonKey,
  }) {
    final normalizedUrl = url.trim();
    final parsed = Uri.tryParse(normalizedUrl);
    return normalizedUrl.isNotEmpty &&
        anonKey.trim().isNotEmpty &&
        parsed != null &&
        parsed.scheme == 'https' &&
        parsed.host.isNotEmpty;
  }

  static bool get isConfigured =>
      isValidConfiguration(url: url, anonKey: anonKey);

  static Future<void> initialize() async {
    if (!isConfigured) {
      _isInitialized = false;
      _configurationError =
          'SUPABASE_URL and SUPABASE_ANON_KEY dart-defines are required';
      if (kDebugMode && AppConfig.allowUnsafeLocalDemo) return;
      throw StateError(_configurationError!);
    }
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
      debug: false,
    );
    _isInitialized = true;
    _configurationError = null;
  }

  static bool get isInitialized => _isInitialized;
  static String? get configurationError => _configurationError;

  static SupabaseClient get client => Supabase.instance.client;
}
