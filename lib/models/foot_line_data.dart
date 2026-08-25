/// The 16 named pressure-point time series per foot, mirroring the Vue
/// `line.vue` / `RightLine.vue` components (`data`..`data16`).
///
/// Point layout (matches `chart/gather/gather.vue`'s grid indices):
///  - data..data8   -> forefoot (8 points)
///  - data9..data14 -> midfoot (6 points)
///  - data15,data16 -> heel (2 points)
class FootLineData {
  final List<List<int>> series; // series[0] = data, series[1] = data2, ...

  FootLineData({List<List<int>>? series})
      : series = series ?? List.generate(16, (_) => <int>[]);

  static const List<String> keys = [
    'data', 'data2', 'data3', 'data4', 'data5', 'data6', 'data7', 'data8',
    'data9', 'data10', 'data11', 'data12', 'data13', 'data14', 'data15', 'data16',
  ];

  List<int> byKey(String key) => series[keys.indexOf(key)];

  void push(List<int> values16) {
    for (var i = 0; i < 16; i++) {
      series[i].add(values16[i]);
    }
  }

  Map<String, dynamic> toJson() => {
        for (var i = 0; i < 16; i++) keys[i]: series[i],
      };

  factory FootLineData.fromJson(Map<String, dynamic> json) {
    return FootLineData(
      series: [
        for (final k in keys)
          List<int>.from((json[k] as List?) ?? const []),
      ],
    );
  }

  double averageOf(List<String> selectedKeys) {
    final values = <int>[];
    for (final k in selectedKeys) {
      values.addAll(byKey(k).where((v) => v != 0));
    }
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }
}
