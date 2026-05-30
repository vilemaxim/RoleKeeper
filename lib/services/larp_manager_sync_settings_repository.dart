import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/game_tenant_ref.dart';
import '../models/larp_manager_sync_settings.dart';
import '../utils/game_firestore_paths.dart';
import 'game_context_service.dart';

/// `games/{instanceId}/events/{eventSlug}/larpManagerSyncSettings/config`
class LarpManagerSyncSettingsRepository {
  LarpManagerSyncSettingsRepository({
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
      GameFirestorePaths.larpManagerSyncSettingsConfig(_firestore, _resolvedTenant);

  Future<LarpManagerSyncSettings> get() async {
    final snap = await _ref.get();
    return LarpManagerSyncSettings.fromMap(snap.data());
  }

  Future<void> save(LarpManagerSyncSettings s) =>
      _ref.set(s.toMap(), SetOptions(merge: true));
}
