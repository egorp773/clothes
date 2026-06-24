import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'Firebase options are configured only for Android and iOS.',
        );
    }
  }

  // Replace this file with real values by running:
  // flutterfire configure --out=lib/firebase_options.dart
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'replace-with-firebase-api-key',
    appId: '1:000000000000:android:replace',
    messagingSenderId: '000000000000',
    projectId: 'replace-with-firebase-project-id',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'replace-with-firebase-api-key',
    appId: '1:000000000000:ios:replace',
    messagingSenderId: '000000000000',
    projectId: 'replace-with-firebase-project-id',
    iosBundleId: 'com.example.clothes',
  );
}
