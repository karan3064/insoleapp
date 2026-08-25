class TrackPoint {
  final double latitude;
  final double longitude;

  const TrackPoint({required this.latitude, required this.longitude});

  Map<String, dynamic> toJson() => {'latitude': latitude, 'longitude': longitude};

  factory TrackPoint.fromJson(Map<String, dynamic> json) => TrackPoint(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      );
}
