import '../models/foot_point_layout.dart';
import '../models/pressure_frame.dart';

/// The result of successfully decoding one complete sensor frame.
class ParsedFrame {
  final List<List<int>> grid; // 21x17
  final List<int> leftPoints; // 16 values, forefoot->heel order
  final List<int> rightPoints; // 16 values, forefoot->heel order
  final int sequence;

  ParsedFrame({
    required this.grid,
    required this.leftPoints,
    required this.rightPoints,
    required this.sequence,
  });
}

/// Decodes the insole's raw BLE notify payloads into a 21x17 pressure grid.
///
/// Ported 1:1 from `utils/BLE.js` (`ab2hext`) and the packet-framing /
/// grid-mapping logic inlined in `chart/gather/gather.vue`'s
/// `onBLECharacteristicValueChange`.
///
/// Wire format per notification chunk (as a hex string):
///  - starts with `55aa`           -> frame header, rest is the first chunk
///  - ends with `ddcc`             -> frame footer, rest is the last chunk
///  - otherwise                    -> a middle chunk, appended to the buffer
///
/// Once a full frame is assembled, its hex digits are split into 4-char
/// (2-byte) little-endian words, then thresholded (only values with
/// `raw - 200 > 0` count) and scaled down (`/ 50`) before being placed into
/// the 21x17 grid.
///
/// To match the original UI's render throttling (and, more importantly, the
/// cadence used later by the gait analytics), only 1 out of every 3
/// completed frames is accepted/emitted -- the other 2 are decoded and
/// discarded, exactly as the Vue app does.
class InsoleFrameParser {
  String _buffer = '';
  int _throttle = 0;
  int _sequence = 0;

  // list[] index that feeds each (row, col) point in FootPointLayout.left/right.
  static const List<int> _leftListIndex = [12, 0, 13, 7, 1, 14, 8, 2, 3, 9, 15, 4, 10, 16, 5, 17];
  static const List<int> _rightListIndex = [33, 21, 34, 28, 22, 35, 29, 23, 36, 30, 24, 37, 31, 25, 38, 26];

  static String bytesToHex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static int _at(List<int> list, int index) => index < list.length ? list[index] : 0;

  /// Feed raw bytes from one BLE notification. Returns a [ParsedFrame] when
  /// a complete frame was decoded and accepted, otherwise null.
  ParsedFrame? feed(List<int> bytes) {
    final hex = bytesToHex(bytes);

    if (hex.startsWith('55aa')) {
      _buffer = hex.substring(4);
      return null;
    }

    if (hex.endsWith('ddcc')) {
      final chunk = hex.substring(0, hex.length - 8);
      final hexString = _buffer + chunk;
      _buffer = '';

      final words = <String>[];
      for (var i = 0; i + 4 <= hexString.length; i += 4) {
        words.add(hexString.substring(i, i + 4));
      }

      final decimal = words.map((w) {
        final swapped = w.substring(2, 4) + w.substring(0, 2);
        return int.parse(swapped, radix: 16);
      }).toList();

      if (decimal.length < 25) return null;

      final list = decimal.map((v) => v - 200 > 0 ? (v / 50).round() : 0).toList();

      _throttle++;
      if (_throttle == 3) _throttle = 0;
      if (_throttle != 1) return null;

      final grid = emptyGrid();
      final leftPoints = <int>[];
      final rightPoints = <int>[];

      for (var i = 0; i < FootPointLayout.left.length; i++) {
        final v = _at(list, _leftListIndex[i]);
        final rc = FootPointLayout.left[i];
        grid[rc[0]][rc[1]] = v;
        leftPoints.add(v);
      }
      for (var i = 0; i < FootPointLayout.right.length; i++) {
        final v = _at(list, _rightListIndex[i]);
        final rc = FootPointLayout.right[i];
        grid[rc[0]][rc[1]] = v;
        rightPoints.add(v);
      }

      _sequence++;

      return ParsedFrame(
        grid: grid,
        leftPoints: leftPoints,
        rightPoints: rightPoints,
        sequence: _sequence,
      );
    }

    if (_buffer.isNotEmpty) {
      _buffer += hex;
    }

    return null;
  }

  void reset() {
    _buffer = '';
    _throttle = 0;
    _sequence = 0;
  }
}
