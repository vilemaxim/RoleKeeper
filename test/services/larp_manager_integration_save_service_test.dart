import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/models/game_tenant_ref.dart';
import 'package:rolekeeper/services/larp_manager_integration_save_service.dart';

void main() {
  group('LarpManagerIntegrationSaveService.buildCallablePayload', () {
    const tenant = GameTenantRef(
      instanceId: 'lm.example.com',
      eventSlug: 'canonical-run',
    );

    test('uses gameId for tenant and separate LM event slug', () {
      final payload = LarpManagerIntegrationSaveService().buildCallablePayload(
        tenant: tenant,
        baseUrl: 'https://lm.example.com',
        larpManagerEventSlug: 'lm-export-slug',
        loginPath: '/login/',
        username: 'bot',
        password: 'secret',
      );

      expect(payload['gameId'], 'lm.example.com::canonical-run');
      expect(payload['instanceId'], 'lm.example.com');
      expect(payload['eventSlug'], 'lm-export-slug');
      expect(payload['username'], 'bot');
      expect(payload['password'], 'secret');
    });

    test('gameId wins over mismatched instanceId+eventSlug on server', () {
      final payload = LarpManagerIntegrationSaveService().buildCallablePayload(
        tenant: tenant,
        baseUrl: 'https://lm.example.com',
        larpManagerEventSlug: 'wrong-run',
        loginPath: '/login/',
      );
      expect(payload['gameId'], contains('canonical-run'));
      expect(payload['eventSlug'], 'wrong-run');
    });

    // Task 012 (docs/adr/0001-remove-fetchdetails-toggle.md): the
    // payload posted to `saveLarpManagerIntegrationConfig` no longer
    // carries `fetchDetails`. Admin sync is always full — there is no
    // toggle to round-trip.
    test('Task 012: payload contains no fetchDetails key', () {
      final payload = LarpManagerIntegrationSaveService().buildCallablePayload(
        tenant: tenant,
        baseUrl: 'https://lm.example.com',
        larpManagerEventSlug: 'lm-export-slug',
        loginPath: '/login/',
        username: 'bot',
        password: 'secret',
      );

      expect(
        payload.containsKey('fetchDetails'),
        isFalse,
        reason:
            'After Task 012 the save payload must NOT include a fetchDetails '
            'key — the field is gone from the save service signature entirely.',
      );
      // Sanity: the other fields still round-trip so we know we hit the
      // payload builder, not a no-op stub.
      expect(payload['baseUrl'], 'https://lm.example.com');
      expect(payload['eventSlug'], 'lm-export-slug');
      expect(payload['loginPath'], '/login/');
    });
  });
}
