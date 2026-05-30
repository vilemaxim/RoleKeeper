import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/models/character.dart';
import 'package:rolekeeper/models/death_rules.dart';
import 'package:rolekeeper/services/character_status_service.dart';
import 'package:rolekeeper/services/death_timer_service.dart';
import 'package:rolekeeper/utils/game_firestore_paths.dart';

import '../helpers/game_tenant_test_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    DeathTimerService.testClock = null;
    DeathTimerService.instance.clear();
  });

  group('Death timer persistence (status + stats)', () {
    const uid = 'owner-99';
    const charId = 'char-z';

    late FakeFirebaseFirestore fake;
    late CharacterStatusService svc;

    setUp(() async {
      fake = FakeFirebaseFirestore();
      await seedGameTenantDocs(fake, kTestGameTenant);
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: uid, email: 'o@test.com'),
        signedIn: true,
      );
      svc = CharacterStatusService(
        firestore: fake,
        auth: auth,
        tenant: kTestGameTenant,
      );
    });

    Future<void> seedCharacter() async {
      await GameFirestorePaths.characters(fake, kTestGameTenant).doc(charId).set({
        'shortId': 'X1Y',
        'ownerId': uid,
        'name': 'Persisted Hero',
        'isArchived': false,
      });
    }

    test('setDeathTimer writes status doc and stats entry with startedAt', () async {
      await seedCharacter();
      final startedAt = DateTime.utc(2025, 7, 1, 15, 0, 0);
      final rules = DeathRules(
        enabled: true,
        countSeconds: 60,
        stages: const [],
        interventionEnabled: true,
        interventionCountSeconds: 30,
        afterDeathTimerText: 'bye',
      );
      const character = Character(
        id: charId,
        shortId: 'X1Y',
        ownerId: uid,
        name: 'Persisted Hero',
      );

      await svc.setDeathTimer(
        character: character,
        rules: rules,
        activityEventId: 'act-42',
        startedAt: startedAt,
      );

      final statusSnap = await GameFirestorePaths.characters(fake, kTestGameTenant)
          .doc(charId)
          .collection('status')
          .doc('deathTimer')
          .get();
      expect(statusSnap.exists, isTrue);
      final statusData = statusSnap.data()!;
      expect(statusData['startedAt'], isA<Timestamp>());
      expect(
        (statusData['startedAt'] as Timestamp).millisecondsSinceEpoch,
        startedAt.millisecondsSinceEpoch,
      );

      final statsSnap = await GameFirestorePaths.characters(fake, kTestGameTenant)
          .doc(charId)
          .collection('stats')
          .get();
      expect(statsSnap.docs, hasLength(1));
      expect(
        statsSnap.docs.first.data()['type'],
        CharacterStatusService.statsDocTypeDeathCounterStarted,
      );
      expect(statsSnap.docs.first.data()['activityEventId'], 'act-42');
      expect(
        (statsSnap.docs.first.data()['startedAt'] as Timestamp)
            .millisecondsSinceEpoch,
        startedAt.millisecondsSinceEpoch,
      );
    });

    test('checkDeathTimerOnLogin restores active timer from persisted status', () async {
      await seedCharacter();
      final startedAt = DateTime.now().subtract(const Duration(seconds: 20));
      await GameFirestorePaths.characters(fake, kTestGameTenant)
          .doc(charId)
          .collection('status')
          .doc('deathTimer')
          .set({
        'characterId': charId,
        'ownerId': uid,
        'characterShortId': 'X1Y',
        'characterName': 'Persisted Hero',
        'activityEventId': 'evt-x',
        'startedAt': Timestamp.fromDate(startedAt),
        'phase': 'deathCount',
        'totalSeconds': 300,
        'interventionCountSeconds': 60,
        'interventionRoleName': 'medic',
        'afterDeathTimerText': '',
      });

      final result = await svc.checkDeathTimerOnLogin();
      expect(result, isA<DeathTimerCheckActive>());
      final active = (result as DeathTimerCheckActive).status;
      expect(active.characterId, charId);
      expect(active.totalSeconds, 300);

      DeathTimerService.testClock = DateTime.now;
      DeathTimerService.instance.setActive(active.toActiveDeathTimer());
      final remaining = DeathTimerService.instance.getRemainingSeconds();
      expect(remaining, inInclusiveRange(270, 300));
    });

    test('checkDeathTimerOnLogin reports just died and clears status when expired', () async {
      await seedCharacter();
      final startedAt = DateTime.now().subtract(const Duration(seconds: 400));
      await GameFirestorePaths.characters(fake, kTestGameTenant)
          .doc(charId)
          .collection('status')
          .doc('deathTimer')
          .set({
        'characterId': charId,
        'ownerId': uid,
        'characterShortId': 'X1Y',
        'characterName': 'Persisted Hero',
        'activityEventId': 'evt-y',
        'startedAt': Timestamp.fromDate(startedAt),
        'phase': 'deathCount',
        'totalSeconds': 300,
        'interventionCountSeconds': 60,
        'interventionRoleName': 'medic',
        'afterDeathTimerText': 'Gone.',
      });

      final result = await svc.checkDeathTimerOnLogin();
      expect(result, isA<DeathTimerCheckJustDied>());
      final died = result as DeathTimerCheckJustDied;
      expect(died.character.id, charId);
      expect(died.afterDeathTimerText, 'Gone.');

      final statusAfter = await GameFirestorePaths.characters(fake, kTestGameTenant)
          .doc(charId)
          .collection('status')
          .doc('deathTimer')
          .get();
      expect(statusAfter.exists, isFalse);
    });
  });
}
