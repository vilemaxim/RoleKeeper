import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/models/game_role.dart';
import 'package:rolekeeper/services/death_intervention_claims_service.dart';
import 'package:rolekeeper/services/game_context_service.dart';
import 'package:rolekeeper/services/game_membership_service.dart';
import 'package:rolekeeper/utils/game_firestore_paths.dart';

import '../helpers/game_tenant_test_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(GameContextService.instance.resetForTest);

  group('Death intervention medic authorization (H4)', () {
    Future<({DeathInterventionClaimsService svc, FakeFirebaseFirestore firestore})>
        serviceForRole({
      required GameRole role,
      required String uid,
    }) async {
      GameContextService.instance.currentTenantForTest = kTestGameTenant;
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: uid, email: '$uid@test.com'),
        signedIn: true,
      );
      final firestore = FakeFirebaseFirestore();
      await seedGameTenantDocs(firestore, kTestGameTenant);
      await GameMembershipService(firestore: firestore, auth: auth).addUserToGame(
        tenant: kTestGameTenant,
        userId: uid,
        role: role,
      );
      final svc = DeathInterventionClaimsService(
        firestore: firestore,
        auth: auth,
        tenant: kTestGameTenant,
      );
      return (svc: svc, firestore: firestore);
    }

    test('plain player cannot claim intervention client-side', () async {
      final setup = await serviceForRole(
        role: GameRole.player,
        uid: 'player-only-uid',
      );

      await expectLater(
        setup.svc.claimIntervention(
          activityEventId: 'activity-event-123',
          fallenPlayerId: 'fallen-player-uid',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('staff'),
          ),
        ),
      );

      final claimSnap = await GameFirestorePaths.deathInterventionClaims(
        setup.firestore,
        kTestGameTenant,
      ).doc('activity-event-123').get();
      expect(claimSnap.exists, isFalse);
    });

    test('staff member can claim intervention client-side', () async {
      final setup = await serviceForRole(
        role: GameRole.staff,
        uid: 'staff-medic-uid',
      );

      await setup.svc.claimIntervention(
        activityEventId: 'activity-event-456',
        fallenPlayerId: 'fallen-player-uid',
      );

      final claimSnap = await GameFirestorePaths.deathInterventionClaims(
        setup.firestore,
        kTestGameTenant,
      ).doc('activity-event-456').get();
      expect(claimSnap.exists, isTrue);
      expect(claimSnap.data()!['medicPlayerId'], 'staff-medic-uid');
    });
  });
}
