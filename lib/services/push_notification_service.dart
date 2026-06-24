import 'package:flutter/foundation.dart';

const String pushMessagesChannelId = 'messages';
const String pushMessagesChannelName = 'Сообщения';

class PushNotificationService {
  PushNotificationService._();

  static bool get isEnabled => false;

  static Future<String?> currentToken() async => null;

  static Stream<String> get onTokenRefresh => const Stream.empty();

  static Future<void> deleteToken() async {}

  static String get platform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }
}
