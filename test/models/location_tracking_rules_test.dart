import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/models/location_tracking_rules.dart';

void main() {
  group('LocationTrackingRules', () {
    test('fromMap(null) returns defaults', () {
      const expected = LocationTrackingRules.defaultRules;

      final rules = LocationTrackingRules.fromMap(null);

      expect(rules.enabled, expected.enabled);
      expect(rules.pingIntervalSeconds, expected.pingIntervalSeconds);
    });

    test('fromMap({}) returns defaults', () {
      final rules = LocationTrackingRules.fromMap({});

      expect(rules.enabled, isFalse);
      expect(rules.pingIntervalSeconds, 60);
    });

    test('toMap / fromMap round-trip preserves values', () {
      const original = LocationTrackingRules(
        enabled: true,
        pingIntervalSeconds: 120,
      );

      final roundTrip = LocationTrackingRules.fromMap(original.toMap());

      expect(roundTrip.enabled, isTrue);
      expect(roundTrip.pingIntervalSeconds, 120);
    });

    test('fromMap clamps pingIntervalSeconds below 30 to 30', () {
      final rules = LocationTrackingRules.fromMap({
        'enabled': true,
        'pingIntervalSeconds': 10,
      });

      expect(rules.pingIntervalSeconds, 30);
    });

    test('fromMap clamps pingIntervalSeconds above 300 to 300', () {
      final rules = LocationTrackingRules.fromMap({
        'enabled': true,
        'pingIntervalSeconds': 999,
      });

      expect(rules.pingIntervalSeconds, 300);
    });

    test('fromMap accepts pingIntervalSeconds within 30–300', () {
      for (final seconds in [30, 60, 150, 300]) {
        final rules = LocationTrackingRules.fromMap({
          'pingIntervalSeconds': seconds,
        });

        expect(rules.pingIntervalSeconds, seconds);
      }
    });

    test('toMap serializes enabled and pingIntervalSeconds', () {
      const rules = LocationTrackingRules(
        enabled: true,
        pingIntervalSeconds: 90,
      );

      expect(rules.toMap(), {
        'enabled': true,
        'pingIntervalSeconds': 90,
      });
    });
  });
}
