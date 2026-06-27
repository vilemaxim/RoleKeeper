// Browser Geolocation API for PWA builds.
//
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

/// iOS Safari PWA: location is foreground-only in v1; pings stop when the app
/// is backgrounded. Permanent denial requires the user to change site settings
/// in the browser; [webRequestWhenInUse] returns false without blocking the app.
Future<bool> webIsWhenInUseGranted() async {
  try {
    final permissions = html.window.navigator.permissions;
    if (permissions == null) return false;
    final status = await permissions.query({'name': 'geolocation'});
    return status.state == 'granted';
  } catch (_) {
    return false;
  }
}

Future<bool> webRequestWhenInUse() async {
  final pos = await webGetCurrentPosition(
    timeLimit: const Duration(seconds: 15),
  );
  return pos != null;
}

Future<({double latitude, double longitude, double accuracy})?>
    webGetCurrentPosition({
  required Duration timeLimit,
}) async {
  try {
    final position = await html.window.navigator.geolocation.getCurrentPosition(
      enableHighAccuracy: false,
      timeout: timeLimit,
      maximumAge: Duration.zero,
    );
    final coords = position.coords;
    if (coords == null) return null;
    final lat = coords.latitude;
    final lng = coords.longitude;
    if (lat == null || lng == null) return null;
    return (
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      accuracy: coords.accuracy?.toDouble() ?? 0,
    );
  } catch (_) {
    return null;
  }
}
