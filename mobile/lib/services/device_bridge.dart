import 'package:flutter/services.dart';

class DevicePermissionStatus {
  final bool fineLocation;
  final bool backgroundLocation;
  final bool notifications;
  final bool locationServices;
  final bool batteryOptimizationDisabled;

  const DevicePermissionStatus({
    required this.fineLocation,
    required this.backgroundLocation,
    required this.notifications,
    required this.locationServices,
    required this.batteryOptimizationDisabled,
  });

  bool get ready => fineLocation && backgroundLocation && locationServices;

  bool get healthy => ready && notifications && batteryOptimizationDisabled;

  factory DevicePermissionStatus.fromMap(Map<dynamic, dynamic> map) =>
      DevicePermissionStatus(
        fineLocation: map['fineLocation'] == true,
        backgroundLocation: map['backgroundLocation'] == true,
        notifications: map['notifications'] == true,
        locationServices: map['locationServices'] == true,
        batteryOptimizationDisabled: map['batteryOptimizationDisabled'] == true,
      );
}

class DeviceBridge {
  static const _channel = MethodChannel('five_star_attendance/device');

  Future<DevicePermissionStatus> status() async =>
      DevicePermissionStatus.fromMap(
        await _channel.invokeMethod<Map<dynamic, dynamic>>('status') ?? const {},
      );

  Future<void> requestFineLocation() =>
      _channel.invokeMethod('requestFineLocation');

  Future<void> requestNotifications() =>
      _channel.invokeMethod('requestNotifications');

  Future<void> openAppSettings() => _channel.invokeMethod('openAppSettings');

  Future<void> openLocationSettings() =>
      _channel.invokeMethod('openLocationSettings');

  Future<void> openBatterySettings() =>
      _channel.invokeMethod('openBatterySettings');
}
