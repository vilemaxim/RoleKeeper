import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rolekeeper/models/game_tenant_ref.dart';
import 'package:rolekeeper/models/larp_registry_entry.dart';
import 'package:rolekeeper/services/larp_registry_repository.dart';
import 'package:rolekeeper/utils/game_firestore_paths.dart';

void main() {
  group('LarpRegistryRepository', () {
    const tenant = GameTenantRef(
      instanceId: 'lm.example',
      eventSlug: 'my_event',
    );

    test('get returns null when doc missing', () async {
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1', email: 'a@b.com'),
        signedIn: true,
      );
      final firestore = FakeFirebaseFirestore();
      final repo = LarpRegistryRepository(firestore: firestore, auth: auth);

      expect(await repo.get(tenant), isNull);
    });

    test('get maps existing doc', () async {
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1', email: 'a@b.com'),
        signedIn: true,
      );
      final firestore = FakeFirebaseFirestore();
      await GameFirestorePaths.larpRegistryEvent(firestore, tenant).set({
        'tenantKey': tenant.tenantKey,
        'instanceId': tenant.instanceId,
        'eventSlug': tenant.eventSlug,
        'larpManagerBaseUrl': 'https://lm.example',
        'larpManagerEventSlug': 'my_event',
        'displayName': 'My Event',
        'organizerAccessConfigured': true,
        'createdByUid': 'u1',
      });

      final repo = LarpRegistryRepository(firestore: firestore, auth: auth);
      final e = await repo.get(tenant);

      expect(e, isA<LarpRegistryEntry>());
      expect(e!.tenant, tenant);
      expect(e.larpManagerBaseUrl, 'https://lm.example');
      expect(e.larpManagerEventSlug, 'my_event');
      expect(e.displayName, 'My Event');
      expect(e.organizerAccessConfigured, isTrue);
    });

    test(
      'markOrganizerAccessConfigured does not set organizerAccessConfigured on create (Task 005 M1)',
      () async {
        final auth = MockFirebaseAuth(
          mockUser: MockUser(uid: 'creator', email: 'c@b.com'),
          signedIn: true,
        );
        final firestore = FakeFirebaseFirestore();
        final repo = LarpRegistryRepository(firestore: firestore, auth: auth);

        const newTenant = GameTenantRef(
          instanceId: 'x.test',
          eventSlug: 'slug',
        );

        await repo.markOrganizerAccessConfigured(
          tenant: newTenant,
          larpManagerBaseUrl: 'https://x.test',
          larpManagerEventSlug: 'slug',
          displayName: 'Display',
        );

        final snap =
            await GameFirestorePaths.larpRegistryEvent(firestore, newTenant).get();
        expect(snap.exists, isTrue);
        final d = snap.data()!;
        expect(d['tenantKey'], newTenant.tenantKey);
        expect(d['larpManagerBaseUrl'], 'https://x.test');
        expect(d['larpManagerEventSlug'], 'slug');
        expect(d['displayName'], 'Display');
        expect(d['organizerAccessConfigured'], isNot(true));
        expect(d['createdByUid'], 'creator');
      },
    );

    test(
      'markOrganizerAccessConfigured does not flip organizerAccessConfigured on merge (Task 005 M1)',
      () async {
        final auth = MockFirebaseAuth(
          mockUser: MockUser(uid: 'u2', email: 'u2@b.com'),
          signedIn: true,
        );
        final firestore = FakeFirebaseFirestore();
        const oldTenant = GameTenantRef(
          instanceId: 'old.test',
          eventSlug: 'old_slug',
        );
        await GameFirestorePaths.larpRegistryEvent(firestore, oldTenant).set({
          'tenantKey': oldTenant.tenantKey,
          'larpManagerBaseUrl': 'https://old',
          'larpManagerEventSlug': 'old_slug',
          'displayName': 'Old',
          'organizerAccessConfigured': false,
          'createdByUid': 'first',
        });

        final repo = LarpRegistryRepository(firestore: firestore, auth: auth);
        await repo.markOrganizerAccessConfigured(
          tenant: oldTenant,
          larpManagerBaseUrl: 'https://new',
          larpManagerEventSlug: 'new_slug',
          displayName: 'New name',
        );

        final snap =
            await GameFirestorePaths.larpRegistryEvent(firestore, oldTenant).get();
        final d = snap.data()!;
        expect(d['createdByUid'], 'first');
        expect(d['larpManagerBaseUrl'], 'https://new');
        expect(d['larpManagerEventSlug'], 'new_slug');
        expect(d['displayName'], 'New name');
        expect(d['organizerAccessConfigured'], isNot(true));
      },
    );

    test('markOrganizerAccessConfigured no-op when signed out', () async {
      final auth = MockFirebaseAuth(signedIn: false);
      final firestore = FakeFirebaseFirestore();
      final repo = LarpRegistryRepository(firestore: firestore, auth: auth);

      const noop = GameTenantRef(instanceId: 'noop.test', eventSlug: 's');
      await repo.markOrganizerAccessConfigured(
        tenant: noop,
        larpManagerBaseUrl: 'https://x',
        larpManagerEventSlug: 's',
        displayName: 'D',
      );

      final snap = await GameFirestorePaths.larpRegistryEvent(firestore, noop).get();
      expect(snap.exists, isFalse);
    });
  });
}
