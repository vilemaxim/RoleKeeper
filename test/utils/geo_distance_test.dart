import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/models/activity_event.dart';
import 'package:rolekeeper/models/nfc_hunt_tag.dart';
import 'package:rolekeeper/utils/geo_distance.dart';

void main() {
  group('haversineDistanceMeters', () {
    test('returns ~0 for identical coordinates', () {
      const lat = 45.5231;
      const lon = -122.6765;

      final meters = haversineDistanceMeters(
        lat1: lat,
        lon1: lon,
        lat2: lat,
        lon2: lon,
      );

      expect(meters, lessThan(0.01));
    });

    test('returns known distance between two Portland-area points', () {
      // ~1.1 km apart — Portland State University ↔ Moda Center area.
      final meters = haversineDistanceMeters(
        lat1: 45.5111,
        lon1: -122.6834,
        lat2: 45.5316,
        lon2: -122.6668,
      );

      expect(meters, greaterThan(2000));
      expect(meters, lessThan(3000));
    });
  });

  group('fixedTagScanMismatchMeters', () {
    const tagLocation = ActivityEventLocation(
      latitude: 45.5231,
      longitude: -122.6765,
    );

    test('returns null for floating tag (no comparison)', () {
      final meters = fixedTagScanMismatchMeters(
        tagPlacement: NfcHuntPlacement.floating,
        tagLocation: tagLocation,
        scanLocation: const ActivityEventLocation(
          latitude: 45.5300,
          longitude: -122.6700,
        ),
      );

      expect(meters, isNull);
    });

    test('returns null when scan has no GPS', () {
      final meters = fixedTagScanMismatchMeters(
        tagPlacement: NfcHuntPlacement.fixed,
        tagLocation: tagLocation,
        scanLocation: null,
      );

      expect(meters, isNull);
    });

    test('returns null when fixed tag has no placement location', () {
      final meters = fixedTagScanMismatchMeters(
        tagPlacement: NfcHuntPlacement.fixed,
        tagLocation: null,
        scanLocation: const ActivityEventLocation(
          latitude: 45.5300,
          longitude: -122.6700,
        ),
      );

      expect(meters, isNull);
    });

    test('returns small distance when scan is near fixed tag (no mismatch)', () {
      final meters = fixedTagScanMismatchMeters(
        tagPlacement: NfcHuntPlacement.fixed,
        tagLocation: tagLocation,
        scanLocation: const ActivityEventLocation(
          latitude: 45.52315,
          longitude: -122.67655,
        ),
      );

      expect(meters, isNotNull);
      expect(meters!, lessThan(kNfcHuntLocationMismatchThresholdMeters));
    });

    test('returns large distance when scan is far from fixed tag (mismatch)', () {
      final meters = fixedTagScanMismatchMeters(
        tagPlacement: NfcHuntPlacement.fixed,
        tagLocation: tagLocation,
        scanLocation: const ActivityEventLocation(
          latitude: 45.5316,
          longitude: -122.6668,
        ),
      );

      expect(meters, isNotNull);
      expect(meters!, greaterThan(kNfcHuntLocationMismatchThresholdMeters));
    });
  });

  group('isFixedTagScanMismatch', () {
    const tagLocation = ActivityEventLocation(
      latitude: 45.5231,
      longitude: -122.6765,
    );

    test('false when within threshold', () {
      expect(
        isFixedTagScanMismatch(
          tagPlacement: NfcHuntPlacement.fixed,
          tagLocation: tagLocation,
          scanLocation: const ActivityEventLocation(
            latitude: 45.52315,
            longitude: -122.67655,
          ),
        ),
        isFalse,
      );
    });

    test('true when beyond 50 m threshold', () {
      expect(
        isFixedTagScanMismatch(
          tagPlacement: NfcHuntPlacement.fixed,
          tagLocation: tagLocation,
          scanLocation: const ActivityEventLocation(
            latitude: 45.5316,
            longitude: -122.6668,
          ),
        ),
        isTrue,
      );
    });

    test('false when comparison does not apply', () {
      expect(
        isFixedTagScanMismatch(
          tagPlacement: NfcHuntPlacement.floating,
          tagLocation: tagLocation,
          scanLocation: const ActivityEventLocation(
            latitude: 45.5316,
            longitude: -122.6668,
          ),
        ),
        isFalse,
      );
    });
  });
}
