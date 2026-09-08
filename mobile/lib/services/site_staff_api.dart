import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class SiteStaffApi {
  Future<Map<String, dynamic>> profile() async {
    final token = await _token();
    final baseUrl = await AppConfig.apiBaseUrl();
    final response = await http
        .get(
          Uri.parse('$baseUrl/site-staff/profile'),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 35));
    return _decode(response.statusCode, response.body);
  }

  Future<Map<String, dynamic>> saveProfile({
    required bool updating,
    required Map<String, String> fields,
    required Map<String, PlatformFile?> files,
    required Map<String, bool> removeFlags,
  }) async {
    final token = await _token();
    final baseUrl = await AppConfig.apiBaseUrl();
    final path = updating ? '/site-staff/profile/update' : '/site-staff/profile';
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    });
    request.fields.addAll(fields);
    for (final entry in removeFlags.entries) {
      request.fields[entry.key] = entry.value ? '1' : '0';
    }

    for (final entry in files.entries) {
      final file = entry.value;
      if (file == null || file.path == null || file.path!.isEmpty) continue;
      request.files.add(
        await http.MultipartFile.fromPath(
          entry.key,
          file.path!,
          filename: file.name,
        ),
      );
    }

    final streamed = await request.send().timeout(const Duration(seconds: 90));
    final response = await http.Response.fromStream(streamed);
    return _decode(response.statusCode, response.body);
  }

  Future<String> _token() async {
    final token = (await SharedPreferences.getInstance()).getString('token');
    if (token == null || token.isEmpty) {
      throw Exception('Please sign in again.');
    }
    return token;
  }

  Map<String, dynamic> _decode(int statusCode, String body) {
    Map<String, dynamic> data = <String, dynamic>{};
    if (body.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {}
    }

    if (statusCode >= 200 && statusCode < 300) return data;

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
    message ??= 'Request failed ($statusCode). Please try again.';
    throw Exception(message);
  }
}
