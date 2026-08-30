/// One captured snapshot of the 21x17 sensor grid during a test.
class PressureFrame {
  /// Milliseconds elapsed since the test/session started, at the moment
  /// this frame was decoded. Real wall-clock timing (not a sequence index)
  /// -- stride-time / cadence / variability metrics depend on this being
  /// accurate, since BLE notifications don't arrive at a perfectly fixed
  /// rate.
  final int time;
  final List<List<int>> item; // 21 rows x 17 cols

  PressureFrame({required this.time, required this.item});

  Map<String, dynamic> toJson() => {'time': time, 'item': item};

  factory PressureFrame.fromJson(Map<String, dynamic> json) {
    final rows = (json['item'] as List)
        .map((row) => List<int>.from((row as List).map((v) => (v as num).toInt())))
        .toList();
    return PressureFrame(time: (json['time'] as num).toInt(), item: rows);
  }

  /// First 7 columns of every row, used by the flight/contact analysis.
  List<List<int>> get firstSevenCols =>
      item.map((row) => row.sublist(0, 7 > row.length ? row.length : 7)).toList();
}

/// A 21x17 grid of zeros, matching the Vue app's initial `arr`.
List<List<int>> emptyGrid() =>
    List.generate(21, (_) => List.filled(17, 0));
