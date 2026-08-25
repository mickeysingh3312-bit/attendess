import 'package:flutter/services.dart';
import '../models/project.dart';
import '../config.dart';

class GeofenceBridge {
  static const _channel = MethodChannel('five_star_attendance/geofence');
  Future<void> register({required List<ProjectGeofence> projects, required String bearerToken, required String deviceUuid}) async {
    await _channel.invokeMethod('register', {'projects': projects.map((p) => p.toNative()).toList(), 'apiBaseUrl': AppConfig.apiBaseUrl, 'bearerToken': bearerToken, 'deviceUuid': deviceUuid});
  }
  Future<void> clear() => _channel.invokeMethod('clear');
}
