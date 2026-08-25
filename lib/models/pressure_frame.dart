/// One captured snapshot of the 21x17 sensor grid during a test, with the
/// capture-sequence `time` value used by the gait analytics.
class PressureFrame {
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
