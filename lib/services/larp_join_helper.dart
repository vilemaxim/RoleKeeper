import '../utils/larp_manager_instance_parser.dart';
import 'game_context_service.dart';
import 'game_membership_service.dart';
import 'user_profile_service.dart';

/// Joins `games/{instanceId}/events/{eventSlug}`, updates configured LARPs, selects context.
Future<void> joinLarpAndSaveUserProfile(LarpManagerInstanceTarget target) async {
  final tenant = target.tenant;
  if (tenant == null) {
    throw ArgumentError(
      'LarpManager URL must include an event slug (e.g. …/crucible)',
    );
  }

  final membership = GameMembershipService();
  final profile = UserProfileService();

  await membership.joinLarpManagerInstance(
    tenant: tenant,
    baseUrl: target.baseUrl,
    eventSlug: target.normalizedEventSlug,
  );

  await profile.upsertConfiguredLarp(
    tenant: tenant,
    displayName: target.resolvedDisplayName,
    baseUrl: target.baseUrl,
    eventSlug: target.normalizedEventSlug,
  );
  await profile.setActiveTenantKey(tenant.tenantKey);
  GameContextService.instance.selectTenant(tenant);
}
