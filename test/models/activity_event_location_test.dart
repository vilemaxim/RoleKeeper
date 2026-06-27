import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/models/activity_event.dart';

void main() {
  group('ActivityEventLocation source field', () {
    test('toMap includes source defaulting to gps', () {
      const loc = ActivityEventLocation(
        latitude: 1.0,
        longitude: 2.0,
      );

      expect(loc.toMap()['source'], 'gps');
    });

    test('toMap preserves explicit source', () {
      const loc = ActivityEventLocation(
        latitude: 1.0,
        longitude: 2.0,
        source: 'beacon',
      );

      expect(loc.toMap()['source'], 'beacon');
    });

    test('fromMap reads source when present', () {
      final loc = ActivityEventLocation.fromMap({
        'latitude': 1.0,
        'longitude': 2.0,
        'source': 'gps',
      });

      expect(loc?.source, 'gps');
    });

    test('fromMap defaults source to gps when omitted', () {
      final loc = ActivityEventLocation.fromMap({
        'latitude': 1.0,
        'longitude': 2.0,
      });

      expect(loc?.source, 'gps');
    });
  });
}
