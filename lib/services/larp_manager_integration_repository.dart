import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/game_tenant_ref.dart';
import '../models/larp_manager_integration_config.dart';
import '../utils/game_firestore_paths.dart';
import 'game_context_service.dart';

/// `games/{instanceId}/events/{eventSlug}/larpManagerIntegration/config`
class LarpManagerIntegrationRepository {
  LarpManagerIntegrationRepository({
    FirebaseFirestore? firestore,
    GameTenantRef? tenant,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _tenant = tenant ?? GameContextService.instance.currentTenant;

  final FirebaseFirestore _firestore;
  final GameTenantRef? _tenant;

  GameTenantRef get _resolvedTenant {
    final t = _tenant;
    if (t == null) throw StateError('No game selected');
    return t;
  }

  DocumentReference<Map<String, dynamic>> get _ref =>
      GameFirestorePaths.larpManagerIntegrationConfig(_firestore, _resolvedTenant);

  Future<LarpManagerIntegrationConfig> get() async {
    final snap = await _ref.get();
    return LarpManagerIntegrationConfig.fromMap(snap.data());
  }

  Future<bool> credentialsConfigured() async {
    final config = await get();
    return config.credentialsConfigured;
  }
}
