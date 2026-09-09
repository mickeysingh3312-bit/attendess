import 'package:flutter/services.dart';

class PickedDocument {
  final String path;
  final String name;
  final int size;
  final String? mimeType;

  const PickedDocument({
    required this.path,
    required this.name,
    required this.size,
    this.mimeType,
  });

  factory PickedDocument.fromMap(Map<dynamic, dynamic> value) {
    return PickedDocument(
      path: value['path']?.toString() ?? '',
      name: value['name']?.toString() ?? 'attachment',
      size: int.tryParse(value['size']?.toString() ?? '') ?? 0,
      mimeType: value['mimeType']?.toString(),
    );
  }
}

class DocumentBridge {
  static const MethodChannel _channel =
      MethodChannel('five_star_attendance/document');

  Future<PickedDocument?> pickDocument() async {
    final value = await _channel.invokeMethod<dynamic>('pick');
    if (value == null || value is! Map) return null;
    final document = PickedDocument.fromMap(value);
    if (document.path.isEmpty) return null;
    return document;
  }

  Future<void> openUrl(String url) async {
    final value = url.trim();
    if (value.isEmpty) return;
    await _channel.invokeMethod<void>('openUrl', {'url': value});
  }
}
