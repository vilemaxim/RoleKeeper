import 'game_tenant_ref.dart';

/// Global catalog doc: `larpRegistry/{instanceId}/events/{eventSlug}`.
class LarpRegistryEntry {
  const LarpRegistryEntry({
    required this.tenant,
    required this.larpManagerBaseUrl,
    required this.larpManagerEventSlug,
    required this.displayName,
    required this.organizerAccessConfigured,
  });

  final GameTenantRef tenant;
  final String larpManagerBaseUrl;
  final String larpManagerEventSlug;
  final String displayName;
  final bool organizerAccessConfigured;

  factory LarpRegistryEntry.fromMap(
    GameTenantRef tenant,
    Map<String, dynamic>? m,
  ) {
    if (m == null) {
      return LarpRegistryEntry(
        tenant: tenant,
        larpManagerBaseUrl: '',
        larpManagerEventSlug: tenant.eventSlug,
        displayName: tenant.eventSlug,
        organizerAccessConfigured: false,
      );
    }
    return LarpRegistryEntry(
      tenant: tenant,
      larpManagerBaseUrl: (m['larpManagerBaseUrl'] as String?)?.trim() ?? '',
      larpManagerEventSlug:
          (m['larpManagerEventSlug'] as String?)?.trim() ?? tenant.eventSlug,
      displayName: (m['displayName'] as String?)?.trim() ?? tenant.eventSlug,
      organizerAccessConfigured: m['organizerAccessConfigured'] == true,
    );
  }

  @Deprecated('Use tenant.tenantKey')
  String get gameId => tenant.tenantKey;
}
