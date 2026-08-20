import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/models/activity_event.dart';
import 'package:rolekeeper/models/nfc_hunt_tag.dart';

void main() {
  group('NfcHuntTag', () {
    test('fromMap parses fixed tag with optional location and label', () {
      final registeredAt = DateTime.utc(2026, 8, 19, 18);

      final tag = NfcHuntTag.fromMap('tag-oak-01', {
        'label': 'Oak grove',
        'placement': 'fixed',
        'location': {
          'latitude': 51.5074,
          'longitude': -0.1278,
          'source': 'gps',
        },
        'registeredByUid': 'placer-gina',
        'registeredAt': Timestamp.fromDate(registeredAt),
      });

      expect(tag.tagUid, 'tag-oak-01');
      expect(tag.label, 'Oak grove');
      expect(tag.placement, NfcHuntPlacement.fixed);
      expect(tag.location?.latitude, 51.5074);
      expect(tag.location?.longitude, -0.1278);
      expect(tag.registeredByUid, 'placer-gina');
      expect(tag.registeredAt, registeredAt.toLocal());
    });

    test('fromMap treats floating placement and omits location', () {
      final tag = NfcHuntTag.fromMap('tag-float', {
        'placement': 'floating',
        'registeredByUid': 'owner-alice',
        'registeredAt': DateTime.utc(2026, 8, 19),
      });

      expect(tag.placement, NfcHuntPlacement.floating);
      expect(tag.location, isNull);
      expect(tag.label, isNull);
    });

    test('toMap omits location for floating tags', () {
      final tag = NfcHuntTag(
        tagUid: 'tag-float',
        placement: NfcHuntPlacement.floating,
        registeredByUid: 'owner-alice',
        registeredAt: DateTime.utc(2026, 8, 19),
        location: const ActivityEventLocation(
          latitude: 1,
          longitude: 2,
        ),
      );

      final map = tag.toMap();
      expect(map['placement'], 'floating');
      expect(map.containsKey('location'), isFalse);
    });
  });
}
