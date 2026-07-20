class AppConfig {
  const AppConfig._();

  static const productAnalyzerUrl = String.fromEnvironment(
    'PRODUCT_ANALYZER_URL',
  );
  static const allowUnsafeLocalDemo = bool.fromEnvironment(
    'ALLOW_UNSAFE_LOCAL_DEMO',
    defaultValue: false,
  );

  static bool get hasProductAnalyzerUrl {
    final uri = Uri.tryParse(productAnalyzerUrl);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }
}
