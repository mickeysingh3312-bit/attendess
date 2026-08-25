class AppConfig {
  static const appVersion = '0.2.0';
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://attendance.example.com/api/mobile');
}
