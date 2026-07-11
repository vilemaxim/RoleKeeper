import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/models/game_role.dart';
import 'package:rolekeeper/services/death_intervention_claims_service.dart';
import 'package:rolekeeper/services/game_context_service.dart';
import 'package:rolekeeper/services/game_membership_service.dart';
import 'package:rolekeeper/utils/death_qr_parser.dart';
import 'package:rolekeeper/utils/game_firestore_paths.dart';

import '../helpers/game_tenant_test_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(GameContextService.instance.resetForTest);

  group('Online medic intervention (Firestore + QR payload)', () {
    test('QR payload parses then claim + confirm write expected fields', () async {
      const fallenId = 'fallen-player-uid';
      const activityId = 'activity-event-123';
      const shortId = 'Z9Y';
      const signingSecret = 'online-test-signing-secret';

      GameContextService.instance.currentTenantForTest = kTestGameTenant;

      final raw = buildDeathMedicQrPayload(
        shortId: shortId,
        fallenPlayerId: fallenId,
        activityEventId: activityId,
        signingSecret: signingSecret,
      );
      expect(verifyDeathInterventionQr(raw, signingSecret: signingSecret), isTrue);
      final parsed = parseDeathInterventionQr(raw, signingSecret: signingSecret);
      expect(parsed, isNotNull);
      expect(parsed!.activityEventId, activityId);
      expect(parsed.fallenPlayerId, fallenId);

      final medicUser = MockUser(uid: 'medic-uid-7', email: 'medic@test.com');
      final auth = MockFirebaseAuth(mockUser: medicUser, signedIn: true);
      final fake = FakeFirebaseFirestore();
      await seedGameTenantDocs(fake, kTestGameTenant);
      await GameMembershipService(firestore: fake, auth: auth).addUserToGame(
        tenant: kTestGameTenant,
        userId: 'medic-uid-7',
        role: GameRole.staff,
      );

      final svc = DeathInterventionClaimsService(
        firestore: fake,
        auth: auth,
        tenant: kTestGameTenant,
      );

      await svc.claimIntervention(
        activityEventId: parsed.activityEventId,
        fallenPlayerId: parsed.fallenPlayerId,
      );

      final claimSnap = await GameFirestorePaths.deathInterventionClaims(
        fake,
        kTestGameTenant,
      ).doc(activityId).get();
      expect(claimSnap.exists, isTrue);
      expect(claimSnap.data()!['fallenPlayerId'], fallenId);
      expect(claimSnap.data()!['medicPlayerId'], 'medic-uid-7');

      await svc.confirmRevival(activityId);

      final after = await GameFirestorePaths.deathInterventionClaims(
        fake,
        kTestGameTenant,
      ).doc(activityId).get();
      expect(after.data()!.containsKey('revivalConfirmedAt'), isTrue);
    });
  });
}
