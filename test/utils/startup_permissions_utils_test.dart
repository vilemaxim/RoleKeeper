import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/utils/location_utils.dart';
import 'package:rolekeeper/utils/startup_permissions_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    startupPermissionsDebugIsWeb = null;
    LocationUtils.debugIsWeb = null;
    LocationUtils.debugWebIsWhenInUseGranted = null;
    LocationUtils.debugWebRequestWhenInUse = null;
  });

  group('StartupPermissionsResult.allGranted', () {
    test('requires vibration only, not location', () {
      const result = StartupPermissionsResult(
        locationGranted: false,
        vibrationReady: true,
        locationServiceEnabled: false,
      );

      expect(result.allGranted, isTrue);
    });

    test('is false when vibration is unavailable', () {
      const result = StartupPermissionsResult(
        locationGranted: true,
        vibrationReady: false,
        locationServiceEnabled: true,
      );

      expect(result.allGranted, isFalse);
    });
  });

  group('requestStartupPermissions', () {
    test('does not block startup when location is unavailable on native',
        () async {
      final result = await requestStartupPermissions();

      expect(result.vibrationReady, isTrue);
      expect(result.allGranted, isTrue);
    });

    test('web path does not require location at startup', () async {
      startupPermissionsDebugIsWeb = true;

      final result = await requestStartupPermissions();

      expect(result.allGranted, isTrue);
      expect(result.vibrationReady, isTrue);
    });
  });

  group('requestLocationWhenNeeded', () {
    test('returns granted when permission is already granted', () async {
      LocationUtils.debugIsWeb = true;
      LocationUtils.debugWebIsWhenInUseGranted = () async => true;

      final result = await requestLocationWhenNeeded();

      expect(result.granted, isTrue);
    });

    test('returns denied without throwing when user denies permission', () async {
      LocationUtils.debugIsWeb = true;
      LocationUtils.debugWebIsWhenInUseGranted = () async => false;
      LocationUtils.debugWebRequestWhenInUse = () async => false;

      final result = await requestLocationWhenNeeded(promptIfNeeded: true);

      expect(result.granted, isFalse);
    });
  });
}
