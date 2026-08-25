import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// A discovered/connected BLE insole peripheral (device name starts with
/// "B2U", matching the Vue app's `pages/bluetooth/bluetooth.vue` filter).
class InsoleDevice {
  final BluetoothDevice device;
  final String name;
  bool connecting;
  bool connected;

  InsoleDevice({
    required this.device,
    required this.name,
    this.connecting = false,
    this.connected = false,
  });

  String get id => device.remoteId.str;
}
