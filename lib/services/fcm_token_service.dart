import 'package:firebase_messaging/firebase_messaging.dart';

/// Requests notification permission and reads this device's FCM push
/// token -- used only by `JoinFamilyContactScreen` to register a family
/// member's device for geofence-breach alerts. The patient's own device
/// never needs a token; it's the one whose position gets watched, not
/// notified.
class FcmTokenService {
  Future<String?> requestToken() async {
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return null;
    return FirebaseMessaging.instance.getToken();
  }
}
