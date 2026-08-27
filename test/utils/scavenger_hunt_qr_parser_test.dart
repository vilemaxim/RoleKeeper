import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/utils/scavenger_hunt_qr_parser.dart';

void main() {
  group('parseScavengerHuntQr', () {
    test('parses valid v1 payload', () {
      final raw =
          'rolekeeper:scavenger:v1:$kTestTenantKey:hunt-forest:tag-oak-01';
      final parsed = parseScavengerHuntQr(raw);
      expect(parsed, isNotNull);
      expect(parsed!.tenantKey, kTestTenantKey);
      expect(parsed.huntId, 'hunt-forest');
      expect(parsed.tagUid, 'tag-oak-01');
    });

    test('parses when expectedTenantKey matches', () {
      final raw = 'rolekeeper:scavenger:v1:$kTestTenantKey:hunt-1:tag-1';
      final parsed = parseScavengerHuntQr(
        raw,
        expectedTenantKey: kTestTenantKey,
      );
      expect(parsed, isNotNull);
      expect(parsed!.huntId, 'hunt-1');
      expect(parsed.tagUid, 'tag-1');
    });

    test('rejects wrong tenant when expectedTenantKey given', () {
      const raw =
          'rolekeeper:scavenger:v1:other.instance::evt:hunt-1:tag-1';
      expect(
        parseScavengerHuntQr(raw, expectedTenantKey: kTestTenantKey),
        isNull,
      );
    });

    test('rejects bad version', () {
      final raw = 'rolekeeper:scavenger:v2:$kTestTenantKey:hunt-1:tag-1';
      expect(parseScavengerHuntQr(raw), isNull);
    });

    test('rejects malformed payloads', () {
      expect(parseScavengerHuntQr(''), isNull);
      expect(parseScavengerHuntQr('https://example.com'), isNull);
      expect(parseScavengerHuntQr('rolekeeper:scavenger:v1:only-two'), isNull);
      expect(
        parseScavengerHuntQr('rolekeeper:death:v2:medic:A1B:p1:e1'),
        isNull,
      );
      expect(
        parseScavengerHuntQr(
          'rolekeeper:scavenger:v1:$kTestTenantKey:hunt-only',
        ),
        isNull,
      );
    });

    test('rejects empty huntId or tagUid segments', () {
      expect(
        parseScavengerHuntQr(
          'rolekeeper:scavenger:v1:$kTestTenantKey::tag-1',
        ),
        isNull,
      );
      expect(
        parseScavengerHuntQr(
          'rolekeeper:scavenger:v1:$kTestTenantKey:hunt-1:',
        ),
        isNull,
      );
    });
  });
}
