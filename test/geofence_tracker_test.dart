import 'package:flutter_test/flutter_test.dart';
import 'package:solesync/models/safe_zone.dart';
import 'package:solesync/services/geofence_tracker.dart';

void main() {
  group('GeofenceTracker', () {
    // ~300m of latitude at the equator is roughly 0.0027 degrees -- used
    // to build points comfortably inside/outside a 200m-radius zone
    // without depending on the exact Haversine constant.
    const zone = SafeZone(label: 'Home', latitude: 0, longitude: 0, radiusMeters: 200);

    test('does not fire while staying inside the zone', () {
      final tracker = GeofenceTracker();
      expect(tracker.checkBreach(zone, 0.0001, 0.0001), isFalse);
      expect(tracker.checkBreach(zone, 0.0002, 0.0002), isFalse);
    });

    test('fires exactly once on the sample that first exits the zone', () {
      final tracker = GeofenceTracker();
      expect(tracker.checkBreach(zone, 0, 0), isFalse); // dead center, inside

      // ~1km away -- well outside the 200m radius.
      expect(tracker.checkBreach(zone, 0.009, 0.009), isTrue);
      // Still outside on the next sample -- must not re-fire.
      expect(tracker.checkBreach(zone, 0.0091, 0.0091), isFalse);
    });

    test('fires again after returning inside then exiting a second time', () {
      final tracker = GeofenceTracker();
      expect(tracker.checkBreach(zone, 0.009, 0.009), isTrue); // exit
      expect(tracker.checkBreach(zone, 0, 0), isFalse); // back inside
      expect(tracker.checkBreach(zone, 0.009, 0.009), isTrue); // exit again
    });

    test('reset() clears the outside state without a fresh exit', () {
      final tracker = GeofenceTracker();
      expect(tracker.checkBreach(zone, 0.009, 0.009), isTrue);
      tracker.reset();
      // Still physically outside, but reset() means the next check is
      // treated as a fresh "first sample" rather than a continuation.
      expect(tracker.checkBreach(zone, 0.0091, 0.0091), isTrue);
    });
  });
}
