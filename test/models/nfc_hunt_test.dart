import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/models/nfc_hunt.dart';

void main() {
  group('NfcHunt', () {
    test('fromMap parses hunt config fields from ADR 007', () {
      final created = DateTime.utc(2026, 8, 19, 12);
      final updated = DateTime.utc(2026, 8, 19, 13);

      final hunt = NfcHunt.fromMap('hunt-forest', {
        'enabled': true,
        'name': 'Forest Hunt',
        'expectedTagCount': 12,
        'placerUids': ['placer-gina', 'placer-hank'],
        'createdAt': Timestamp.fromDate(created),
        'updatedAt': Timestamp.fromDate(updated),
      });

      expect(hunt.id, 'hunt-forest');
      expect(hunt.enabled, isTrue);
      expect(hunt.name, 'Forest Hunt');
      expect(hunt.expectedTagCount, 12);
      expect(hunt.placerUids, ['placer-gina', 'placer-hank']);
      expect(hunt.createdAt, created.toLocal());
      expect(hunt.updatedAt, updated.toLocal());
    });

    test('fromMap defaults missing fields', () {
      final hunt = NfcHunt.fromMap('hunt-empty', null);

      expect(hunt.id, 'hunt-empty');
      expect(hunt.enabled, isFalse);
      expect(hunt.name, '');
      expect(hunt.expectedTagCount, 0);
      expect(hunt.placerUids, isEmpty);
      expect(hunt.createdAt, isNull);
      expect(hunt.updatedAt, isNull);
    });

    test('toMap / fromMap round-trip preserves values', () {
      final original = NfcHunt(
        id: 'hunt-forest',
        enabled: true,
        name: 'Forest Hunt',
        expectedTagCount: 8,
        placerUids: const ['placer-gina'],
        createdAt: DateTime.utc(2026, 8, 19, 12),
        updatedAt: DateTime.utc(2026, 8, 19, 13),
      );

      final roundTrip = NfcHunt.fromMap('hunt-forest', original.toMap());

      expect(roundTrip.enabled, isTrue);
      expect(roundTrip.name, 'Forest Hunt');
      expect(roundTrip.expectedTagCount, 8);
      expect(roundTrip.placerUids, ['placer-gina']);
    });
  });
}
