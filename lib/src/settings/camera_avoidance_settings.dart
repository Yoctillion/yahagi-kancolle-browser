import 'dart:convert';

/// User-controlled spacing on the physical camera side, in logical pixels.
class CameraAvoidanceSettings {
  const CameraAvoidanceSettings({this.enabled = false, this.distance = 0});

  static const maxDistance = 120.0;

  final bool enabled;
  final double distance;

  static double normalizeDistance(double value) =>
      value.isFinite ? value.clamp(0.0, maxDistance) : 0.0;

  CameraAvoidanceSettings normalized() => CameraAvoidanceSettings(
    enabled: enabled,
    distance: normalizeDistance(distance),
  );

  static CameraAvoidanceSettings decode(String? raw) {
    if (raw == null) return const CameraAvoidanceSettings();
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        return const CameraAvoidanceSettings();
      }
      final distance = json['distance'];
      return CameraAvoidanceSettings(
        enabled: json['enabled'] == true,
        distance: distance is num ? distance.toDouble() : 0,
      ).normalized();
    } on FormatException {
      return const CameraAvoidanceSettings();
    }
  }

  String encode() =>
      jsonEncode({'enabled': enabled, 'distance': normalizeDistance(distance)});
}
