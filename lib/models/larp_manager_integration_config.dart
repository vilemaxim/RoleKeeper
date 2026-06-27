/// Non-sensitive LarpManager connection fields (Firestore). Credentials live in Secret Manager.
///
/// Task 012 (`docs/adr/0001-remove-fetchdetails-toggle.md`) removed the
/// `fetchDetails` field. Admin sync is always full. `fromMap` still
/// tolerates a legacy `fetchDetails: bool` key in the stored Firestore
/// doc — we did not run a Firestore migration to delete the stale field
/// — but the value is silently ignored and never surfaced on the model.
class LarpManagerIntegrationConfig {
  const LarpManagerIntegrationConfig({
    required this.baseUrl,
    required this.eventSlug,
    required this.loginPath,
    required this.credentialsConfigured,
  });

  final String baseUrl;
  final String eventSlug;
  final String loginPath;
  final bool credentialsConfigured;

  static const empty = LarpManagerIntegrationConfig(
    baseUrl: '',
    eventSlug: '',
    loginPath: '/login/',
    credentialsConfigured: false,
  );

  factory LarpManagerIntegrationConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null) return LarpManagerIntegrationConfig.empty;
    return LarpManagerIntegrationConfig(
      baseUrl: (m['baseUrl'] as String?)?.trim() ?? '',
      eventSlug: (m['eventSlug'] as String?)?.trim() ?? '',
      loginPath: (m['loginPath'] as String?)?.trim().isNotEmpty == true
          ? (m['loginPath'] as String).trim()
          : '/login/',
      credentialsConfigured: m['credentialsConfigured'] == true,
    );
  }
}
