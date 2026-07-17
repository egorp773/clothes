import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test(
    'Android release permissions and hardware declarations are explicit',
    () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      final network = read(
        'android/app/src/main/res/xml/network_security_config.xml',
      );
      final debugNetwork = read(
        'android/app/src/debug/res/xml/network_security_config.xml',
      );

      for (final permission in <String>[
        'android.permission.CAMERA',
        'android.permission.RECORD_AUDIO',
        'android.permission.POST_NOTIFICATIONS',
        'android.permission.READ_MEDIA_IMAGES',
        'android.permission.READ_MEDIA_VIDEO',
      ]) {
        expect(manifest, contains(permission));
      }
      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
      expect(
        RegExp(
          r'android:name="android\.hardware\.(?:camera\.any|microphone)"\s+'
          r'android:required="false"',
        ).allMatches(manifest),
        hasLength(2),
      );
      expect(network, contains('cleartextTrafficPermitted="false"'));
      expect(network, isNot(contains('localhost')));
      expect(debugNetwork, contains('localhost'));
    },
  );

  test('iOS privacy prompts and push environments are release-safe', () {
    final info = read('ios/Runner/Info.plist');
    final entitlements = read('ios/Runner/Runner.entitlements');
    final project = read('ios/Runner.xcodeproj/project.pbxproj');

    for (final key in <String>[
      'NSCameraUsageDescription',
      'NSMicrophoneUsageDescription',
      'NSPhotoLibraryUsageDescription',
      'NSPhotoLibraryAddUsageDescription',
    ]) {
      expect(info, contains('<key>$key</key>'));
    }
    expect(info, isNot(contains('NSAllowsArbitraryLoads')));
    expect(entitlements, contains(r'$(APS_ENVIRONMENT)'));
    expect(project, contains('APS_ENVIRONMENT = development;'));
    expect('APS_ENVIRONMENT = production;'.allMatches(project), hasLength(2));
  });

  test('manual IPA workflow cannot package an unsigned app as an IPA', () {
    final workflow = read('.github/workflows/build_ipa.yml');

    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, isNot(contains('\n  push:')));
    expect(workflow, contains('environment: ios-release'));
    expect(workflow, contains('runs-on: macos-26'));
    expect(workflow, contains('XCODE_MAJOR'));
    expect(workflow, contains('IOS_SDK_MAJOR'));
    expect(workflow, contains('flutter build ipa --release'));
    expect(workflow, isNot(contains('--no-codesign')));
    expect(workflow, contains('codesign --verify --deep --strict'));
    expect(workflow, contains('Provisioning profile bundle mismatch'));
    expect(workflow, contains('IOS_RELEASE_DART_DEFINES_BASE64'));
    expect(workflow, contains('actions/upload-artifact@ea165f8d'));

    for (final file in Directory('.github/workflows').listSync()) {
      if (file is! File || !file.path.endsWith('.yml')) continue;
      if (file.path.endsWith('build_sideloadly_ipa.yml')) continue;
      final source = file.readAsStringSync();
      final fakesUnsignedIpa =
          source.contains('--no-codesign') &&
          source.contains('Payload') &&
          source.contains('.ipa');
      expect(fakesUnsignedIpa, isFalse, reason: file.path);
    }
  });

  test('Sideloadly IPA is an explicit manual unsigned artifact', () {
    final workflow = read('.github/workflows/build_sideloadly_ipa.yml');

    expect(workflow, contains('Build unsigned IPA for Sideloadly'));
    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, isNot(contains('\n  push:')));
    expect(workflow, contains('flutter build ios --release --no-codesign'));
    expect(workflow, contains('clothes-sideloadly-'));
    expect(workflow, contains('retention-days: 14'));
  });

  test('release builds never fall back to Android debug signing', () {
    final gradle = read('android/app/build.gradle.kts');

    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    expect(gradle, contains('Release signing is not configured'));
    expect(gradle, contains('ANDROID_KEYSTORE_PATH'));
  });
}
