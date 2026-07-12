import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/utils/death_qr_parser.dart';

/// Example v2 signed medic QR (HMAC hex is opaque to parse tests).
const kSignedMedicQrV2Example =
    'rolekeeper:death:v2:medic:A1B:player-uid-1:evt-99:aabbccddeeff00112233445566778899';

void main() {
  group('Death QR v2 HMAC signing (H5)', () {
    test('v2 signed medic QR parses ids correctly', () {
      const raw = kSignedMedicQrV2Example;
      expect(raw, startsWith('rolekeeper:death:v2:medic:'));
      final parsed = parseDeathInterventionQr(raw);
      expect(parsed, isNotNull);
      expect(parsed!.shortId, 'A1B');
      expect(parsed.fallenPlayerId, 'player-uid-1');
      expect(parsed.activityEventId, 'evt-99');
    });

    test('isDeathInterventionMedicQr accepts v2 signed medic QR', () {
      expect(isDeathInterventionMedicQr(kSignedMedicQrV2Example), isTrue);
      expect(isDeathInterventionQr(kSignedMedicQrV2Example), isTrue);
    });

    test('unsigned v1 medic QR is rejected after v2 rollout', () {
      const raw = 'rolekeeper:death:medic:A1B:player-uid-1:evt-99';
      expect(isDeathInterventionMedicQr(raw), isFalse);
    });

    test('verifyDeathInterventionQr accepts payload signed with event secret', () {
      const signingSecret = 'event-signing-secret';
      const shortId = 'A1B';
      const fallenId = 'player-uid-1';
      const eventId = 'evt-99';
      final raw = buildDeathMedicQrPayload(
        shortId: shortId,
        fallenPlayerId: fallenId,
        activityEventId: eventId,
        signingSecret: signingSecret,
      );
      expect(verifyDeathInterventionQr(raw, signingSecret: signingSecret), isTrue);
    });

    test('verifyDeathInterventionQr rejects forged HMAC', () {
      const signingSecret = 'event-signing-secret';
      final raw = buildDeathMedicQrPayload(
        shortId: 'A1B',
        fallenPlayerId: 'player-uid-1',
        activityEventId: 'evt-99',
        signingSecret: signingSecret,
      );
      final tampered = raw.replaceFirst(
        raw.split(':').last,
        '00000000000000000000000000000000',
      );
      expect(
        verifyDeathInterventionQr(tampered, signingSecret: signingSecret),
        isFalse,
      );
    });

    test('verifyDeathInterventionQr rejects payload signed with wrong secret', () {
      final raw = buildDeathMedicQrPayload(
        shortId: 'A1B',
        fallenPlayerId: 'player-uid-1',
        activityEventId: 'evt-99',
        signingSecret: 'correct-secret',
      );
      expect(
        verifyDeathInterventionQr(raw, signingSecret: 'wrong-secret'),
        isFalse,
      );
    });

    test('canProduceSignedDeathMedicQr accepts usable secret and rejects empty', () {
      expect(
        canProduceSignedDeathMedicQr(
          signingSecret: 'event-signing-secret',
          shortId: 'A1B',
          fallenPlayerId: 'player-uid-1',
        ),
        isTrue,
      );
      expect(
        canProduceSignedDeathMedicQr(
          signingSecret: null,
          shortId: 'A1B',
          fallenPlayerId: 'player-uid-1',
        ),
        isFalse,
      );
      expect(
        canProduceSignedDeathMedicQr(
          signingSecret: '',
          shortId: 'A1B',
          fallenPlayerId: 'player-uid-1',
        ),
        isFalse,
      );
    });

    test('example v2 QR fails verification without correct secret', () {
      expect(
        verifyDeathInterventionQr(
          kSignedMedicQrV2Example,
          signingSecret: 'not-the-event-secret',
        ),
        isFalse,
      );
    });

    test('medic scan path rejects v2 QR with invalid HMAC (H5)', () {
      const raw = 'rolekeeper:death:v2:medic:A1B:player-uid-1:evt-99:'
          '00000000000000000000000000000000';
      expect(
        verifyDeathInterventionQr(raw, signingSecret: 'event-secret'),
        isFalse,
      );
      expect(parseDeathInterventionQr(raw, signingSecret: 'event-secret'), isNull);
    });
  });
}
