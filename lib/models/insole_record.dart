import 'foot_line_data.dart';
import 'pressure_frame.dart';
import 'track_point.dart';

/// A single completed test session, mirroring the object built in
/// `chart/gather/gather.vue`'s `goDetail()` and persisted via
/// `store/modules/insole.js`.
class InsoleRecord {
  final int id;
  final String name; // connected device name, e.g. "B2U-321B"
  final String date; // "YYYY-MM-DD HH:mm"
  final int time; // test duration in seconds
  final List<PressureFrame> details; // frame-by-frame replay data
  final FootLineData line; // left foot
  final FootLineData rightLine; // right foot
  final double distanceKm;
  final int pace; // minutes per km
  final int totalTime; // minutes
  final List<TrackPoint> path;

  InsoleRecord({
    required this.id,
    required this.name,
    required this.date,
    required this.time,
    required this.details,
    required this.line,
    required this.rightLine,
    required this.distanceKm,
    required this.pace,
    required this.totalTime,
    required this.path,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'date': date,
        'time': time,
        'details': {
          for (var i = 0; i < details.length; i++) 'uniqueKey_$i': details[i].toJson(),
        },
        'line': line.toJson(),
        'rightLine': rightLine.toJson(),
        'distance': distanceKm,
        'pace': pace,
        'totalTime': totalTime,
        'path': path.map((p) => p.toJson()).toList(),
      };

  factory InsoleRecord.fromJson(Map<String, dynamic> json) {
    final detailsJson = (json['details'] as Map?) ?? const {};
    final details = detailsJson.values
        .map((v) => PressureFrame.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    return InsoleRecord(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      date: json['date'] as String? ?? '',
      time: (json['time'] as num?)?.toInt() ?? 0,
      details: details,
      line: FootLineData.fromJson(Map<String, dynamic>.from(json['line'] as Map? ?? const {})),
      rightLine: FootLineData.fromJson(
          Map<String, dynamic>.from(json['rightLine'] as Map? ?? const {})),
      distanceKm: (json['distance'] as num?)?.toDouble() ?? 0,
      pace: (json['pace'] as num?)?.toInt() ?? 0,
      totalTime: (json['totalTime'] as num?)?.toInt() ?? 0,
      path: ((json['path'] as List?) ?? const [])
          .map((p) => TrackPoint.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList(),
    );
  }
}
