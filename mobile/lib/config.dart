class AppConfig {
  static const appVersion = '0.4.4';
  static const productionApiBaseUrl =
      'https://attendees.fivestaraccess.com.au/public/api/mobile';

  static Future<String> apiBaseUrl() async => productionApiBaseUrl;
}
