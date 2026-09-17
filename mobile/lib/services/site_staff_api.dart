import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'document_bridge.dart';

class SiteStaffApi {
  Future<Map<String, dynamic>> profile() async {
    final token = await _token();
    final baseUrl = await AppConfig.apiBaseUrl();
    Object? lastError;

    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final response = await http
            .get(
              Uri.parse('$baseUrl/site-staff/profile'),
              headers: {
                'Authorization': 'Bearer $token',
                'Accept': 'application/json',
                'Cache-Control': 'no-cache',
              },
            )
            .timeout(const Duration(seconds: 25));

        if (response.statusCode >= 500 && attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt * attempt));
          continue;
        }
        return _decode(response.statusCode, response.body);
      } catch (e) {
        if (!_isNetworkError(e)) rethrow;
        lastError = e;
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt * attempt));
        }
      }
    }

    throw Exception(_networkMessage(lastError ?? Exception('network unavailable')));
  }

  Future<Map<String, dynamic>> saveProfile({
    required bool updating,
    required Map<String, String> fields,
    required Map<String, PickedDocument?> files,
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
      if (file == null || file.path.isEmpty) continue;
      request.files.add(
        await http.MultipartFile.fromPath(
          entry.key,
          file.path,
          filename: file.name,
        ),
      );
    }

    try {
      final streamed = await request.send().timeout(const Duration(seconds: 90));
      final response = await http.Response.fromStream(streamed);
      return _decode(response.statusCode, response.body);
    } catch (e) {
      if (_isNetworkError(e)) {
        throw Exception(
          'We could not save your profile because the connection was interrupted. Your existing profile is unchanged. Please reconnect and try again.',
        );
      }
      rethrow;
    }
  }

  Future<String> _token() async {
    final token = (await SharedPreferences.getInstance()).getString('token');
    if (token == null || token.isEmpty) {
      throw Exception('Please sign in again.');
    }
    return token;
  }

  bool _isNetworkError(Object error) {
    if (error is SocketException ||
        error is TimeoutException ||
        error is HandshakeException ||
        error is http.ClientException) {
      return true;
    }
    final text = error.toString().toLowerCase();
    return text.contains('socket') ||
        text.contains('failed host lookup') ||
        text.contains('connection reset') ||
        text.contains('connection refused') ||
        text.contains('connection closed') ||
        text.contains('network is unreachable') ||
        text.contains('timed out') ||
        text.contains('timeout') ||
        text.contains('handshake') ||
        text.contains('clientexception');
  }

  String _networkMessage(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('timed out') || text.contains('timeout')) {
      return 'The attendance server is taking longer than expected. Please try again in a moment.';
    }
    return 'We could not reach the attendance server. Check your internet connection and try again.';
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
    message ??= statusCode >= 500
        ? 'The attendance server is temporarily unavailable. Please try again shortly.'
        : 'Request failed ($statusCode). Please try again.';
    throw Exception(message);
  }
}
