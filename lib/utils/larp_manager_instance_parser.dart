import '../models/game_tenant_ref.dart';

/// Parsed LarpManager site URL (scheme + host, optional first path segment as event slug).
class LarpManagerInstanceTarget {
  const LarpManagerInstanceTarget({
    required this.baseUrl,
    required this.eventSlug,
    this.displayNameForProfile,
  });

  /// Origin only, e.g. `https://events.example.com`
  final String baseUrl;

  /// First non-empty path segment when present, else empty.
  final String eventSlug;

  /// Optional label for LARP list / `larpRegistry` (e.g. preset quick-picks).
  final String? displayNameForProfile;

  /// Firestore instance doc id (FQDN with dots), e.g. `sovereignscrolls.larpmanager.com`.
  String get instanceId => Uri.parse(baseUrl).host.toLowerCase();

  /// Normalized event slug (lowercase).
  String get normalizedEventSlug => eventSlug.trim().toLowerCase();

  /// `games/{instanceId}/events/{eventSlug}` when slug is non-empty.
  GameTenantRef? get tenant {
    final slug = normalizedEventSlug;
    if (slug.isEmpty) return null;
    return GameTenantRef(instanceId: instanceId, eventSlug: slug);
  }

  /// Display name in user profile and registry when not overridden.
  String get resolvedDisplayName {
    final hint = displayNameForProfile?.trim();
    if (hint != null && hint.isNotEmpty) {
      return hint;
    }
    if (normalizedEventSlug.isNotEmpty) {
      return normalizedEventSlug.replaceAll('_', ' ');
    }
    return instanceId;
  }

  /// Full event page URL (instance + first path segment), no trailing slash.
  String get canonicalEventPageUrl {
    return canonicalLarpEventPageUrl(baseUrl, eventSlug);
  }
}

/// One stable string per LARP: scheme + host [(+port)] and optional `/` first segment.
String canonicalLarpEventPageUrl(String baseUrl, String eventSlug) {
  final u = Uri.parse(baseUrl.trim());
  if (!u.hasScheme || u.host.isEmpty) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final slug = eventSlug.trim().toLowerCase();
    if (slug.isEmpty) return base;
    return '$base/$slug';
  }
  final origin = u.origin; // lowercases host, normalizes default ports
  final slug = eventSlug.trim().toLowerCase();
  if (slug.isEmpty) {
    return origin;
  }
  return '$origin/$slug';
}

/// Normalizes user input or scanned text into a [LarpManagerInstanceTarget], or null if invalid.
LarpManagerInstanceTarget? parseLarpManagerInstance(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;

  if (!s.contains('://')) {
    if (s.contains('/') && !s.startsWith('/')) {
      s = 'https://$s';
    } else if (s.contains('.')) {
      s = 'https://$s';
    } else {
      return null;
    }
  }

  final uri = Uri.tryParse(s);
  if (uri == null || !uri.hasAuthority) return null;

  var scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;

  final host = uri.host;
  if (host.isEmpty) return null;

  final origin = '$scheme://$host${uri.hasPort ? ':${uri.port}' : ''}';
  final segments = uri.pathSegments.where((e) => e.isNotEmpty).toList();
  final slug = segments.isNotEmpty ? segments.first : '';

  return LarpManagerInstanceTarget(baseUrl: origin, eventSlug: slug);
}
