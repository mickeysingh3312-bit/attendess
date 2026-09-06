import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class ApiClient {
  Future<String?> token() async =>
      (await SharedPreferences.getInstance()).getString('token');

  Future<Map<String, dynamic>> requestOtp(
    String email,
    String deviceUuid,
  ) async {
    final baseUrl = await AppConfig.apiBaseUrl();
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/request-otp'),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'email': email.trim().toLowerCase(),
            'device_uuid': deviceUuid,
          }),
        )
        .timeout(const Duration(seconds: 25));

    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> verifyOtp(
    String email,
    String otp,
    String deviceUuid,
  ) async {
    final baseUrl = await AppConfig.apiBaseUrl();
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/verify-otp'),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'email': email.trim().toLowerCase(),
            'otp': otp.trim(),
            'device_uuid': deviceUuid,
            'platform': 'android',
            'app_version': AppConfig.appVersion,
          }),
        )
        .timeout(const Duration(seconds: 25));

    final data = _decodeResponse(response);
    final authToken = data['token']?.toString();
    if (authToken == null || authToken.isEmpty) {
      throw Exception('The server did not return a login token.');
    }

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('token', authToken);
    await preferences.setString('user_email', email.trim().toLowerCase());
    return data;
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    final authToken = await token();
    if (authToken == null || authToken.isEmpty) {
      throw Exception('Please sign in again.');
    }

    final baseUrl = await AppConfig.apiBaseUrl();
    final response = await http
        .get(
          Uri.parse('$baseUrl$path'),
          headers: {
            'Authorization': 'Bearer $authToken',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 25));

    if (response.statusCode == 401) {
      throw Exception('Your session has expired. Please sign in again.');
    }
    return _decodeResponse(response);
  }

  Future<void> logout() async {
    final authToken = await token();
    if (authToken == null || authToken.isEmpty) return;

    try {
      final baseUrl = await AppConfig.apiBaseUrl();
      await http
          .post(
            Uri.parse('$baseUrl/logout'),
            headers: {
              'Authorization': 'Bearer $authToken',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Local sign-out must still work if the network is unavailable.
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Map<String, dynamic> data = <String, dynamic>{};
    if (response.body.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {
        // A non-JSON response is handled by the generic status message below.
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) return data;

    String? message;
    final errors = data['errors'];
    if (errors is Map) {
      for (final value in errors.values) {
        if (value is List && value.isNotEmpty) {
          message = value.first.toString();
          break;
        }
        if (value != null) {
          message = value.toString();
          break;
        }
      }
    }
    message ??= data['message']?.toString();
    message ??= 'Request failed (${response.statusCode}). Please try again.';
    throw Exception(message);
  }
}
