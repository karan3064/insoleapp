import '../models/foot_line_data.dart';
import '../models/pressure_frame.dart';

class FootprintResult {
  final String footprintLeft;
  final String archLeft;
  final String landingLeft;
  final String footprintRight;
  final String archRight;
  final String landingRight;

  FootprintResult({
    required this.footprintLeft,
    required this.archLeft,
    required this.landingLeft,
    required this.footprintRight,
    required this.archRight,
    required this.landingRight,
  });
}

class ProportionResult {
  final int forefootPct;
  final int hindfootPct;
  final int wholePct;

  ProportionResult({
    required this.forefootPct,
    required this.hindfootPct,
    required this.wholePct,
  });
}

class FlightContactResult {
  final int totalDuration;
  final int totalAir;
  final int totalGround;

  FlightContactResult({
    required this.totalDuration,
    required this.totalAir,
    required this.totalGround,
  });
}

/// Ported 1:1 from `utils/gaitMetrics.js`.
class GaitAnalysis {
  GaitAnalysis._();

  /// Step count: number of captured frames with any non-zero pressure cell.
  static int processFrames(List<PressureFrame> frames) {
    return frames.where((f) => f.item.any((row) => row.any((v) => v != 0))).length;
  }

  static double calculateAverage(FootLineData data, List<String> keys) {
    return data.averageOf(keys);
  }

  static bool _isZeroMoreThanOthers(List<int> arr) {
    final zeroCount = arr.where((v) => v == 0).length;
    final otherCount = arr.length - zeroCount;
    return zeroCount > otherCount;
  }

  static bool _notZeroMoreThanOthers(List<int> arr) {
    final nonZeroCount = arr.where((v) => v != 0).length;
    final otherCount = arr.length - nonZeroCount;
    // Matches the (oddly-named) JS helper: true when non-zero samples
    // outnumber zero samples.
    return nonZeroCount > otherCount;
  }

  static bool _isNormal(List<bool> arr) {
    final trueCount = arr.where((v) => v).length;
    final otherCount = arr.length - trueCount;
    return trueCount >= otherCount;
  }

  static bool _isLand(List<bool> arr) {
    final trueCount = arr.where((v) => v).length;
    final otherCount = arr.length - trueCount;
    return trueCount > otherCount;
  }

  /// Footprint / arch / landing classification, per foot.
  static FootprintResult footprint(FootLineData line, FootLineData rightLine) {
    final lList = [
      _isZeroMoreThanOthers(line.byKey('data2')),
      _isZeroMoreThanOthers(line.byKey('data6')),
      _isZeroMoreThanOthers(line.byKey('data11')),
      _isZeroMoreThanOthers(line.byKey('data14')),
    ];

    String footprintLeft;
    String archLeft;
    if (_isNormal(lList)) {
      footprintLeft = 'Normal foot';
      archLeft = 'Normal arch';
    } else if (_isZeroMoreThanOthers(line.byKey('data11'))) {
      footprintLeft = 'Wide & flat feet';
      archLeft = 'Flat arch';
    } else {
      footprintLeft = 'Flat feet';
      archLeft = 'High arch (cavus)';
    }

    final rList = [
      _isZeroMoreThanOthers(rightLine.byKey('data2')),
      _isZeroMoreThanOthers(rightLine.byKey('data6')),
      _isZeroMoreThanOthers(rightLine.byKey('data9')),
      _isZeroMoreThanOthers(rightLine.byKey('data12')),
    ];

    String footprintRight;
    String archRight;
    if (_isNormal(rList)) {
      footprintRight = 'Normal foot';
      archRight = 'Normal arch';
    } else if (_isZeroMoreThanOthers(rightLine.byKey('data9'))) {
      footprintRight = 'Wide & flat feet';
      archRight = 'Flat arch';
    } else {
      footprintRight = 'Flat feet';
      archRight = 'High arch (cavus)';
    }

    final laLList = [
      'data', 'data2', 'data3', 'data4', 'data5', 'data6', 'data7', 'data8', 'data15', 'data16'
    ].map((k) => _notZeroMoreThanOthers(line.byKey(k))).toList();

    String landingLeft;
    if (_isLand(laLList)) {
      landingLeft = 'Full palm touching the ground';
    } else if (_isLand([
      _notZeroMoreThanOthers(line.byKey('data15')),
      _notZeroMoreThanOthers(line.byKey('data16')),
    ])) {
      landingLeft = 'Heel touching the ground';
    } else {
      landingLeft = 'Forefoot touching the ground';
    }

    final laRList = [
      'data', 'data2', 'data3', 'data4', 'data5', 'data6', 'data7', 'data8', 'data15', 'data16'
    ].map((k) => _notZeroMoreThanOthers(rightLine.byKey(k))).toList();

    String landingRight;
    if (_isLand(laRList)) {
      landingRight = 'Full palm touching the ground';
    } else if (_isLand([
      _notZeroMoreThanOthers(rightLine.byKey('data15')),
      _notZeroMoreThanOthers(rightLine.byKey('data16')),
    ])) {
      landingRight = 'Heel touching the ground';
    } else {
      landingRight = 'Forefoot touching the ground';
    }

    return FootprintResult(
      footprintLeft: footprintLeft,
      archLeft: archLeft,
      landingLeft: landingLeft,
      footprintRight: footprintRight,
      archRight: archRight,
      landingRight: landingRight,
    );
  }

  static const _forefootKeys = [
    'data', 'data2', 'data3', 'data4', 'data5', 'data6', 'data7', 'data8'
  ];
  static const _hindfootKeys = ['data15', 'data16'];
  static const _midfootKeys = [
    'data9', 'data10', 'data11', 'data12', 'data13', 'data14'
  ];

  /// Forefoot / midfoot / heel touchdown proportion for one foot.
  static ProportionResult proportion(FootLineData data) {
    int sumOf(List<String> keys) =>
        keys.fold(0, (sum, k) => sum + data.byKey(k).fold(0, (a, b) => a + b));

    final forefootSum = sumOf(_forefootKeys);
    final hindfootSum = sumOf(_hindfootKeys);
    final fullFootSum = sumOf(_midfootKeys);

    final total = forefootSum + hindfootSum + fullFootSum;
    if (total == 0) {
      return ProportionResult(forefootPct: 0, hindfootPct: 0, wholePct: 0);
    }

    return ProportionResult(
      forefootPct: (forefootSum / total * 100).round(),
      hindfootPct: (hindfootSum / total * 100).round(),
      wholePct: (fullFootSum / total * 100).round(),
    );
  }

  /// Truncates every frame's grid to its first 7 columns (used for
  /// flight/contact analysis).
  static List<PressureFrame> truncateToSevenCols(List<PressureFrame> frames) {
    return frames
        .map((f) => PressureFrame(time: f.time, item: f.firstSevenCols))
        .toList();
  }

  /// Air (flight) vs ground (contact) time analysis across captured frames.
  static FlightContactResult analyzeFlightAndContact(List<PressureFrame> frames) {
    if (frames.isEmpty) {
      return FlightContactResult(totalDuration: 0, totalAir: 0, totalGround: 0);
    }
    final sorted = [...frames]..sort((a, b) => a.time.compareTo(b.time));

    var totalAir = 0;
    var totalGround = 0;

    for (var i = 0; i < sorted.length; i++) {
      final frame = sorted[i];
      final next = i + 1 < sorted.length ? sorted[i + 1] : null;
      final duration = next != null ? next.time - frame.time : 0;

      final flat = frame.item.expand((row) => row);
      final allLow = flat.every((v) => v < 10);

      if (allLow) {
        totalAir += duration;
      } else {
        totalGround += duration;
      }
    }

    final totalDuration = sorted.last.time - sorted.first.time;

    return FlightContactResult(
      totalDuration: totalDuration,
      totalAir: totalAir,
      totalGround: totalGround,
    );
  }

  static int calculateCadence(int steps, int seconds) {
    if (seconds == 0) return 0;
    return (steps / seconds).round();
  }

  /// Left/right pressure balance, 0-100 (100 = perfectly balanced).
  static int calculateBalance(double l, double r) {
    final total = l + r;
    if (total == 0) return 0;
    return 100 - ((l - r).abs() / total * 100).round();
  }
}
