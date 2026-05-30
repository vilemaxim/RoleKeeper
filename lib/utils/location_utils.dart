import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Location permission and coarse position reads for RoleKeeper.
abstract final class LocationUtils {
  /// Whether "when in use" (or always) location access is already granted.
  static Future<bool> isWhenInUseGranted() async {
    // Geolocator's method channel is not wired in all web/debug setups; the
    // browser handles permission when [getCurrentPositionOrNull] runs.
    if (kIsWeb) return true;
    try {
      final p = await Geolocator.checkPermission();
      return p == LocationPermission.whileInUse || p == LocationPermission.always;
    } catch (e, st) {
      debugPrint('LocationUtils.isWhenInUseGranted: $e\n$st');
      return false;
    }
  }

  /// Requests when-in-use location if currently denied. Does not open settings.
  /// Returns `true` if granted (including already granted).
  static Future<bool> requestWhenInUseIfNeeded() async {
    if (kIsWeb) return true;
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      return p == LocationPermission.whileInUse || p == LocationPermission.always;
    } catch (e, st) {
      debugPrint('LocationUtils.requestWhenInUseIfNeeded: $e\n$st');
      return false;
    }
  }

  /// Opens OS location settings for this app (e.g. after "denied forever").
  static Future<bool> openLocationAppSettings() async {
    if (kIsWeb) return false;
    try {
      return await Geolocator.openAppSettings();
    } catch (e, st) {
      debugPrint('LocationUtils.openLocationAppSettings: $e\n$st');
      return false;
    }
  }

  /// Whether location services are enabled at the OS level (GPS off, etc.).
  /// On web there is no such channel; treat as enabled so the browser prompt can run.
  static Future<bool> isLocationServiceEnabled() async {
    if (kIsWeb) return true;
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (e, st) {
      debugPrint('LocationUtils.isLocationServiceEnabled: $e\n$st');
      return true;
    }
  }

  /// Last known position, or `null` if unavailable / not permitted.
  static Future<Position?> getLastKnownPositionOrNull() async {
    if (kIsWeb) return null;
    if (!await isWhenInUseGranted()) return null;
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (e, st) {
      debugPrint('LocationUtils.getLastKnownPositionOrNull: $e\n$st');
      return null;
    }
  }

  /// Current position (may prompt on mobile). Returns `null` if denied or error.
  ///
  /// On `flutter run -d chrome`, the Geolocator method channel is often not
  /// registered (`MissingPluginException`); skip the plugin and return null.
  /// Use the browser Geolocation API via a dedicated web package if you need
  /// coordinates on web later.
  static Future<Position?> getCurrentPositionOrNull({
    LocationAccuracy desiredAccuracy = LocationAccuracy.medium,
    Duration timeLimit = const Duration(seconds: 15),
  }) async {
    if (kIsWeb) return null;
    try {
      if (!await isWhenInUseGranted()) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: desiredAccuracy,
          timeLimit: timeLimit,
        ),
      );
    } catch (e, st) {
      debugPrint('LocationUtils.getCurrentPositionOrNull: $e\n$st');
      return null;
    }
  }
}
