class AppConfig {
  static const appVersion = '0.6.3';
  static const productionApiBaseUrl =
      'https://attendees.fivestaraccess.com.au/public/api/mobile';

  static Future<String> apiBaseUrl() async => productionApiBaseUrl;
}
