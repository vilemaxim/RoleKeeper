/// Identifies one LarpManager event tenant:
/// `games/{instanceId}/events/{eventSlug}/...`
class GameTenantRef {
  const GameTenantRef({
    required this.instanceId,
    required this.eventSlug,
  });

  /// Firestore instance doc id (FQDN), e.g. `sovereignscrolls.larpmanager.com`.
  final String instanceId;

  /// LarpManager event path segment, e.g. `crucible`.
  final String eventSlug;

  static const tenantKeySeparator = '::';

  /// Flat key for user mirrors and callables (`instanceId::eventSlug`).
  String get tenantKey => '$instanceId$tenantKeySeparator$eventSlug';

  factory GameTenantRef.parseTenantKey(String key) {
    final sep = key.indexOf(tenantKeySeparator);
    if (sep <= 0 || sep >= key.length - tenantKeySeparator.length) {
      throw FormatException('Invalid tenant key: $key');
    }
    return GameTenantRef(
      instanceId: key.substring(0, sep),
      eventSlug: key.substring(sep + tenantKeySeparator.length),
    );
  }

  /// Returns null when [key] is empty or malformed.
  static GameTenantRef? tryParseTenantKey(String? key) {
    if (key == null || key.trim().isEmpty) return null;
    try {
      return GameTenantRef.parseTenantKey(key.trim());
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is GameTenantRef &&
      other.instanceId == instanceId &&
      other.eventSlug == eventSlug;

  @override
  int get hashCode => Object.hash(instanceId, eventSlug);
}
