/// Non-sensitive LarpManager connection fields (Firestore). Credentials live in Secret Manager.
class LarpManagerIntegrationConfig {
  const LarpManagerIntegrationConfig({
    required this.baseUrl,
    required this.eventSlug,
    required this.loginPath,
    required this.fetchDetails,
    required this.credentialsConfigured,
  });

  final String baseUrl;
  final String eventSlug;
  final String loginPath;
  final bool fetchDetails;
  final bool credentialsConfigured;

  static const empty = LarpManagerIntegrationConfig(
    baseUrl: '',
    eventSlug: '',
    loginPath: '/login/',
    fetchDetails: false,
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
      fetchDetails: m['fetchDetails'] == true,
      credentialsConfigured: m['credentialsConfigured'] == true,
    );
  }
}
