import 'package:flutter/foundation.dart';

import 'location_utils.dart';
import 'vibration_utils.dart';

/// Overrides [kIsWeb] in tests for [requestStartupPermissions].
@visibleForTesting
bool? startupPermissionsDebugIsWeb;

bool get _startupIsWeb => startupPermissionsDebugIsWeb ?? kIsWeb;

/// Outcome of [requestLocationWhenNeeded].
class LocationWhenNeededResult {
  const LocationWhenNeededResult({required this.granted});

  final bool granted;
}

/// Requests location permission when tracking needs it (not at app startup).
///
/// When [promptIfNeeded] is false, reports current grant state without prompting.
/// When true, prompts the user (OS dialog or browser Geolocation API).
/// Returns denied without throwing if the user declines.
Future<LocationWhenNeededResult> requestLocationWhenNeeded({
  bool promptIfNeeded = false,
}) async {
  if (await LocationUtils.isWhenInUseGranted()) {
    return const LocationWhenNeededResult(granted: true);
  }
  if (!promptIfNeeded) {
    return const LocationWhenNeededResult(granted: false);
  }
  final granted = await LocationUtils.requestWhenInUseIfNeeded();
  if (!granted) {
    return const LocationWhenNeededResult(granted: false);
  }
  if (!_startupIsWeb && !await LocationUtils.isLocationServiceEnabled()) {
    return const LocationWhenNeededResult(granted: false);
  }
  return const LocationWhenNeededResult(granted: true);
}

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

  /// Startup gate: vibration/haptics only. Location is requested later via
  /// [requestLocationWhenNeeded] when tracking is active.
  bool get allGranted => vibrationReady;

  StartupPermissionsResult copyWith({
    bool? locationGranted,
    bool? vibrationReady,
    bool? locationServiceEnabled,
  }) {
    return StartupPermissionsResult(
      locationGranted: locationGranted ?? this.locationGranted,
      vibrationReady: vibrationReady ?? this.vibrationReady,
      locationServiceEnabled:
          locationServiceEnabled ?? this.locationServiceEnabled,
    );
  }
}

/// Validates vibration/haptics readiness at app launch (see [AppPermissionsWrapper]).
/// Location is not requested here; use [requestLocationWhenNeeded] when tracking
/// needs coordinates.
Future<StartupPermissionsResult> requestStartupPermissions() async {
  if (_startupIsWeb) {
    return const StartupPermissionsResult(
      locationGranted: false,
      vibrationReady: true,
      locationServiceEnabled: true,
    );
  }

  final vib = await VibrationUtils.isVibrationCapabilitySatisfied();

  if (vib) {
    await VibrationUtils.vibrateShortPulse();
  }

  return StartupPermissionsResult(
    locationGranted: false,
    vibrationReady: vib,
    locationServiceEnabled: true,
  );
}
