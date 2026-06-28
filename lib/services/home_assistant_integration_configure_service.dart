import 'package:cloud_functions/cloud_functions.dart';

import '../models/game_tenant_ref.dart';
import 'game_context_service.dart';

/// Invokes [configureHomeAssistantIntegration] to enable/disable HA reads and
/// generate API keys (plaintext returned once per regeneration).
class HomeAssistantIntegrationConfigureService {
  HomeAssistantIntegrationConfigureService({FirebaseFunctions? functions})
      : _functions = functions;

  final FirebaseFunctions? _functions;

  static const functionsRegion = 'us-central1';
  static const callableName = 'configureHomeAssistantIntegration';

  FirebaseFunctions get _resolved =>
      _functions ?? FirebaseFunctions.instanceFor(region: functionsRegion);

  Future<String?> configure({
    required bool enabled,
    bool regenerateKey = false,
    GameTenantRef? tenant,
  }) async {
    final t = tenant ?? GameContextService.instance.currentTenant;
    if (t == null) throw StateError('No game selected');

    final callable = _resolved.httpsCallable(callableName);
    final result = await callable.call({
      'gameId': t.tenantKey,
      'instanceId': t.instanceId,
      'eventSlug': t.eventSlug,
      'enabled': enabled,
      'regenerateKey': regenerateKey,
    });

    final raw = result.data;
    if (raw is! Map) return null;
    final key = raw['apiKey'];
    return key is String && key.isNotEmpty ? key : null;
  }
}
