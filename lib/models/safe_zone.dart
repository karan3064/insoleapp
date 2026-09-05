/// A single home-base geofence. During an insole capture session, GPS
/// positions are checked against this -- moving outside [radiusMeters]
/// from ([latitude], [longitude]) is treated as a safe-zone breach.
class SafeZone {
  final String label;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  const SafeZone({
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
      };

  factory SafeZone.fromJson(Map<String, dynamic> json) => SafeZone(
        label: json['label'] as String? ?? 'Home',
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 200,
      );
}
