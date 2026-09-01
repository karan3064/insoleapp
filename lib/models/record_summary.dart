import '../services/clinical_gait_analysis.dart';
import '../services/gait_analysis.dart';
import 'foot_line_data.dart';
import 'pressure_frame.dart';

/// Everything a saved session's dashboard/detail/trends views need,
/// computed once (from the full frame data) at save time instead of being
/// re-derived from raw per-frame data on every screen render. Keeping this
/// small and always-resident is what lets `InsoleRecord` stay cheap to
/// hold many of at once -- the raw frames it's computed from live in a
/// local file instead (see `SessionFileStore`), loaded only when a screen
/// specifically needs frame-level detail (playback, full line charts,
/// export).
class RecordSummary {
  final int stepCount;
  final int cadenceSpm;
  final int groundContactMs;
  final int flightMs;
  final String footprintLeft;
  final String footprintRight;
  final String archLeft;
  final String archRight;
  final String landingLeft;
  final String landingRight;
  final int forefootPct;
  final int hindfootPct;
  final int wholePct;
  final int lFront, rFront, lMid, rMid, lRear, rRear;
  final int balancePercent;
  final ClinicalGaitReport clinical;

  RecordSummary({
    required this.stepCount,
    required this.cadenceSpm,
    required this.groundContactMs,
    required this.flightMs,
    required this.footprintLeft,
    required this.footprintRight,
    required this.archLeft,
    required this.archRight,
    required this.landingLeft,
    required this.landingRight,
    required this.forefootPct,
    required this.hindfootPct,
    required this.wholePct,
    required this.lFront,
    required this.rFront,
    required this.lMid,
    required this.rMid,
    required this.lRear,
    required this.rRear,
    required this.balancePercent,
    required this.clinical,
  });

  static const _frontKeys = ['data', 'data2', 'data3', 'data4', 'data5', 'data6', 'data7', 'data8'];
  static const _midKeys = ['data9', 'data10', 'data11', 'data12', 'data13', 'data14'];
  static const _rearKeys = ['data15', 'data16'];
  static const _allKeys = [..._frontKeys, ..._midKeys, ..._rearKeys];

  /// Runs every gait/footprint/clinical computation once, from the full
  /// per-frame data captured for a session. Called right after a session
  /// is saved, while that data is still at hand -- never re-run later
  /// from a lazily-reloaded frame file just to render a dashboard.
  factory RecordSummary.compute({
    required List<PressureFrame> details,
    required FootLineData line,
    required FootLineData rightLine,
    required int elapsedSeconds,
  }) {
    final stepCount = GaitAnalysis.processFrames(details);
    final cadence = GaitAnalysis.calculateCadence(stepCount, elapsedSeconds);
    final flightContact =
        GaitAnalysis.analyzeFlightAndContact(GaitAnalysis.truncateToSevenCols(details));
    final footprint = GaitAnalysis.footprint(line, rightLine);
    final proportion = GaitAnalysis.proportion(line);
    final lFoot = GaitAnalysis.calculateAverage(line, _allKeys);
    final rFoot = GaitAnalysis.calculateAverage(rightLine, _allKeys);
    final clinical = ClinicalGaitAnalysis.analyze(line: line, rightLine: rightLine, details: details);

    return RecordSummary(
      stepCount: stepCount,
      cadenceSpm: cadence,
      groundContactMs: flightContact.totalGround,
      flightMs: flightContact.totalAir,
      footprintLeft: footprint.footprintLeft,
      footprintRight: footprint.footprintRight,
      archLeft: footprint.archLeft,
      archRight: footprint.archRight,
      landingLeft: footprint.landingLeft,
      landingRight: footprint.landingRight,
      forefootPct: proportion.forefootPct,
      hindfootPct: proportion.hindfootPct,
      wholePct: proportion.wholePct,
      lFront: GaitAnalysis.calculateAverage(line, _frontKeys).round(),
      rFront: GaitAnalysis.calculateAverage(rightLine, _frontKeys).round(),
      lMid: GaitAnalysis.calculateAverage(line, _midKeys).round(),
      rMid: GaitAnalysis.calculateAverage(rightLine, _midKeys).round(),
      lRear: GaitAnalysis.calculateAverage(line, _rearKeys).round(),
      rRear: GaitAnalysis.calculateAverage(rightLine, _rearKeys).round(),
      balancePercent: GaitAnalysis.calculateBalance(lFoot, rFoot),
      clinical: clinical,
    );
  }

  /// Used for a record with no frame data available at all (defensive
  /// fallback only -- every record saved by this app always has a summary
  /// computed at save time).
  static final empty = RecordSummary(
    stepCount: 0,
    cadenceSpm: 0,
    groundContactMs: 0,
    flightMs: 0,
    footprintLeft: '',
    footprintRight: '',
    archLeft: '',
    archRight: '',
    landingLeft: '',
    landingRight: '',
    forefootPct: 0,
    hindfootPct: 0,
    wholePct: 0,
    lFront: 0,
    rFront: 0,
    lMid: 0,
    rMid: 0,
    lRear: 0,
    rRear: 0,
    balancePercent: 0,
    clinical: ClinicalGaitReport.empty,
  );

  Map<String, dynamic> toJson() => {
        'stepCount': stepCount,
        'cadenceSpm': cadenceSpm,
        'groundContactMs': groundContactMs,
        'flightMs': flightMs,
        'footprintLeft': footprintLeft,
        'footprintRight': footprintRight,
        'archLeft': archLeft,
        'archRight': archRight,
        'landingLeft': landingLeft,
        'landingRight': landingRight,
        'forefootPct': forefootPct,
        'hindfootPct': hindfootPct,
        'wholePct': wholePct,
        'lFront': lFront,
        'rFront': rFront,
        'lMid': lMid,
        'rMid': rMid,
        'lRear': lRear,
        'rRear': rRear,
        'balancePercent': balancePercent,
        'clinical': clinical.toJson(),
      };

  factory RecordSummary.fromJson(Map<String, dynamic> json) => RecordSummary(
        stepCount: (json['stepCount'] as num?)?.toInt() ?? 0,
        cadenceSpm: (json['cadenceSpm'] as num?)?.toInt() ?? 0,
        groundContactMs: (json['groundContactMs'] as num?)?.toInt() ?? 0,
        flightMs: (json['flightMs'] as num?)?.toInt() ?? 0,
        footprintLeft: json['footprintLeft'] as String? ?? '',
        footprintRight: json['footprintRight'] as String? ?? '',
        archLeft: json['archLeft'] as String? ?? '',
        archRight: json['archRight'] as String? ?? '',
        landingLeft: json['landingLeft'] as String? ?? '',
        landingRight: json['landingRight'] as String? ?? '',
        forefootPct: (json['forefootPct'] as num?)?.toInt() ?? 0,
        hindfootPct: (json['hindfootPct'] as num?)?.toInt() ?? 0,
        wholePct: (json['wholePct'] as num?)?.toInt() ?? 0,
        lFront: (json['lFront'] as num?)?.toInt() ?? 0,
        rFront: (json['rFront'] as num?)?.toInt() ?? 0,
        lMid: (json['lMid'] as num?)?.toInt() ?? 0,
        rMid: (json['rMid'] as num?)?.toInt() ?? 0,
        lRear: (json['lRear'] as num?)?.toInt() ?? 0,
        rRear: (json['rRear'] as num?)?.toInt() ?? 0,
        balancePercent: (json['balancePercent'] as num?)?.toInt() ?? 0,
        clinical: json['clinical'] == null
            ? ClinicalGaitReport.empty
            : ClinicalGaitReport.fromJson(Map<String, dynamic>.from(json['clinical'] as Map)),
      );
}
