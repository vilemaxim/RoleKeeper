import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/models/nfc_hunt_scan.dart';

void main() {
  group('NfcHuntScan', () {
    test('fromMap parses credit scan fields from ADR 007', () {
      final scannedAt = DateTime.utc(2026, 8, 19, 19);
      final clientScannedAt = DateTime.utc(2026, 8, 19, 18, 59);

      final scan = NfcHuntScan.fromMap('scan-1', {
        'characterId': 'char-alpha-01',
        'ownerUid': 'player-alpha',
        'tagUid': 'tag-oak-01',
        'scannedAt': Timestamp.fromDate(scannedAt),
        'clientScannedAt': Timestamp.fromDate(clientScannedAt),
        'location': {
          'latitude': 51.5,
          'longitude': -0.12,
        },
        'queuedOffline': true,
        'tenantKey': 'g1::crucible',
        'huntId': 'hunt-forest',
      });

      expect(scan.id, 'scan-1');
      expect(scan.characterId, 'char-alpha-01');
      expect(scan.ownerUid, 'player-alpha');
      expect(scan.tagUid, 'tag-oak-01');
      expect(scan.scannedAt, scannedAt.toLocal());
      expect(scan.clientScannedAt, clientScannedAt.toLocal());
      expect(scan.location?.latitude, 51.5);
      expect(scan.queuedOffline, isTrue);
      expect(scan.tenantKey, 'g1::crucible');
      expect(scan.huntId, 'hunt-forest');
      expect(scan.reason, isNull);
    });

    test('fromMap parses review scan reason', () {
      final scan = NfcHuntScan.fromMap('review-1', {
        'characterId': 'char-alpha-01',
        'ownerUid': 'player-alpha',
        'tagUid': 'tag-unknown',
        'scannedAt': DateTime.utc(2026, 8, 19),
        'queuedOffline': false,
        'tenantKey': 'g1::crucible',
        'huntId': 'hunt-forest',
        'reason': 'unknown_tag',
      });

      expect(scan.reason, 'unknown_tag');
      expect(scan.queuedOffline, isFalse);
    });
  });
}
