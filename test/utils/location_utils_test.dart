import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rolekeeper/utils/location_utils.dart';

Position _testPosition({double lat = 42.3601, double lng = -71.0589}) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: DateTime.utc(2026, 6, 27, 12, 0),
    accuracy: 12,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  tearDown(() {
    LocationUtils.debugIsWeb = null;
    LocationUtils.debugWebIsWhenInUseGranted = null;
    LocationUtils.debugWebGetCurrentPosition = null;
    LocationUtils.debugWebRequestWhenInUse = null;
  });

  group('LocationUtils web (browser Geolocation API)', () {
    test('isWhenInUseGranted reflects denied web permission', () async {
      LocationUtils.debugIsWeb = true;
      LocationUtils.debugWebIsWhenInUseGranted = () async => false;

      expect(await LocationUtils.isWhenInUseGranted(), isFalse);
    });

    test('isWhenInUseGranted reflects granted web permission', () async {
      LocationUtils.debugIsWeb = true;
      LocationUtils.debugWebIsWhenInUseGranted = () async => true;

      expect(await LocationUtils.isWhenInUseGranted(), isTrue);
    });

    test('getCurrentPositionOrNull returns coordinates when web permission granted',
        () async {
      LocationUtils.debugIsWeb = true;
      LocationUtils.debugWebIsWhenInUseGranted = () async => true;
      LocationUtils.debugWebGetCurrentPosition =
          ({
            LocationAccuracy desiredAccuracy = LocationAccuracy.medium,
            Duration timeLimit = const Duration(seconds: 15),
          }) async =>
              _testPosition();

      final pos = await LocationUtils.getCurrentPositionOrNull();

      expect(pos, isNotNull);
      expect(pos!.latitude, closeTo(42.3601, 0.0001));
      expect(pos.longitude, closeTo(-71.0589, 0.0001));
    });

    test('getCurrentPositionOrNull returns null when web permission denied',
        () async {
      LocationUtils.debugIsWeb = true;
      LocationUtils.debugWebIsWhenInUseGranted = () async => false;

      expect(await LocationUtils.getCurrentPositionOrNull(), isNull);
    });

    test('requestWhenInUseIfNeeded prompts via browser and returns granted',
        () async {
      LocationUtils.debugIsWeb = true;
      LocationUtils.debugWebRequestWhenInUse = () async => true;

      expect(await LocationUtils.requestWhenInUseIfNeeded(), isTrue);
    });

    test('requestWhenInUseIfNeeded returns false when browser denies', () async {
      LocationUtils.debugIsWeb = true;
      LocationUtils.debugWebRequestWhenInUse = () async => false;

      expect(await LocationUtils.requestWhenInUseIfNeeded(), isFalse);
    });
  });
}
