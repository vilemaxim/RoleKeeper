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
  });
}
