import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/services/game_context_service.dart';
import 'package:rolekeeper/services/user_profile_service.dart';

void main() {
  tearDown(GameContextService.instance.resetForTest);

  group('UserProfileService.shouldShowLarpPicker', () {
    test('returns false when signed out', () async {
      final auth = MockFirebaseAuth(signedIn: false);
      final firestore = FakeFirebaseFirestore();
      final svc = UserProfileService(firestore: firestore, auth: auth);

      expect(await svc.shouldShowLarpPicker(), isFalse);
    });

    test('returns true when configuredLarps is empty', () async {
      final user = MockUser(uid: 'new-user-1', email: 'n@b.com');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final firestore = FakeFirebaseFirestore();
      final svc = UserProfileService(firestore: firestore, auth: auth);

      expect(await svc.shouldShowLarpPicker(), isTrue);
    });

    test('returns false when at least one configured LARP exists', () async {
      final user = MockUser(uid: 'u-larps', email: 'l@b.com');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('users').doc(user.uid).set({
        UserProfileService.kConfiguredLarpsField: {
          'lm.example::evt': {
            'tenantKey': 'lm.example::evt',
            'displayName': 'Event X',
            'configuredAt': Timestamp.fromDate(DateTime.utc(2025, 1, 1)),
          },
        },
      });

      final svc = UserProfileService(firestore: firestore, auth: auth);
      expect(await svc.shouldShowLarpPicker(), isFalse);
    });

    test(
      'legacy: only default membership does not fill configuredLarps; user stays in picker flow',
      () async {
        final user = MockUser(uid: 'legacy-default', email: 'd@b.com');
        final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
        final firestore = FakeFirebaseFirestore();
        final userRef = firestore.collection('users').doc(user.uid);
        await userRef.collection('gameMemberships').doc('default').set({
          'role': 'player',
          'gameId': 'default',
        });
        final svc = UserProfileService(firestore: firestore, auth: auth);

        expect(await svc.shouldShowLarpPicker(), isTrue);

        final snap = await userRef.get();
        final larps = snap.data()?[UserProfileService.kConfiguredLarpsField];
        expect(larps is Map ? (larps).isEmpty : true, isTrue);
      },
    );

    test(
      'legacy: non-default membership migrates into configuredLarps then picker is skipped',
      () async {
        final user = MockUser(uid: 'legacy-mig', email: 'm@b.com');
        final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
        final firestore = FakeFirebaseFirestore();
        final userRef = firestore.collection('users').doc(user.uid);
        const tenantKey = 'lm.example::migrated';
        await userRef.collection('gameMemberships').doc(tenantKey).set({
          'role': 'player',
          'tenantKey': tenantKey,
          'instanceId': 'lm.example',
          'eventSlug': 'migrated',
        });
        await firestore
            .collection('games')
            .doc('lm.example')
            .collection('events')
            .doc('migrated')
            .set({
          'displayName': 'Migrated Event',
          'larpManagerBaseUrl': 'https://lm.example',
        });

        final svc = UserProfileService(firestore: firestore, auth: auth);
        expect(await svc.shouldShowLarpPicker(), isFalse);

        final snap = await userRef.get();
        final map =
            snap.data()?[UserProfileService.kConfiguredLarpsField] as Map?;
        expect(map?[tenantKey]['displayName'], 'Migrated Event');
      },
    );
  });

  group('UserProfileService.restoreActiveGameContext', () {
    test('selects activeGameId when it matches configuredLarps', () async {
      final user = MockUser(uid: 'u-restore', email: 'r@b.com');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final firestore = FakeFirebaseFirestore();
      final userRef = firestore.collection('users').doc(user.uid);
      await userRef.set({
        'activeGameId': 'a.example::one',
        UserProfileService.kConfiguredLarpsField: {
          'a.example::one': {
            'displayName': 'A',
            'tenantKey': 'a.example::one',
            'configuredAt': Timestamp.fromDate(DateTime.utc(2025, 2, 1)),
          },
          'b.example::two': {
            'displayName': 'B',
            'tenantKey': 'b.example::two',
            'configuredAt': Timestamp.fromDate(DateTime.utc(2025, 1, 1)),
          },
        },
      });

      final svc = UserProfileService(firestore: firestore, auth: auth);
      await svc.restoreActiveGameContext();

      expect(GameContextService.instance.currentGameId, 'a.example::one');
    });

    test('falls back and re-persists when activeGameId is stale', () async {
      final user = MockUser(uid: 'u-stale', email: 's@b.com');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final firestore = FakeFirebaseFirestore();
      final userRef = firestore.collection('users').doc(user.uid);
      await userRef.set({
        'activeGameId': 'gone',
        UserProfileService.kConfiguredLarpsField: {
          'b.example::two': {
            'displayName': 'B',
            'tenantKey': 'b.example::two',
            'configuredAt': Timestamp.fromDate(DateTime.utc(2025, 1, 1)),
          },
        },
      });

      final svc = UserProfileService(firestore: firestore, auth: auth);
      await svc.restoreActiveGameContext();

      expect(GameContextService.instance.currentGameId, 'b.example::two');
      final snap = await userRef.get();
      expect(snap.data()?['activeGameId'], 'b.example::two');
    });

    test('clears game context when configuredLarps is empty', () async {
      final user = MockUser(uid: 'u-empty', email: 'e@b.com');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final firestore = FakeFirebaseFirestore();
      final userRef = firestore.collection('users').doc(user.uid);
      await userRef.set({'activeGameId': 'orphan'});

      final svc = UserProfileService(firestore: firestore, auth: auth);
      await svc.restoreActiveGameContext();

      expect(GameContextService.instance.hasSelectedGame, isFalse);
      final snap = await userRef.get();
      expect(snap.data()?.containsKey('activeGameId'), isFalse);
    });
  });

  group('UserProfileService.setActiveTenantKey', () {
    test('writes activeGameId on user doc', () async {
      final user = MockUser(uid: 'mark-1', email: 'm@b.com');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final firestore = FakeFirebaseFirestore();
      final svc = UserProfileService(firestore: firestore, auth: auth);

      await svc.setActiveTenantKey(kTestTenantKey);

      final snap = await firestore.collection('users').doc(user.uid).get();
      expect(snap.data()?['activeGameId'], kTestTenantKey);
    });
  });
}
