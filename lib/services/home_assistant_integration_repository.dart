import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/game_tenant_ref.dart';
import '../models/home_assistant_integration.dart';
import '../utils/game_firestore_paths.dart';
import 'game_context_service.dart';

/// Reads Home Assistant integration config from Firestore.
class HomeAssistantIntegrationRepository {
  HomeAssistantIntegrationRepository({
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

  DocumentReference<Map<String, dynamic>> get _configRef =>
      GameFirestorePaths.homeAssistantIntegrationConfig(
        _firestore,
        _resolvedTenant,
      );

  Future<HomeAssistantIntegrationConfig> get() async {
    final snap = await _configRef.get();
    return HomeAssistantIntegrationConfig.fromMap(snap.data());
  }
}
