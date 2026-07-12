class AppConfig {
  const AppConfig._();

  static const productAnalyzerUrl = String.fromEnvironment(
    'PRODUCT_ANALYZER_URL',
    defaultValue: 'https://109.172.37.219.sslip.io',
  );
}
