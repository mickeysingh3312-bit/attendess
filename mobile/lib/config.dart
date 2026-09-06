import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const appVersion = '0.3.0';
  static const defaultApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://attendance.example.com/api/mobile',
  );

  static Future<String> apiBaseUrl() async {
    final preferences = await SharedPreferences.getInstance();
    return normalizeApiBaseUrl(
      preferences.getString('api_base_url') ?? defaultApiBaseUrl,
    );
  }

  static Future<void> setApiBaseUrl(String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('api_base_url', normalizeApiBaseUrl(value));
  }

  static Future<void> resetApiBaseUrl() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('api_base_url');
  }

  static String normalizeApiBaseUrl(String input) {
    var value = input.trim();
    if (value.isEmpty) value = defaultApiBaseUrl;
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'https://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (!value.endsWith('/api/mobile')) {
      value = '$value/api/mobile';
    }
    return value;
  }
}
