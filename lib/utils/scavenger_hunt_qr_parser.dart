/// Parsed scavenger-hunt QR payload (ADR 007 v1).
class ScavengerHuntQrPayload {
  const ScavengerHuntQrPayload({
    required this.tenantKey,
    required this.huntId,
    required this.tagUid,
  });

  final String tenantKey;
  final String huntId;
  final String tagUid;
}

const _prefix = 'rolekeeper:scavenger:v1:';

/// Parses `rolekeeper:scavenger:v1:{tenantKey}:{huntId}:{tagUid}`.
///
/// [tenantKey] is `instanceId::eventSlug` and may itself contain `:`.
/// Returns null for malformed / wrong-version payloads, or when
/// [expectedTenantKey] is set and does not match.
ScavengerHuntQrPayload? parseScavengerHuntQr(
  String raw, {
  String? expectedTenantKey,
}) {
  final s = raw.trim();
  if (!s.startsWith(_prefix)) return null;

  final rest = s.substring(_prefix.length);
  final lastColon = rest.lastIndexOf(':');
  if (lastColon <= 0) return null;

  final tagUid = rest.substring(lastColon + 1).trim();
  if (tagUid.isEmpty) return null;

  final beforeTag = rest.substring(0, lastColon);
  final huntColon = beforeTag.lastIndexOf(':');
  if (huntColon <= 0) return null;

  final huntId = beforeTag.substring(huntColon + 1).trim();
  final tenantKey = beforeTag.substring(0, huntColon).trim();
  if (huntId.isEmpty || tenantKey.isEmpty) return null;
  if (!tenantKey.contains('::')) return null;

  if (expectedTenantKey != null && tenantKey != expectedTenantKey) {
    return null;
  }

  return ScavengerHuntQrPayload(
    tenantKey: tenantKey,
    huntId: huntId,
    tagUid: tagUid,
  );
}
