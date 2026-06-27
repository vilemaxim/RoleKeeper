import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'web_geolocation.dart' as web_geo;

/// Location permission and coarse position reads for RoleKeeper.
abstract final class LocationUtils {
  /// Overrides [kIsWeb] in tests to exercise browser geolocation paths.
  @visibleForTesting
  static bool? debugIsWeb;

  @visibleForTesting
  static Future<bool> Function()? debugWebIsWhenInUseGranted;

  @visibleForTesting
  static Future<Position?> Function({
    LocationAccuracy desiredAccuracy,
    Duration timeLimit,
  })? debugWebGetCurrentPosition;

  @visibleForTesting
  static Future<bool> Function()? debugWebRequestWhenInUse;

  static bool get _isWeb => debugIsWeb ?? kIsWeb;

  /// Whether "when in use" (or always) location access is already granted.
  static Future<bool> isWhenInUseGranted() async {
    if (_isWeb) {
      final probe = debugWebIsWhenInUseGranted;
      if (probe != null) return probe();
      return web_geo.webIsWhenInUseGranted();
    }
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
    if (_isWeb) {
      final request = debugWebRequestWhenInUse;
      if (request != null) return request();
      if (await isWhenInUseGranted()) return true;
      return web_geo.webRequestWhenInUse();
    }
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
    if (_isWeb) return false;
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
    if (_isWeb) return true;
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (e, st) {
      debugPrint('LocationUtils.isLocationServiceEnabled: $e\n$st');
      return true;
    }
  }

  /// Last known position, or `null` if unavailable / not permitted.
  static Future<Position?> getLastKnownPositionOrNull() async {
    if (_isWeb) return null;
    if (!await isWhenInUseGranted()) return null;
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (e, st) {
      debugPrint('LocationUtils.getLastKnownPositionOrNull: $e\n$st');
      return null;
    }
  }

  /// Current position (may prompt on mobile/web). Returns `null` if denied or error.
  static Future<Position?> getCurrentPositionOrNull({
    LocationAccuracy desiredAccuracy = LocationAccuracy.medium,
    Duration timeLimit = const Duration(seconds: 15),
  }) async {
    if (_isWeb) {
      if (!await isWhenInUseGranted()) return null;
      final getPosition = debugWebGetCurrentPosition;
      if (getPosition != null) {
        return getPosition(
          desiredAccuracy: desiredAccuracy,
          timeLimit: timeLimit,
        );
      }
      final webPos = await web_geo.webGetCurrentPosition(timeLimit: timeLimit);
      if (webPos == null) return null;
      return Position(
        latitude: webPos.latitude,
        longitude: webPos.longitude,
        timestamp: DateTime.now(),
        accuracy: webPos.accuracy,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    }
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
