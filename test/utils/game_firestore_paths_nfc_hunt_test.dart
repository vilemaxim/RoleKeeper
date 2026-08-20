import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/utils/game_firestore_paths.dart';

void main() {
  group('GameFirestorePaths nfc hunt helpers', () {
    final firestore = FakeFirebaseFirestore();
    final tenant = kTestGameTenant;
    const huntId = 'hunt-forest';
    const tagUid = 'tag-oak-01';
    const characterId = 'char-alpha-01';

    String tenantPrefix() =>
        'games/${tenant.instanceId}/events/${tenant.eventSlug}';

    test('nfcHunts collection matches ADR 007 path', () {
      expect(
        GameFirestorePaths.nfcHunts(firestore, tenant).path,
        '${tenantPrefix()}/nfcHunts',
      );
    });

    test('nfcHunt document matches ADR 007 path', () {
      expect(
        GameFirestorePaths.nfcHunt(firestore, tenant, huntId).path,
        '${tenantPrefix()}/nfcHunts/$huntId',
      );
    });

    test('nfcHuntTag document uses tagUid as id', () {
      expect(
        GameFirestorePaths.nfcHuntTag(firestore, tenant, huntId, tagUid).path,
        '${tenantPrefix()}/nfcHunts/$huntId/tags/$tagUid',
      );
    });

    test('nfcHuntScans and reviewScans collections match ADR 007', () {
      expect(
        GameFirestorePaths.nfcHuntScans(firestore, tenant, huntId).path,
        '${tenantPrefix()}/nfcHunts/$huntId/scans',
      );
      expect(
        GameFirestorePaths.nfcHuntReviewScans(firestore, tenant, huntId).path,
        '${tenantPrefix()}/nfcHunts/$huntId/reviewScans',
      );
    });

    test('character nfcHuntScans mirror path matches ADR 007', () {
      expect(
        GameFirestorePaths.characterNfcHuntScans(
          firestore,
          tenant,
          characterId,
        ).path,
        '${tenantPrefix()}/characters/$characterId/nfcHuntScans',
      );
    });
  });
}
