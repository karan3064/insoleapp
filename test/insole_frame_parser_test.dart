import 'package:flutter_test/flutter_test.dart';
import 'package:solesync/services/insole_frame_parser.dart';

/// Encodes one raw sensor value into the 4-hex-char wire word that, after
/// the parser's byte-swap, decodes back to [value]. Mirrors the inverse of
/// `str = hex.slice(-2) + hex.slice(0, -2)` from the original `BLE.js`
/// packet handling.
String _wireWord(int value) {
  final hex = value.toRadixString(16).padLeft(4, '0');
  return hex.substring(2, 4) + hex.substring(0, 2);
}

List<int> _hexToBytes(String hex) {
  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return bytes;
}

void main() {
  test('InsoleFrameParser decodes a full BLE frame split across 3 notifications', () {
    // 39 raw sensor readings, each comfortably above the 200 threshold so
    // scaling is exercised: raw = 200 + (i+1)*10, scaled = round(raw/50).
    final raw = List.generate(39, (i) => 200 + (i + 1) * 10);
    final words = raw.map(_wireWord).join();

    final headerChunk = '55aa${words.substring(0, 40)}';
    final middleChunk = words.substring(40, 80);
    final footerChunk = '${words.substring(80)}ddcc';

    final parser = InsoleFrameParser();

    expect(parser.feed(_hexToBytes(headerChunk)), isNull);
    expect(parser.feed(_hexToBytes(middleChunk)), isNull);

    final frame = parser.feed(_hexToBytes(footerChunk));
    expect(frame, isNotNull);

    // left point 0 -> grid[0][5], sourced from list[33] (raw index 33).
    // (Confirmed by physical device testing: pressing the physical left
    // insole was showing up as the rightmost position on screen, i.e.
    // _leftListIndex/_rightListIndex were crossed relative to
    // FootPointLayout -- see InsoleFrameParser.feed.)
    final expectedLeft0 = ((200 + 34 * 10) / 50).round();
    expect(frame!.grid[0][5], expectedLeft0);
    expect(frame.leftPoints[0], expectedLeft0);

    // right point 0 -> grid[0][11], sourced from list[12] (raw index 12).
    final expectedRight0 = ((200 + 13 * 10) / 50).round();
    expect(frame.grid[0][11], expectedRight0);
    expect(frame.rightPoints[0], expectedRight0);

    // Row12 (the first midfoot row, 3 points at cols 1/3/5) is medial<->
    // lateral mirrored relative to the forefoot points above: confirmed
    // by physical device testing that this row (and row15/row19 below
    // it) still read opposite after the left/right-foot swap alone.
    // left points 8/9/10 -> grid[12][1]/[12][3]/[12][5], sourced from
    // list[24]/list[30]/list[36] (mirrored: positions 10/9/8 of
    // _rightListIndex, not 8/9/10 straight).
    expect(frame.grid[12][1], ((200 + 25 * 10) / 50).round()); // list[24]
    expect(frame.grid[12][3], ((200 + 31 * 10) / 50).round()); // list[30]
    expect(frame.grid[12][5], ((200 + 37 * 10) / 50).round()); // list[36]
    expect(frame.leftPoints[8], ((200 + 25 * 10) / 50).round());
    expect(frame.leftPoints[9], ((200 + 31 * 10) / 50).round());
    expect(frame.leftPoints[10], ((200 + 37 * 10) / 50).round());

    // Untouched grid cells stay zero.
    expect(frame.grid[10][8], 0);
  });

  test('InsoleFrameParser thresholds low readings to zero', () {
    // All 39 values at/under the 200 threshold -> every mapped point is 0.
    final raw = List.filled(39, 150);
    final words = raw.map(_wireWord).join();

    final parser = InsoleFrameParser();
    parser.feed(_hexToBytes('55aa${words.substring(0, 40)}'));
    final frame = parser.feed(_hexToBytes('${words.substring(40)}ddcc'));

    expect(frame, isNotNull);
    expect(frame!.leftPoints.every((v) => v == 0), isTrue);
    expect(frame.rightPoints.every((v) => v == 0), isTrue);
  });
}
