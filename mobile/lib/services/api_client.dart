import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class ApiException implements Exception {
  final String message;
  final bool network;

  const ApiException(this.message, {this.network = false});

  @override
  String toString() => message;
}

class ApiClient {
  static const _requestTimeout = Duration(seconds: 22);
  static const _cachePrefix = 'api_cache_';
  static const _retryableStatusCodes = {502, 503, 504};

  Future<String?> token() async =>
      (await SharedPreferences.getInstance()).getString('token');

  static String friendlyError(Object error) {
    if (error is ApiException) return error.message;

    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    final text = raw.toLowerCase();
    if (text.contains('socket') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection reset') ||
        text.contains('connection refused') ||
        text.contains('connection closed') ||
        text.contains('clientexception') ||
        text.contains('handshake')) {
      return 'We could not reach the attendance server. Check your internet connection and try again. Automatic attendance events will keep retrying in the background.';
    }
    if (text.contains('timed out') || text.contains('timeout')) {
      return 'The attendance server is taking longer than expected. Please try again in a moment. Automatic attendance events remain queued for retry.';
    }
    if (raw.isEmpty || raw.length > 220 || raw.contains('dart:') || raw.contains('package:')) {
      return 'Something went wrong while contacting the attendance service. Please try again.';
    }
    return raw;
  }

  Future<Map<String, dynamic>> requestOtp(
    String email,
    String deviceUuid,
  ) async {
    final baseUrl = await AppConfig.apiBaseUrl();
    final response = await _networkRequest(
      () => http.post(
        Uri.parse('$baseUrl/auth/request-otp'),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'email': email.trim().toLowerCase(),
          'device_uuid': deviceUuid,
        }),
      ),
      attempts: 1,
    );

    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> verifyOtp(
    String email,
    String otp,
    String deviceUuid,
  ) async {
    final baseUrl = await AppConfig.apiBaseUrl();
    final response = await _networkRequest(
      () => http.post(
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
      ),
      attempts: 1,
    );

    final data = _decodeResponse(response);
    final authToken = data['token']?.toString();
    if (authToken == null || authToken.isEmpty) {
      throw const ApiException('The server did not return a login token. Please try again.');
    }

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('token', authToken);
    await preferences.setString('user_email', email.trim().toLowerCase());
    return data;
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    final authToken = await token();
    if (authToken == null || authToken.isEmpty) {
      throw const ApiException('Please sign in again.');
    }

    final baseUrl = await AppConfig.apiBaseUrl();
    final response = await _networkRequest(
      () => http.get(
        Uri.parse('$baseUrl$path'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Accept': 'application/json',
          'Cache-Control': 'no-cache',
        },
      ),
      attempts: 4,
      retryServerErrors: true,
    );

    if (response.statusCode == 401) {
      throw const ApiException('Your session has expired. Please sign in again.');
    }
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> getJsonCached(
    String path, {
    required String cacheKey,
  }) async {
    try {
      final data = await getJson(path);
      await writeCache(cacheKey, data);
      return <String, dynamic>{
        'data': data,
        'from_cache': false,
      };
    } on ApiException catch (e) {
      if (!e.network) rethrow;
      final cached = await readCache(cacheKey);
      if (cached == null) rethrow;
      return <String, dynamic>{
        'data': cached['data'] ?? cached,
        'from_cache': true,
        'cached_at': cached['cached_at'],
        'network_message': e.message,
      };
    }
  }

  Future<void> writeCache(String key, Map<String, dynamic> data) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      '$_cachePrefix$key',
      jsonEncode({
        'cached_at': DateTime.now().toUtc().toIso8601String(),
        'data': data,
      }),
    );
  }

  Future<Map<String, dynamic>?> readCache(String key) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('$_cachePrefix$key');
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  Future<void> logout() async {
    final authToken = await token();
    if (authToken == null || authToken.isEmpty) return;

    try {
      final baseUrl = await AppConfig.apiBaseUrl();
      await _networkRequest(
        () => http.post(
          Uri.parse('$baseUrl/logout'),
          headers: {
            'Authorization': 'Bearer $authToken',
            'Accept': 'application/json',
          },
        ),
        attempts: 1,
        timeout: const Duration(seconds: 10),
      );
    } catch (_) {
      // Local sign-out must still work when the server or network is unavailable.
    }
  }

  Future<http.Response> _networkRequest(
    Future<http.Response> Function() request, {
    int attempts = 1,
    Duration timeout = _requestTimeout,
    bool retryServerErrors = false,
  }) async {
    Object? lastError;
    http.Response? lastResponse;

    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final response = await request().timeout(timeout);
        lastResponse = response;
        if (!retryServerErrors ||
            !_retryableStatusCodes.contains(response.statusCode) ||
            attempt == attempts) {
          return response;
        }
        lastError = ApiException(
          'The attendance server is temporarily unavailable.',
          network: true,
        );
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on HandshakeException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      } catch (e) {
        if (!_looksLikeNetworkError(e)) rethrow;
        lastError = e;
      }

      if (attempt < attempts) {
        final delay = 500 * attempt * attempt;
        await Future<void>.delayed(Duration(milliseconds: delay));
      }
    }

    if (lastResponse != null) return lastResponse;

    throw ApiException(
      _networkMessage(lastError),
      network: true,
    );
  }

  bool _looksLikeNetworkError(Object error) {
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

  String _networkMessage(Object? error) {
    final text = error?.toString().toLowerCase() ?? '';
    if (text.contains('failed host lookup') || text.contains('network is unreachable')) {
      return 'We could not reach the attendance server. Check your internet connection and try again. Your automatic attendance events will keep retrying in the background.';
    }
    if (text.contains('timed out') || text.contains('timeout')) {
      return 'The attendance server is taking longer than expected. Please try again in a moment. Automatic attendance events remain queued for retry.';
    }
    return 'The attendance server is temporarily unavailable. Please try again shortly. Automatic attendance events will retry in the background.';
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Map<String, dynamic> data = <String, dynamic>{};
    if (response.body.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {
        // Non-JSON responses are handled by the generic status message below.
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

    if (response.statusCode >= 500) {
      message ??= 'The attendance server is temporarily unavailable. Please try again shortly.';
    } else {
      message ??= 'Request failed (${response.statusCode}). Please try again.';
    }

    throw ApiException(message);
  }
}
