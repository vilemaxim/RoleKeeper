import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/models/death_rules.dart';
import 'package:rolekeeper/models/game_tenant_ref.dart';
import 'package:rolekeeper/services/rules_repository.dart';
import 'package:rolekeeper/utils/game_firestore_paths.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/game_tenant_test_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RulesRepository offline death rules', () {
    late DeathRules sampleRules;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      sampleRules = DeathRules(
        enabled: true,
        countSeconds: 100,
        stages: const [
          DeathStage(
            id: '1',
            label: 'Bleeding',
            countSeconds: 50,
            playerDescription: 'You feel weak',
          ),
        ],
        interventionEnabled: true,
        interventionCountSeconds: 45,
        interventionRoleName: 'healer',
        afterDeathTimerText: 'Custom death copy for LARP.',
      );
    });

    test('loads from Firestore and writes cache when enabled', () async {
      final fake = FakeFirebaseFirestore();
      await seedGameTenantDocs(fake, kTestGameTenant);
      await GameFirestorePaths.deathRules(fake, kTestGameTenant)
          .set(sampleRules.toMap());

      final prefs = await SharedPreferences.getInstance();
      final repo = RulesRepository(
        firestore: fake,
        prefs: prefs,
        tenant: kTestGameTenant,
      );

      final loaded = await repo.getDeathRules();

      expect(loaded.enabled, isTrue);
      expect(loaded.totalSeconds, 150);
      expect(loaded.interventionRoleName, 'healer');
      expect(loaded.afterDeathTimerText, 'Custom death copy for LARP.');
      expect(loaded.interventionCountSeconds, 45);
      expect(loaded.stages, hasLength(1));
      expect(loaded.stages.first.label, 'Bleeding');

      final cachedJson =
          prefs.getString('rules_death_cached_$kTestTenantKey');
      expect(cachedJson, isNotNull);
      final roundTrip = DeathRules.fromMap(
        jsonDecode(cachedJson!) as Map<String, dynamic>,
      );
      expect(roundTrip.interventionRoleName, 'healer');
      expect(roundTrip.deathExpiredDialogBody, 'Custom death copy for LARP.');
    });

    test('per-game cache keys isolate rules between tenants', () async {
      final prefs = await SharedPreferences.getInstance();
      final fake = FakeFirebaseFirestore();
      const other = GameTenantRef(
        instanceId: 'other.local',
        eventSlug: 'default',
      );

      await seedGameTenantDocs(fake, kTestGameTenant);
      await GameFirestorePaths.deathRules(fake, kTestGameTenant)
          .set(sampleRules.toMap());

      final otherRules = DeathRules(
        enabled: true,
        countSeconds: 10,
        stages: const [],
        interventionEnabled: false,
        interventionRoleName: 'cleric',
      );
      await seedGameTenantDocs(fake, other);
      await GameFirestorePaths.deathRules(fake, other).set(otherRules.toMap());

      final repoDefault = RulesRepository(
        firestore: fake,
        prefs: prefs,
        tenant: kTestGameTenant,
      );
      expect((await repoDefault.getDeathRules()).interventionRoleName, 'healer');

      final repoOther = RulesRepository(
        firestore: fake,
        prefs: prefs,
        tenant: other,
      );
      expect((await repoOther.getDeathRules()).interventionRoleName, 'cleric');

      expect(
        prefs.getString('rules_death_cached_$kTestTenantKey'),
        isNotNull,
      );
      expect(
        prefs.getString('rules_death_cached_${other.tenantKey}'),
        isNotNull,
      );
    });
  });
}
