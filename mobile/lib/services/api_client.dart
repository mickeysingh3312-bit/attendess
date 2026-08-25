import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class ApiClient {
  Future<String?> token() async => (await SharedPreferences.getInstance()).getString('token');
  Future<Map<String, dynamic>> login(String email, String password, String deviceUuid) async {
    final response = await http.post(Uri.parse('${AppConfig.apiBaseUrl}/login'), headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'}, body: jsonEncode({'email': email, 'password': password, 'device_uuid': deviceUuid, 'platform': 'android', 'app_version': AppConfig.appVersion})).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Login failed (${response.statusCode})');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final p = await SharedPreferences.getInstance();
    await p.setString('token', data['token'].toString());
    return data;
  }
  Future<Map<String, dynamic>> getJson(String path) async {
    final t = await token();
    if (t == null) throw Exception('Please sign in again.');
    final response = await http.get(Uri.parse('${AppConfig.apiBaseUrl}$path'), headers: {'Authorization': 'Bearer $t', 'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('API error ${response.statusCode}');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
