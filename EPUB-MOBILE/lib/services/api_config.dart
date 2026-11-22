class ApiConfig {
  const ApiConfig._();

  static const String rawBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/',
  );

  static String get baseUrl => normalizeBaseUrl(rawBaseUrl);

  static String normalizeBaseUrl(String value) {
    return value.trim().replaceFirst(RegExp(r'/+$'), '');
  }
}
