import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/utils/death_qr_parser.dart';

void main() {
  group('death QR payloads (same strings as death timer / medic scan)', () {
    test('parse medic QR from buildDeathMedicQrPayload', () {
      const shortId = 'A1B';
      const fallenId = 'player-uid-1';
      const eventId = 'evt-99';
      final raw = buildDeathMedicQrPayload(
        shortId: shortId,
        fallenPlayerId: fallenId,
        activityEventId: eventId,
      );
      expect(raw, 'rolekeeper:death:medic:A1B:player-uid-1:evt-99');
      expect(isDeathInterventionMedicQr(raw), isTrue);
      expect(isDeathInterventionQr(raw), isTrue);

      final parsed = parseDeathInterventionQr(raw);
      expect(parsed, isNotNull);
      expect(parsed!.shortId, shortId);
      expect(parsed.fallenPlayerId, fallenId);
      expect(parsed.activityEventId, eventId);
    });

    test('parse revival-confirm QR', () {
      final raw = buildDeathRevivalConfirmQrPayload(
        shortId: 'XYZ',
        fallenPlayerId: 'p2',
        activityEventId: 'e2',
      );
      expect(isDeathInterventionRevivalConfirmQr(raw), isTrue);
      final p = parseDeathInterventionQr(raw);
      expect(p!.activityEventId, 'e2');
    });

    test('reject invalid payloads', () {
      expect(parseDeathInterventionQr('https://example.com'), isNull);
      expect(parseDeathInterventionQr('rolekeeper:death:medic::u:e'), isNull);
      expect(isDeathInterventionQr('not-a-qr'), isFalse);
    });
  });
}
