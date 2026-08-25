# SoleSync (Flutter)

A Flutter port of the SoleSync smart-insole companion app (originally a Vue 3 /
uni-app project). Connects to the insole hardware over Bluetooth Low Energy,
visualizes live foot-pressure data, and computes gait analytics (footprint,
arch type, landing method, cadence, ground/air time).

This port is **insole-only** -- the original app's mattress/pillow modules
were intentionally left out of scope.

## What's implemented

- BLE scan/connect to `B2U*` insole peripherals (`flutter_blue_plus`), with
  the exact same packet-framing/decoding protocol as the original app
  (`lib/services/insole_frame_parser.dart` -- see its tests for a worked
  example of the wire format).
- Live pressure heatmap + point view per foot, GPS path tracking during a
  test, and per-foot pressure line charts.
- Gait analytics ported 1:1 from the original `gaitMetrics.js` / `health.js`
  (`lib/services/gait_analysis.dart`, `lib/services/health_calc.dart`).
- Firebase Auth (email/password) + Firestore sync of profile + test records,
  targeting the **same Firebase project** the Vue app uses
  (`solesync-f7740`), with local on-device persistence as the source of
  truth (`shared_preferences`) mirroring the original's
  `vuex-persistedstate` setup.
- Screens: splash, login/signup, home dashboard (activity rings, quick
  stats), bluetooth connect, live test, record detail/replay, records list,
  7-day trends, profile.

## Setup required before running

### 1. Firebase

This app is wired to reuse the existing `solesync-f7740` Firebase project,
but it needs its own registered Android/iOS app entries (the Vue app only
registered a web app). Run:

```sh
dart pub global activate flutterfire_cli
flutterfire configure --project=solesync-f7740
```

This registers new Android + iOS apps under the same project and
regenerates `lib/firebase_options.dart` with the real keys (overwriting the
placeholder committed here). It'll also drop `google-services.json` /
`GoogleService-Info.plist` in place, though they aren't strictly required
since Firebase is initialized with explicit `FirebaseOptions`.

### 2. Google Maps API key

The GPS path map (test + detail screens) needs a Google Maps API key from
<https://console.cloud.google.com/google/maps-apis>. Set it in:

- `android/app/src/main/AndroidManifest.xml` -- the
  `com.google.android.geo.API_KEY` meta-data value
- `ios/Runner/AppDelegate.swift` -- the `GMSServices.provideAPIKey(...)` call

### 3. Run it

```sh
flutter pub get
flutter run
```

## Known gaps / follow-ups

- **Foot outline artwork**: the original app's `left.png` / `right.png`
  foot-silhouette images weren't part of the shared source, so
  `lib/widgets/foot_pressure_view.dart` draws a procedural stand-in
  silhouette. Swap in the real artwork (as a clip mask) if you have it.
- **Localization**: the Vue app was i18n-ready; this port ships English
  strings only. Add `flutter_localizations` / ARB files if needed.
- **3D insole model** (`components/insole/Model/Model.vue`, three.js +
  GLB): this was an experimental/unused component in the original app (not
  wired into any active screen) and was not ported.
