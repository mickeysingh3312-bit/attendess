class AppConfig {
  static const appVersion = '0.7.0';
  static const versionCode = 16;
  static const productionApiBaseUrl =
      'https://attendees.fivestaraccess.com.au/public/api/mobile';

  static Future<String> apiBaseUrl() async => productionApiBaseUrl;
}
