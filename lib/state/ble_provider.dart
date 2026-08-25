import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/foot_line_data.dart';
import '../models/insole_device.dart';
import '../models/insole_record.dart';
import '../models/pressure_frame.dart';
import '../models/track_point.dart';
import '../services/insole_frame_parser.dart';

/// Same service/characteristic UUIDs used by the Vue app's
/// `pages/bluetooth/bluetooth.vue`.
final _serviceUuid = Guid('0000ee00-0000-1000-8000-00805f9b34fb');
final _characteristicUuid = Guid('0000ee02-0000-1000-8000-00805f9b34fb');

/// Owns the BLE connection(s) to the insole(s), decodes live pressure data,
/// and accumulates a test session's replay data / GPS path -- mirroring
/// `pages/bluetooth/bluetooth.vue` + `chart/gather/gather.vue` combined.
class BleProvider extends ChangeNotifier {
  final List<InsoleDevice> discovered = [];
  final List<InsoleDevice> connectedDevices = [];

  bool isScanning = false;
  bool isTesting = false;
  int testSeconds = 0;

  /// Live 21x17 pressure grid, updated as data streams in.
  List<List<int>> grid = emptyGrid();

  FootLineData leftLine = FootLineData();
  FootLineData rightLine = FootLineData();
  final List<PressureFrame> _frames = [];

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

    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<void> startScan() async {
    if (isScanning) return;

    final granted = await ensurePermissions();
    if (!granted) return;

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
    });

    FlutterBluePlus.isScanning.where((s) => s == false).first.then((_) {
      isScanning = false;
      notifyListeners();
    });
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
      notifyListeners();
      return true;
    } catch (e) {
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

    if (isTesting) {
      leftLine.push(frame.leftPoints);
      rightLine.push(frame.rightPoints);
      _frames.add(PressureFrame(time: _frames.length, item: frame.grid));
    }
  }

  Future<void> startTest() async {
    isTesting = true;
    testSeconds = 0;
    grid = emptyGrid();
    leftLine = FootLineData();
    rightLine = FootLineData();
    _frames.clear();
    path.clear();
    totalDistanceKm = 0;
    _testStartTime = DateTime.now();
    _parser.reset();

    _testTimer?.cancel();
    _testTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      testSeconds++;
      notifyListeners();
    });

    unawaited(_startLocationTracking());

    notifyListeners();
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

  /// Stops the test and returns the completed record. [id] should be the
  /// next sequential record id (mirrors `insole.list.length + 1`).
  InsoleRecord stopTest(int id, String deviceName) {
    isTesting = false;
    _testTimer?.cancel();
    _positionSub?.cancel();

    final totalTimeMin = _testStartTime == null
        ? 0
        : (DateTime.now().difference(_testStartTime!).inSeconds / 60).round();
    final pace = totalDistanceKm > 0 ? (totalTimeMin / totalDistanceKm).round() : 0;

    final record = InsoleRecord(
      id: id,
      name: deviceName,
      date: _formattedNow(),
      time: testSeconds,
      details: List.of(_frames),
      line: leftLine,
      rightLine: rightLine,
      distanceKm: totalDistanceKm,
      pace: pace,
      totalTime: totalTimeMin,
      path: List.of(path),
    );

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
    super.dispose();
  }
}
