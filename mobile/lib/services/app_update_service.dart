import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

class AppRelease {
  final bool updateAvailable;
  final String versionName;
  final int versionCode;
  final String releaseNotes;
  final bool mandatory;
  final String downloadUrl;

  const AppRelease({
    required this.updateAvailable,
    required this.versionName,
    required this.versionCode,
    required this.releaseNotes,
    required this.mandatory,
    required this.downloadUrl,
  });

  factory AppRelease.fromJson(Map<String, dynamic> json) => AppRelease(
        updateAvailable: json['update_available'] == true,
        versionName: json['version_name']?.toString() ?? '',
        versionCode: int.tryParse(json['version_code']?.toString() ?? '') ?? 0,
        releaseNotes: json['release_notes']?.toString() ?? '',
        mandatory: json['mandatory'] == true,
        downloadUrl: json['download_url']?.toString() ?? '',
      );
}

class AppUpdateService {
  static const _channel = MethodChannel('five_star_attendance/updater');

  Future<AppRelease?> check() async {
    final baseUrl = await AppConfig.apiBaseUrl();
    final uri = Uri.parse('$baseUrl/app-release/latest').replace(
      queryParameters: {'version_code': AppConfig.versionCode.toString()},
    );
    final response = await http.get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    return AppRelease.fromJson(decoded);
  }

  Future<void> downloadAndInstall(AppRelease release) async {
    if (!Platform.isAndroid || release.downloadUrl.isEmpty) return;
    await _channel.invokeMethod('downloadAndInstall', {
      'url': release.downloadUrl,
      'fileName': 'five-star-attendance-v${release.versionName}.apk',
    });
  }
}
