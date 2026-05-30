import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rolekeeper/models/game_tenant_ref.dart';
import 'package:rolekeeper/services/larp_manager_registration_service.dart';
import 'package:rolekeeper/services/larp_registry_repository.dart';
import 'package:rolekeeper/utils/game_firestore_paths.dart';

void main() {
  group('LarpManagerRegistrationService', () {
    late FakeFirebaseFirestore firestore;
    late MockUser user;
    late LarpManagerRegistrationService svc;

    final tenant = GameTenantRef(
      instanceId: 'lm.test',
      eventSlug: 'spring-run',
    );

    setUp(() {
      user = MockUser(uid: 'player-1', email: 'p@example.com');
      firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      svc = LarpManagerRegistrationService(
        firestore: firestore,
        auth: auth,
        registry: LarpRegistryRepository(firestore: firestore, auth: auth),
      );
    });

    test('getEventLinkForTenant reads configuredLarps', () async {
      await firestore.collection('users').doc(user.uid).set({
        'configuredLarps': {
          tenant.tenantKey: {
            'gameId': tenant.tenantKey,
            'larpManagerBaseUrl': 'https://lm.test',
            'larpManagerEventSlug': 'spring-run',
          },
        },
      });

      final link = await svc.getEventLinkForTenant(tenant.tenantKey);
      expect(link, isNotNull);
      expect(link!.registrationPageUrl,
          'https://lm.test/spring-run/register/');
    });

    test('isRegisteredForTenant is false until Cloud Function marks membership',
        () async {
      await GameFirestorePaths.userMembership(firestore, user.uid, tenant).set({
        'gameId': tenant.tenantKey,
        'instanceId': tenant.instanceId,
        'eventSlug': tenant.eventSlug,
        'role': 'player',
      });

      expect(await svc.isRegisteredForTenant(tenant.tenantKey), isFalse);
    });

    test('isRegisteredForTenant is true when larpManagerRegisteredAt set',
        () async {
      await GameFirestorePaths.userMembership(firestore, user.uid, tenant).set({
        'gameId': tenant.tenantKey,
        'instanceId': tenant.instanceId,
        'eventSlug': tenant.eventSlug,
        'role': 'player',
        LarpManagerRegistrationService.kLarpManagerRegisteredAtField:
            Timestamp.now(),
      });

      expect(await svc.isRegisteredForTenant(tenant.tenantKey), isTrue);
    });
  });
}
