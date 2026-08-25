class ProjectGeofence {
  final int id;
  final String code;
  final String name;
  final String? address;
  final double latitude;
  final double longitude;
  final int radius;
  const ProjectGeofence({required this.id, required this.code, required this.name, this.address, required this.latitude, required this.longitude, required this.radius});
  factory ProjectGeofence.fromJson(Map<String, dynamic> j) => ProjectGeofence(
    id: j['id'] as int,
    code: (j['project_code'] ?? '').toString(),
    name: (j['name'] ?? '').toString(),
    address: j['address']?.toString(),
    latitude: double.parse(j['latitude'].toString()),
    longitude: double.parse(j['longitude'].toString()),
    radius: int.tryParse((j['geofence_radius_m'] ?? 150).toString()) ?? 150,
  );
  Map<String, dynamic> toNative() => {'id': id, 'code': code, 'name': name, 'latitude': latitude, 'longitude': longitude, 'radius': radius};
}
