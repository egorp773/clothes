import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase configuration supplied at build time through `--dart-define`.
///
/// No Firebase project credentials are stored in the repository. Android and
/// iOS can use different app registrations while sharing the same project and
/// messaging sender.
abstract final class RuntimeFirebaseConfig {
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const _genericApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _genericAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _androidApiKey = String.fromEnvironment(
    'FIREBASE_ANDROID_API_KEY',
  );
  static const _androidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
  );
  static const _iosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY');
  static const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const _iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');
  static const _androidClientId = String.fromEnvironment(
    'FIREBASE_ANDROID_CLIENT_ID',
  );
  static const _iosClientId = String.fromEnvironment('FIREBASE_IOS_CLIENT_ID');
  static const _authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const _storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );
  static const _measurementId = String.fromEnvironment(
    'FIREBASE_MEASUREMENT_ID',
  );

  static bool get supportsCurrentPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static FirebaseOptions? get currentPlatform {
    if (!supportsCurrentPlatform) return null;

    final isApple = defaultTargetPlatform == TargetPlatform.iOS;
    final apiKey = _firstNotEmpty(
      isApple ? _iosApiKey : _androidApiKey,
      _genericApiKey,
    );
    final appId = _firstNotEmpty(
      isApple ? _iosAppId : _androidAppId,
      _genericAppId,
    );
    if (apiKey.isEmpty ||
        appId.isEmpty ||
        _senderId.isEmpty ||
        _projectId.isEmpty) {
      return null;
    }

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: _senderId,
      projectId: _projectId,
      authDomain: _nullable(_authDomain),
      storageBucket: _nullable(_storageBucket),
      measurementId: _nullable(_measurementId),
      androidClientId: _nullable(_androidClientId),
      iosClientId: _nullable(_iosClientId),
      iosBundleId: isApple ? _nullable(_iosBundleId) : null,
    );
  }

  static bool get isConfigured => currentPlatform != null;

  static String _firstNotEmpty(String preferred, String fallback) =>
      preferred.trim().isNotEmpty ? preferred.trim() : fallback.trim();

  static String? _nullable(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}
