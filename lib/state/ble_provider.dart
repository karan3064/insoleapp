import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/foot_line_data.dart';
import '../models/foot_point_layout.dart';
import '../models/insole_device.dart';
import '../models/insole_record.dart';
import '../models/pressure_frame.dart';
import '../models/record_summary.dart';
import '../models/track_point.dart';
import '../services/insole_frame_parser.dart';
import '../services/session_file_store.dart';

/// Same service/characteristic UUIDs used by the Vue app's
/// `pages/bluetooth/bluetooth.vue`.
final _serviceUuid = Guid('0000ee00-0000-1000-8000-00805f9b34fb');
final _characteristicUuid = Guid('0000ee02-0000-1000-8000-00805f9b34fb');

/// Owns the BLE connection(s) to the insole(s), decodes live pressure data,
/// and accumulates a test session's replay data / GPS path -- mirroring
/// `pages/bluetooth/bluetooth.vue` + `chart/gather/gather.vue` combined.
///
/// Capture can run for hours (there's no "stop test" step -- see
/// [isCapturing]), so raw per-frame data is streamed straight to a local
/// file as it arrives instead of being held in a growing in-memory list;
/// only a bounded recent window is kept resident for the live UI. See
/// `SessionFileStore` and `RecordSummary` for the other half of this.
class BleProvider extends ChangeNotifier {
  final List<InsoleDevice> discovered = [];
  final List<InsoleDevice> connectedDevices = [];

  bool isScanning = false;

  /// True from the moment both insoles are connected until they're
  /// disconnected. Pressure/line/GPS data is captured continuously the
  /// whole time -- there's no separate "start/stop test" step, so you never
  /// need to reconnect just to record another session.
  bool isCapturing = false;
  int elapsedSeconds = 0;

  /// Set whenever scanning/connecting fails, so the UI can surface it
  /// instead of failing silently. Cleared at the start of the next attempt.
  String? lastError;

  /// Live 21x17 pressure grid, updated as data streams in.
  List<List<int>> grid = emptyGrid();

  /// Recent-only per-foot pressure series, for the live waveform chart.
  /// Capped at [_liveWindowSize] samples -- full-fidelity history for a
  /// saved session is reconstructed from its frame file on demand (see
  /// `FootLineData.fromFrames`), not kept resident here for a session's
  /// whole duration.
  FootLineData leftLine = FootLineData();
  FootLineData rightLine = FootLineData();
  static const _liveWindowSize = 200;

  IOSink? _frameSink;
  String? _framesFilePath;
  final _fileStore = SessionFileStore();

  final List<TrackPoint> path = [];
  double totalDistanceKm = 0;
  DateTime? _testStartTime;

  final _parser = InsoleFrameParser();
  StreamSubscription<List<ScanResult>>? _scanSub;
  final Map<String, StreamSubscription<List<int>>> _valueSubs = {};
  Timer? _testTimer;
  StreamSubscription<Position>? _positionSub;

  Future<bool> ensurePermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final denied = statuses.entries.where((e) => !(e.value.isGranted || e.value.isLimited));
    if (denied.isNotEmpty) {
      lastError = 'Permission denied: ${denied.map((e) => e.key.toString()).join(', ')}. '
          'Enable these for the app in your phone\'s Settings.';
      return false;
    }
    return true;
  }

  Future<void> startScan() async {
    if (isScanning) return;
    lastError = null;

    try {
      if (!await FlutterBluePlus.isSupported) {
        lastError = 'This device does not support Bluetooth Low Energy.';
        notifyListeners();
        return;
      }

      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        lastError = 'Bluetooth is off. Turn it on and try again.';
        notifyListeners();
        return;
      }

      final granted = await ensurePermissions();
      if (!granted) {
        notifyListeners();
        return;
      }

      discovered.clear();
      isScanning = true;
      notifyListeners();

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final name = r.device.platformName.isNotEmpty
              ? r.device.platformName
              : r.advertisementData.advName;

          if (name.isEmpty || !name.startsWith('B2U')) continue;
          if (discovered.any((d) => d.name == name)) continue;

          discovered.add(InsoleDevice(device: r.device, name: name));
        }
        notifyListeners();
      }, onError: (Object e) {
        lastError = 'Scan error: $e';
        isScanning = false;
        notifyListeners();
      });

      FlutterBluePlus.isScanning.where((s) => s == false).first.then((_) {
        isScanning = false;
        notifyListeners();
      });
    } catch (e) {
      lastError = 'Failed to start scan: $e';
      isScanning = false;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    isScanning = false;
    notifyListeners();
  }

  Future<bool> connect(InsoleDevice insole) async {
    insole.connecting = true;
    notifyListeners();

    try {
      await insole.device.connect(timeout: const Duration(seconds: 12));

      final services = await insole.device.discoverServices();
      final service = services.firstWhere(
        (s) => s.uuid == _serviceUuid,
        orElse: () => services.first,
      );
      final characteristic = service.characteristics.firstWhere(
        (c) => c.uuid == _characteristicUuid,
        orElse: () => service.characteristics.first,
      );

      await characteristic.setNotifyValue(true);

      _valueSubs[insole.id]?.cancel();
      _valueSubs[insole.id] = characteristic.onValueReceived.listen((bytes) {
        _onData(bytes);
      });

      insole.connected = true;
      insole.connecting = false;
      if (!connectedDevices.any((d) => d.id == insole.id)) {
        connectedDevices.add(insole);
      }

      if (connectedDevices.length >= 2 && !isCapturing) {
        await _beginCapture();
      }

      notifyListeners();
      return true;
    } catch (e) {
      lastError = 'Failed to connect to ${insole.name}: $e';
      insole.connecting = false;
      insole.connected = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnect(InsoleDevice insole) async {
    await _valueSubs.remove(insole.id)?.cancel();
    try {
      await insole.device.disconnect();
    } catch (_) {
      // already disconnected
    }
    insole.connected = false;
    connectedDevices.removeWhere((d) => d.id == insole.id);

    if (connectedDevices.length < 2) {
      await _stopCapture();
    }

    notifyListeners();
  }

  Future<void> disconnectAll() async {
    for (final d in [...connectedDevices]) {
      await disconnect(d);
    }
  }

  void _onData(List<int> bytes) {
    final frame = _parser.feed(bytes);
    if (frame == null) return;

    grid = frame.grid;
    notifyListeners();

    if (isCapturing) {
      leftLine.push(frame.leftPoints);
      rightLine.push(frame.rightPoints);
      _trimLiveWindow(leftLine);
      _trimLiveWindow(rightLine);

      final elapsedMs = _testStartTime == null
          ? 0
          : DateTime.now().difference(_testStartTime!).inMilliseconds;
      final sink = _frameSink;
      if (sink != null) {
        _fileStore.writeFrame(sink, PressureFrame(time: elapsedMs, item: frame.grid));
      }
    }
  }

  static void _trimLiveWindow(FootLineData data) {
    for (final series in data.series) {
      if (series.length > _liveWindowSize) {
        series.removeRange(0, series.length - _liveWindowSize);
      }
    }
  }

  /// Auto-invoked once both insoles are connected. Resets the accumulators
  /// and starts the elapsed-time timer + GPS tracking; keeps running
  /// continuously (through any number of saved sessions) until disconnect.
  Future<void> _beginCapture() async {
    isCapturing = true;
    _resetAccumulators();
    _testStartTime = DateTime.now();
    await _openFrameFile();

    _testTimer?.cancel();
    _testTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsedSeconds++;
      notifyListeners();
    });

    unawaited(_startLocationTracking());

    notifyListeners();
  }

  Future<void> _openFrameFile() async {
    final sessionKey = DateTime.now().millisecondsSinceEpoch;
    _frameSink = await _fileStore.openWriter(sessionKey);
    _framesFilePath = (await _fileStore.fileFor(sessionKey)).path;
  }

  Future<void> _stopCapture() async {
    isCapturing = false;
    _testTimer?.cancel();
    _positionSub?.cancel();
    await _frameSink?.flush();
    await _frameSink?.close();
    _frameSink = null;
  }

  void _resetAccumulators() {
    elapsedSeconds = 0;
    grid = emptyGrid();
    leftLine = FootLineData();
    rightLine = FootLineData();
    path.clear();
    totalDistanceKm = 0;
    _parser.reset();
  }

  Future<void> _startLocationTracking() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final requested = await Geolocator.requestPermission();
      if (requested == LocationPermission.denied ||
          requested == LocationPermission.deniedForever) {
        return;
      }
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    await _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).listen((position) {
      final point = TrackPoint(latitude: position.latitude, longitude: position.longitude);

      if (path.isNotEmpty) {
        final last = path.last;
        totalDistanceKm += Geolocator.distanceBetween(
              last.latitude,
              last.longitude,
              point.latitude,
              point.longitude,
            ) /
            1000;
      }

      path.add(point);
      notifyListeners();
    });
  }

  /// Snapshots the currently-accumulated data into a saved record, then
  /// immediately resets the accumulators so capture keeps going
  /// uninterrupted -- no reconnect, no re-arming a "test mode" needed to
  /// record the next session. [id] should be the next sequential record id
  /// (mirrors `insole.list.length + 1`).
  ///
  /// Closes out this segment's frame file, reads it back once to compute
  /// the session's [RecordSummary] (step count, footprint, clinical gait
  /// metrics, ...), then opens a fresh file for the next segment. The
  /// returned record carries that summary plus a pointer to the frame
  /// file -- never the raw frames themselves.
  Future<InsoleRecord> saveSession(int id, String deviceName) async {
    final totalTimeMin = _testStartTime == null
        ? 0
        : (DateTime.now().difference(_testStartTime!).inSeconds / 60).round();
    final pace = totalDistanceKm > 0 ? (totalTimeMin / totalDistanceKm).round() : 0;

    // Detach the sink before any `await` below -- `_onData` checks
    // `_frameSink` on every incoming frame, so nulling it out synchronously
    // (rather than after closing) means a frame arriving during this
    // close-and-reopen gap is just skipped, never written to a sink that's
    // in the middle of closing.
    final sink = _frameSink;
    final framesFilePath = _framesFilePath;
    _frameSink = null;
    await sink?.flush();
    await sink?.close();

    List<PressureFrame> details = const [];
    if (framesFilePath != null) {
      details = await _fileStore.readFramesAtPath(framesFilePath);
    }
    final line = FootLineData.fromFrames(details, FootPointLayout.left);
    final rightFull = FootLineData.fromFrames(details, FootPointLayout.right);

    final summary = RecordSummary.compute(
      details: details,
      line: line,
      rightLine: rightFull,
      elapsedSeconds: elapsedSeconds,
    );

    final record = InsoleRecord(
      id: id,
      name: deviceName,
      date: _formattedNow(),
      time: elapsedSeconds,
      summary: summary,
      framesFilePath: framesFilePath,
      distanceKm: totalDistanceKm,
      pace: pace,
      totalTime: totalTimeMin,
      path: List.of(path),
    );

    if (isCapturing) {
      _resetAccumulators();
      _testStartTime = DateTime.now();
      await _openFrameFile();
    }

    return record;
  }

  String _formattedNow() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)} ${two(n.hour)}:${two(n.minute)}';
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    for (final s in _valueSubs.values) {
      s.cancel();
    }
    _testTimer?.cancel();
    _positionSub?.cancel();
    _frameSink?.close();
    super.dispose();
  }
}
