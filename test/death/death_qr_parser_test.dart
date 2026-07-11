import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/utils/death_qr_parser.dart';

void main() {
  group('death QR payloads (same strings as death timer / medic scan)', () {
    const signingSecret = 'test-signing-secret';

    test('parse medic QR from buildDeathMedicQrPayload', () {
      const shortId = 'A1B';
      const fallenId = 'player-uid-1';
      const eventId = 'evt-99';
      final raw = buildDeathMedicQrPayload(
        shortId: shortId,
        fallenPlayerId: fallenId,
        activityEventId: eventId,
        signingSecret: signingSecret,
      );
      expect(raw, startsWith('rolekeeper:death:v2:medic:'));
      expect(isDeathInterventionMedicQr(raw), isTrue);
      expect(isDeathInterventionQr(raw), isTrue);
      expect(verifyDeathInterventionQr(raw, signingSecret: signingSecret), isTrue);

      final parsed = parseDeathInterventionQr(raw, signingSecret: signingSecret);
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
        signingSecret: signingSecret,
      );
      expect(isDeathInterventionRevivalConfirmQr(raw), isTrue);
      final p = parseDeathInterventionQr(raw, signingSecret: signingSecret);
      expect(p!.activityEventId, 'e2');
    });

    test('reject invalid payloads', () {
      expect(parseDeathInterventionQr('https://example.com'), isNull);
      expect(parseDeathInterventionQr('rolekeeper:death:medic::u:e'), isNull);
      expect(isDeathInterventionQr('not-a-qr'), isFalse);
      expect(
        isDeathInterventionMedicQr('rolekeeper:death:medic:A1B:p1:e1'),
        isFalse,
      );
    });
  });
}
