import 'record_summary.dart';
import 'track_point.dart';

/// A single completed test session, mirroring the object built in
/// `chart/gather/gather.vue`'s `goDetail()` and persisted via
/// `store/modules/insole.js`.
///
/// Deliberately does NOT hold raw per-frame pressure data (that would make
/// this object -- and the local storage / Firestore payload built from it
/// -- grow without bound as sessions get longer, up to and including
/// multi-hour all-day wear). Raw frames live in a local file instead (see
/// `SessionFileStore`) and are loaded on demand only by the screens that
/// actually need frame-level detail (playback, full line charts, export).
/// Everything else (dashboards, trends, the clinical metrics card) reads
/// [summary], computed once when the session was saved.
class InsoleRecord {
  final int id;
  final String name; // connected device name, e.g. "B2U-321B"
  final String date; // "YYYY-MM-DD HH:mm"
  final int time; // test duration in seconds
  final RecordSummary summary;

  /// Local path to this session's raw-frame file (see `SessionFileStore`),
  /// or null if none is available on this device (e.g. a record synced
  /// down from another device, or a summary-only cloud record).
  final String? framesFilePath;

  final double distanceKm;
  final int pace; // minutes per km
  final int totalTime; // minutes
  final List<TrackPoint> path;

  InsoleRecord({
    required this.id,
    required this.name,
    required this.date,
    required this.time,
    required this.summary,
    required this.framesFilePath,
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
        'summary': summary.toJson(),
        'framesFilePath': framesFilePath,
        'distance': distanceKm,
        'pace': pace,
        'totalTime': totalTime,
        'path': path.map((p) => p.toJson()).toList(),
      };

  factory InsoleRecord.fromJson(Map<String, dynamic> json) {
    return InsoleRecord(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      date: json['date'] as String? ?? '',
      time: (json['time'] as num?)?.toInt() ?? 0,
      summary: json['summary'] == null
          ? RecordSummary.empty
          : RecordSummary.fromJson(Map<String, dynamic>.from(json['summary'] as Map)),
      framesFilePath: json['framesFilePath'] as String?,
      distanceKm: (json['distance'] as num?)?.toDouble() ?? 0,
      pace: (json['pace'] as num?)?.toInt() ?? 0,
      totalTime: (json['totalTime'] as num?)?.toInt() ?? 0,
      path: ((json['path'] as List?) ?? const [])
          .map((p) => TrackPoint.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList(),
    );
  }
}
