import 'package:flutter/foundation.dart';

import 'location_utils.dart';
import 'vibration_utils.dart';

/// Outcome of [requestStartupPermissions].
class StartupPermissionsResult {
  const StartupPermissionsResult({
    required this.locationGranted,
    required this.vibrationReady,
    required this.locationServiceEnabled,
  });

  final bool locationGranted;
  final bool vibrationReady;
  final bool locationServiceEnabled;

  bool get allGranted => locationGranted && vibrationReady;

  StartupPermissionsResult copyWith({
    bool? locationGranted,
    bool? vibrationReady,
    bool? locationServiceEnabled,
  }) {
    return StartupPermissionsResult(
      locationGranted: locationGranted ?? this.locationGranted,
      vibrationReady: vibrationReady ?? this.vibrationReady,
      locationServiceEnabled: locationServiceEnabled ?? this.locationServiceEnabled,
    );
  }
}

/// Asks for location (when in use) and validates vibration/haptics readiness.
/// Call once at app launch (see [AppPermissionsWrapper]).
Future<StartupPermissionsResult> requestStartupPermissions() async {
  // Avoid Geolocator permission channels on web (often MissingPluginException
  // in `flutter run -d chrome`); the browser handles geolocation when used.
  if (kIsWeb) {
    return const StartupPermissionsResult(
      locationGranted: true,
      vibrationReady: true,
      locationServiceEnabled: true,
    );
  }

  final serviceOn = await LocationUtils.isLocationServiceEnabled();
  final loc = await LocationUtils.requestWhenInUseIfNeeded();
  final vib = await VibrationUtils.isVibrationCapabilitySatisfied();

  // Web: no OS-level "location services" toggle like mobile GPS.
  final locationOk = loc && (kIsWeb || serviceOn);

  if (locationOk && vib) {
    await VibrationUtils.vibrateShortPulse();
  }

  return StartupPermissionsResult(
    locationGranted: locationOk,
    vibrationReady: vib,
    locationServiceEnabled: serviceOn,
  );
}
