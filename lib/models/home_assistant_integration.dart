/// Non-sensitive Home Assistant integration fields (Firestore).
///
/// The API key hash is never loaded into this model; key generation returns
/// plaintext once from [HomeAssistantIntegrationConfigureService].
class HomeAssistantIntegrationConfig {
  const HomeAssistantIntegrationConfig({
    required this.enabled,
    required this.apiKeyConfigured,
  });

  final bool enabled;
  final bool apiKeyConfigured;

  static const empty = HomeAssistantIntegrationConfig(
    enabled: false,
    apiKeyConfigured: false,
  );

  factory HomeAssistantIntegrationConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null) return HomeAssistantIntegrationConfig.empty;
    final hash = m['apiKeyHash'];
    return HomeAssistantIntegrationConfig(
      enabled: m['enabled'] == true,
      apiKeyConfigured: hash is String && hash.isNotEmpty,
    );
  }
}
