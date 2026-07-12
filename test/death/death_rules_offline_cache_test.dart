import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/models/death_rules.dart';
import 'package:rolekeeper/models/game_tenant_ref.dart';
import 'package:rolekeeper/services/rules_repository.dart';
import 'package:rolekeeper/utils/game_firestore_paths.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/game_tenant_test_paths.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

/// Simulates Firestore being unreachable so [RulesRepository] uses its cache.
class _UnavailableFirestore extends Fake implements FirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'unavailable',
      message: 'simulated offline',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Task 008 L4 — RulesRepository secure offline death rules', () {
    late DeathRules sampleRules;
    late MockFlutterSecureStorage secureStorage;
    late Map<String, String> secureStore;

    String cacheKeyFor(GameTenantRef tenant) =>
        RulesRepository.storageKeyForTenant(tenant.tenantKey);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      secureStorage = MockFlutterSecureStorage();
      secureStore = {};

      when(() => secureStorage.read(key: any(named: 'key')))
          .thenAnswer((invocation) async {
        final key = invocation.namedArguments[#key] as String;
        return secureStore[key];
      });
      when(
        () => secureStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((invocation) async {
        final key = invocation.namedArguments[#key] as String;
        final value = invocation.namedArguments[#value] as String;
        secureStore[key] = value;
      });

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

    test('source uses flutter_secure_storage, not SharedPreferences', () {
      final src =
          File('lib/services/rules_repository.dart').readAsStringSync();
      expect(
        src.contains('package:flutter_secure_storage'),
        isTrue,
        reason: 'Death rules offline cache must use flutter_secure_storage (L4).',
      );
      expect(
        src.contains('package:shared_preferences'),
        isFalse,
        reason: 'Death rules must not remain in SharedPreferences (L4).',
      );
    });

    test('storageKeyForTenant is scoped per tenant', () {
      expect(
        RulesRepository.storageKeyForTenant('a::b'),
        'rules_death_cached_a::b',
      );
    });

    test('loads from Firestore and writes secure cache when enabled', () async {
      final fake = FakeFirebaseFirestore();
      await seedGameTenantDocs(fake, kTestGameTenant);
      await GameFirestorePaths.deathRules(fake, kTestGameTenant)
          .set(sampleRules.toMap());

      final prefs = await SharedPreferences.getInstance();
      final repo = RulesRepository(
        firestore: fake,
        secureStorage: secureStorage,
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

      final cachedJson = secureStore[cacheKeyFor(kTestGameTenant)];
      expect(cachedJson, isNotNull);
      final roundTrip = DeathRules.fromMap(
        jsonDecode(cachedJson!) as Map<String, dynamic>,
      );
      expect(roundTrip.interventionRoleName, 'healer');
      expect(roundTrip.deathExpiredDialogBody, 'Custom death copy for LARP.');

      expect(
        prefs.getString('rules_death_cached_$kTestTenantKey'),
        isNull,
        reason: 'L4: must not write death rules into SharedPreferences',
      );
    });

    test('offline fallback reads cached rules from secure storage', () async {
      secureStore[cacheKeyFor(kTestGameTenant)] =
          jsonEncode(sampleRules.toMap());

      final repo = RulesRepository(
        firestore: _UnavailableFirestore(),
        secureStorage: secureStorage,
        tenant: kTestGameTenant,
      );

      final loaded = await repo.getDeathRules();

      expect(loaded.enabled, isTrue);
      expect(loaded.interventionRoleName, 'healer');
      expect(loaded.totalSeconds, 150);
      expect(loaded.deathExpiredDialogBody, 'Custom death copy for LARP.');
    });

    test('cached rules survive new repository instance (app restart)', () async {
      final fake = FakeFirebaseFirestore();
      await seedGameTenantDocs(fake, kTestGameTenant);
      await GameFirestorePaths.deathRules(fake, kTestGameTenant)
          .set(sampleRules.toMap());

      final online = RulesRepository(
        firestore: fake,
        secureStorage: secureStorage,
        tenant: kTestGameTenant,
      );
      await online.getDeathRules();

      final afterRestart = RulesRepository(
        firestore: _UnavailableFirestore(),
        secureStorage: secureStorage,
        tenant: kTestGameTenant,
      );
      final restored = await afterRestart.getDeathRules();

      expect(restored.enabled, isTrue);
      expect(restored.interventionRoleName, 'healer');
      expect(restored.totalSeconds, 150);
    });

    test('per-game cache keys isolate rules between tenants', () async {
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
        secureStorage: secureStorage,
        tenant: kTestGameTenant,
      );
      expect((await repoDefault.getDeathRules()).interventionRoleName, 'healer');

      final repoOther = RulesRepository(
        firestore: fake,
        secureStorage: secureStorage,
        tenant: other,
      );
      expect((await repoOther.getDeathRules()).interventionRoleName, 'cleric');

      expect(secureStore[cacheKeyFor(kTestGameTenant)], isNotNull);
      expect(secureStore[cacheKeyFor(other)], isNotNull);
    });
  });
}
