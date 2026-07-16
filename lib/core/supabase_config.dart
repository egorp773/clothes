import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String url = 'https://hbwzxtwcjlsfldjcqudt.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imhid3p4dHdjamxzZmxkamNxdWR0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg3NzMxOTAsImV4cCI6MjA5NDM0OTE5MH0.zsT_O_08sQWvAaKcj9P8qzgTLg_2KvRsvM6qfibwQAw';
  static const String authRedirectUri = 'com.example.clothes://login-callback/';
  static const String oauthRedirectUri =
      'com.example.clothes://oauth-callback/';
  static const String yandexProvider = 'custom:yandex';
  static const String yandexAuthUrl = '$url/functions/v1/yandex-auth';
  static const String vkAuthUrl = '$url/functions/v1/vk-auth';
  static const String telegramAuthUrl = '$url/functions/v1/telegram-auth';
  static const String telegramBotId = '8941747263';
  static const String telegramOrigin =
      'https://hbwzxtwcjlsfldjcqudt.supabase.co';
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.implicit,
      ),
      debug: false,
    );
    _isInitialized = true;
  }

  static bool get isInitialized => _isInitialized;

  static SupabaseClient get client => Supabase.instance.client;
}
