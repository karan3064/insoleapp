import 'package:geolocator/geolocator.dart';

import '../models/safe_zone.dart';

/// Tracks inside/outside-safe-zone transitions so a breach fires once per
/// exit, not on every GPS sample while still outside. Factored out of
/// `BleProvider` purely so this transition logic is unit-testable without
/// GPS/BLE/Firestore.
class GeofenceTracker {
  bool _wasOutside = false;

  /// Returns true exactly on the sample where the position moves from
  /// inside to outside [zone] -- never on the samples that follow while
  /// still outside, and never again until a subsequent return-then-exit.
  bool checkBreach(SafeZone zone, double latitude, double longitude) {
    final distanceMeters = Geolocator.distanceBetween(
      zone.latitude,
      zone.longitude,
      latitude,
      longitude,
    );
    final isOutside = distanceMeters > zone.radiusMeters;
    final isNewBreach = isOutside && !_wasOutside;
    _wasOutside = isOutside;
    return isNewBreach;
  }

  void reset() => _wasOutside = false;
}
