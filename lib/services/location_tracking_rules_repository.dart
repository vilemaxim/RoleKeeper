import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/game_tenant_ref.dart';
import '../models/location_tracking_rules.dart';
import '../utils/game_firestore_paths.dart';
import 'game_context_service.dart';

/// Loads and saves location tracking rules under
/// `games/{instanceId}/events/{eventSlug}/rules/locationTracking`.
class LocationTrackingRulesRepository {
  LocationTrackingRulesRepository({
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

  DocumentReference<Map<String, dynamic>> get _rulesRef =>
      GameFirestorePaths.locationTrackingRules(_firestore, _resolvedTenant);

  Future<LocationTrackingRules> get() async {
    final doc = await _rulesRef.get();
    return LocationTrackingRules.fromMap(doc.data());
  }

  Stream<LocationTrackingRules> watch() {
    return _rulesRef
        .snapshots()
        .map((doc) => LocationTrackingRules.fromMap(doc.data()));
  }

  Future<void> save(LocationTrackingRules rules) async {
    await _rulesRef.set(rules.toMap());
  }
}
