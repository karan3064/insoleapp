/// The 16 physical sensor positions per foot, as (row, col) coordinates in
/// the shared 21x17 pressure grid. Order is forefoot(8) -> midfoot(6) ->
/// heel(2), matching `FootLineData`'s data..data16 series order.
///
/// This is the single source of truth for the grid layout; both the BLE
/// frame parser and the foot visualizations key off of it.
class FootPointLayout {
  FootPointLayout._();

  static const List<List<int>> left = [
    [0, 5], [1, 1], [3, 6], [4, 3],
    [5, 0], [7, 6], [8, 3], [9, 0],
    [12, 1], [12, 3], [12, 5],
    [15, 1], [15, 3], [15, 5],
    [19, 2], [19, 4],
  ];

  static const List<List<int>> right = [
    [0, 11], [1, 15], [3, 10], [4, 13],
    [5, 16], [7, 10], [8, 13], [9, 16],
    [12, 11], [12, 13], [12, 15],
    [15, 11], [15, 13], [15, 15],
    [19, 12], [19, 14],
  ];

  /// Row span used for layout math (0-based, inclusive).
  static const int minRow = 0;
  static const int maxRow = 20;

  /// Column span for a single foot's half of the grid, 0-based relative to
  /// that foot (left uses grid cols 0-6, right uses grid cols 10-16).
  static const int minCol = 0;
  static const int maxCol = 6;
}
