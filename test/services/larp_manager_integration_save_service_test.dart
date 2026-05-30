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
        fetchDetails: true,
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
        fetchDetails: false,
      );
      expect(payload['gameId'], contains('canonical-run'));
      expect(payload['eventSlug'], 'wrong-run');
    });
  });
}
