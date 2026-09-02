import 'package:flutter/services.dart';

/// Starts/stops the Android foreground service that keeps BLE + GPS
/// capture running while the app is backgrounded during a long session
/// (see `android/.../CaptureForegroundService.kt`). A no-op on platforms
/// without a matching native handler (iOS has no equivalent yet) --
/// capture still works there, just only while the app stays foregrounded.
class CaptureServiceChannel {
  CaptureServiceChannel._();

  static const _channel = MethodChannel('com.solesync.solesync/capture_service');

  static Future<void> start() async {
    try {
      await _channel.invokeMethod('start');
    } catch (_) {
      // Best-effort: capture still works while the app is foregrounded
      // even if this fails (unsupported platform, permission denied).
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }
}
