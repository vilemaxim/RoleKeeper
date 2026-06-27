import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/models/game_tenant_ref.dart';
import 'package:rolekeeper/models/location_tracking_rules.dart';
import 'package:rolekeeper/services/location_tracking_rules_repository.dart';
import 'package:rolekeeper/utils/game_firestore_paths.dart';

import '../helpers/game_tenant_test_paths.dart';

void main() {
  group('LocationTrackingRulesRepository', () {
    const sampleRules = LocationTrackingRules(
      enabled: true,
      pingIntervalSeconds: 90,
    );

    test('get returns defaults when doc is missing', () async {
      final firestore = FakeFirebaseFirestore();
      await seedGameTenantDocs(firestore, kTestGameTenant);

      final repo = LocationTrackingRulesRepository(
        firestore: firestore,
        tenant: kTestGameTenant,
      );

      final rules = await repo.get();

      expect(rules.enabled, isFalse);
      expect(rules.pingIntervalSeconds, 60);
    });

    test('get reads rules/locationTracking under current tenant', () async {
      final firestore = FakeFirebaseFirestore();
      await seedGameTenantDocs(firestore, kTestGameTenant);
      await GameFirestorePaths.locationTrackingRules(firestore, kTestGameTenant)
          .set(sampleRules.toMap());

      final repo = LocationTrackingRulesRepository(
        firestore: firestore,
        tenant: kTestGameTenant,
      );

      final rules = await repo.get();

      expect(rules.enabled, isTrue);
      expect(rules.pingIntervalSeconds, 90);
    });

    test('save writes rules/locationTracking under current tenant', () async {
      final firestore = FakeFirebaseFirestore();
      await seedGameTenantDocs(firestore, kTestGameTenant);

      final repo = LocationTrackingRulesRepository(
        firestore: firestore,
        tenant: kTestGameTenant,
      );

      await repo.save(sampleRules);

      final snap =
          await GameFirestorePaths.locationTrackingRules(firestore, kTestGameTenant)
              .get();
      expect(snap.exists, isTrue);
      expect(snap.data(), sampleRules.toMap());
    });

    test('save then get round-trips', () async {
      final firestore = FakeFirebaseFirestore();
      await seedGameTenantDocs(firestore, kTestGameTenant);

      final repo = LocationTrackingRulesRepository(
        firestore: firestore,
        tenant: kTestGameTenant,
      );

      await repo.save(sampleRules);
      final loaded = await repo.get();

      expect(loaded.enabled, sampleRules.enabled);
      expect(loaded.pingIntervalSeconds, sampleRules.pingIntervalSeconds);
    });

    test('tenant isolation: reads only the configured game', () async {
      final firestore = FakeFirebaseFirestore();
      const other = GameTenantRef(
        instanceId: 'other.local',
        eventSlug: 'default',
      );

      await seedGameTenantDocs(firestore, kTestGameTenant);
      await seedGameTenantDocs(firestore, other);

      await GameFirestorePaths.locationTrackingRules(firestore, kTestGameTenant)
          .set(const LocationTrackingRules(
        enabled: true,
        pingIntervalSeconds: 45,
      ).toMap());
      await GameFirestorePaths.locationTrackingRules(firestore, other).set(
        const LocationTrackingRules(
          enabled: true,
          pingIntervalSeconds: 180,
        ).toMap(),
      );

      final repoTest = LocationTrackingRulesRepository(
        firestore: firestore,
        tenant: kTestGameTenant,
      );
      final repoOther = LocationTrackingRulesRepository(
        firestore: firestore,
        tenant: other,
      );

      expect((await repoTest.get()).pingIntervalSeconds, 45);
      expect((await repoOther.get()).pingIntervalSeconds, 180);
    });

    test('throws when no tenant is selected', () {
      final repo = LocationTrackingRulesRepository(
        firestore: FakeFirebaseFirestore(),
        tenant: null,
      );

      expect(repo.get, throwsA(isA<StateError>()));
      expect(
        () => repo.save(sampleRules),
        throwsA(isA<StateError>()),
      );
    });
  });
}
