import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:solesync/models/pressure_frame.dart';
import 'package:solesync/services/session_file_store.dart';

/// Fakes `getApplicationDocumentsDirectory()` with a temp directory so the
/// store can be exercised without a real device/plugin channel.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String path;
  _FakePathProvider(this.path);

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_file_store_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('writes frames incrementally and reads them back in order', () async {
    final store = SessionFileStore();
    final sink = await store.openWriter(1);

    final frames = [
      PressureFrame(time: 0, item: emptyGrid()),
      PressureFrame(time: 50, item: [
        for (var r = 0; r < 21; r++)
          [for (var c = 0; c < 17; c++) if (r == 0 && c == 0) 42 else 0],
      ]),
      PressureFrame(time: 100, item: emptyGrid()),
    ];
    for (final f in frames) {
      store.writeFrame(sink, f);
    }
    await sink.flush();
    await sink.close();

    final readBack = await store.readFrames(1);
    expect(readBack.length, 3);
    expect(readBack.map((f) => f.time).toList(), [0, 50, 100]);
    expect(readBack[1].item[0][0], 42);
  });

  test('readFramesAtPath reads the same content as readFrames', () async {
    final store = SessionFileStore();
    final sink = await store.openWriter(2);
    store.writeFrame(sink, PressureFrame(time: 10, item: emptyGrid()));
    await sink.flush();
    await sink.close();

    final file = await store.fileFor(2);
    final byPath = await store.readFramesAtPath(file.path);
    expect(byPath.length, 1);
    expect(byPath.single.time, 10);
  });

  test('returns an empty list for a session with no file', () async {
    final store = SessionFileStore();
    expect(await store.readFrames(999), isEmpty);
  });

  test('deleteSession removes the file', () async {
    final store = SessionFileStore();
    final sink = await store.openWriter(3);
    store.writeFrame(sink, PressureFrame(time: 0, item: emptyGrid()));
    await sink.flush();
    await sink.close();

    expect(await (await store.fileFor(3)).exists(), isTrue);
    await store.deleteSession(3);
    expect(await (await store.fileFor(3)).exists(), isFalse);
  });
}
