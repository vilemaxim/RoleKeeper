import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/models/game_role.dart';
import 'package:rolekeeper/models/game_tenant_ref.dart';
import 'package:rolekeeper/models/member_presence.dart';
import 'package:rolekeeper/services/member_presence_repository.dart';
import 'package:rolekeeper/utils/game_firestore_paths.dart';

import '../helpers/game_tenant_test_paths.dart';

void main() {
  group('MemberPresenceRepository', () {
    late FakeFirebaseFirestore firestore;
    late MockUser player;
    late MockUser otherPlayer;
    late MockFirebaseAuth auth;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      player = MockUser(uid: 'player-1', email: 'p@example.com');
      otherPlayer = MockUser(uid: 'player-2', email: 'other@example.com');
      auth = MockFirebaseAuth(signedIn: true, mockUser: player);
      await seedGameTenantDocs(firestore, kTestGameTenant);
      await GameFirestorePaths.member(firestore, kTestGameTenant, player.uid)
          .set({
        'role': GameRole.player.wireName,
        'tenantKey': kTestGameTenant.tenantKey,
        'instanceId': kTestGameTenant.instanceId,
        'eventSlug': kTestGameTenant.eventSlug,
      });
    });

    MemberPresenceRepository repo({GameTenantRef? tenant}) {
      return MemberPresenceRepository(
        firestore: firestore,
        auth: auth,
        tenant: tenant ?? kTestGameTenant,
      );
    }

    test('getPresence returns defaults when member doc has no presence fields',
        () async {
      final presence = await repo().getPresence();

      expect(presence.locationOptIn, isFalse);
      expect(presence.presenceState, PresenceState.inGame);
    });

    test('getPresence reads locationOptIn and presenceState from member doc',
        () async {
      await GameFirestorePaths.member(firestore, kTestGameTenant, player.uid)
          .set({
        'role': GameRole.player.wireName,
        'locationOptIn': true,
        'presenceState': 'out_of_game',
      }, SetOptions(merge: true));

      final presence = await repo().getPresence();

      expect(presence.locationOptIn, isTrue);
      expect(presence.presenceState, PresenceState.outOfGame);
    });

    test('setLocationOptIn merges locationOptIn without changing role', () async {
      await repo().setLocationOptIn(true);

      final snap =
          await GameFirestorePaths.member(firestore, kTestGameTenant, player.uid)
              .get();
      expect(snap.data()?['locationOptIn'], isTrue);
      expect(snap.data()?['role'], GameRole.player.wireName);
      expect(snap.data()?['presenceUpdatedAt'], isNotNull);
    });

    test('setPresenceState merges presenceState without changing role', () async {
      await repo().setPresenceState(PresenceState.outOfGame);

      final snap =
          await GameFirestorePaths.member(firestore, kTestGameTenant, player.uid)
              .get();
      expect(snap.data()?['presenceState'], 'out_of_game');
      expect(snap.data()?['role'], GameRole.player.wireName);
      expect(snap.data()?['presenceUpdatedAt'], isNotNull);
    });

    test('writes only the signed-in user member document', () async {
      await GameFirestorePaths.member(
        firestore,
        kTestGameTenant,
        otherPlayer.uid,
      ).set({
        'role': GameRole.player.wireName,
        'locationOptIn': false,
      });

      await repo().setLocationOptIn(true);

      final otherSnap = await GameFirestorePaths.member(
        firestore,
        kTestGameTenant,
        otherPlayer.uid,
      ).get();
      expect(otherSnap.data()?['locationOptIn'], isFalse);
    });

    test('tenant isolation: reads only the configured game', () async {
      const other = GameTenantRef(
        instanceId: 'other.local',
        eventSlug: 'default',
      );
      await seedGameTenantDocs(firestore, other);
      await GameFirestorePaths.member(firestore, kTestGameTenant, player.uid)
          .set({'locationOptIn': true}, SetOptions(merge: true));
      await GameFirestorePaths.member(firestore, other, player.uid).set({
        'role': GameRole.player.wireName,
        'locationOptIn': false,
      });

      final testPresence = await repo(tenant: kTestGameTenant).getPresence();
      final otherPresence = await repo(tenant: other).getPresence();

      expect(testPresence.locationOptIn, isTrue);
      expect(otherPresence.locationOptIn, isFalse);
    });

    test('throws when no tenant is selected', () {
      final noTenantRepo = MemberPresenceRepository(
        firestore: firestore,
        auth: auth,
        tenant: null,
      );

      expect(noTenantRepo.getPresence, throwsA(isA<StateError>()));
      expect(
        () => noTenantRepo.setLocationOptIn(true),
        throwsA(isA<StateError>()),
      );
      expect(
        () => noTenantRepo.setPresenceState(PresenceState.outOfGame),
        throwsA(isA<StateError>()),
      );
    });

    test('throws when user is not signed in', () {
      final signedOutAuth = MockFirebaseAuth();
      final signedOutRepo = MemberPresenceRepository(
        firestore: firestore,
        auth: signedOutAuth,
        tenant: kTestGameTenant,
      );

      expect(signedOutRepo.getPresence, throwsA(isA<StateError>()));
    });
  });
}
