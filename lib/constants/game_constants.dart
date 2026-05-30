import '../models/game_tenant_ref.dart';

/// Test tenant: `games/rk-test.local/events/default`.
const GameTenantRef kTestGameTenant = GameTenantRef(
  instanceId: 'rk-test.local',
  eventSlug: 'default',
);

/// Flat tenant key for tests ([kTestGameTenant]).
String get kTestTenantKey => kTestGameTenant.tenantKey;
