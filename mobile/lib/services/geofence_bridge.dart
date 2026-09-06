import 'package:flutter/services.dart';

import '../config.dart';
import '../models/project.dart';

class GeofenceBridge {
  static const _channel = MethodChannel('five_star_attendance/geofence');

  Future<void> register({
    required List<ProjectGeofence> projects,
    required String bearerToken,
    required String deviceUuid,
  }) async {
    final apiBaseUrl = await AppConfig.apiBaseUrl();
    await _channel.invokeMethod('register', {
      'projects': projects.map((project) => project.toNative()).toList(),
      'apiBaseUrl': apiBaseUrl,
      'bearerToken': bearerToken,
      'deviceUuid': deviceUuid,
    });
  }

  Future<void> clear() => _channel.invokeMethod('clear');
}
