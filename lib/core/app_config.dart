import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig._();

  static const productAnalyzerUrl = String.fromEnvironment(
    'PRODUCT_ANALYZER_URL',
  );
  static const _unsafeLocalDemoRequested = bool.fromEnvironment(
    'ALLOW_UNSAFE_LOCAL_DEMO',
    defaultValue: false,
  );

  /// Local demo data is an explicit debug-only escape hatch. Even an
  /// accidentally supplied release dart-define cannot enable it in production.
  static bool get allowUnsafeLocalDemo =>
      kDebugMode && _unsafeLocalDemoRequested;

  static bool get hasProductAnalyzerUrl {
    final uri = Uri.tryParse(productAnalyzerUrl);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }
}
