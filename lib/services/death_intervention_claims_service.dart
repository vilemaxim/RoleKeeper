import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/game_tenant_ref.dart';
import '../utils/game_firestore_paths.dart';
import 'game_context_service.dart';

/// Medic claims under `games/{instanceId}/events/{eventSlug}/deathInterventionClaims`.
class DeathInterventionClaimsService {
  DeathInterventionClaimsService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    GameTenantRef? tenant,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _tenant = tenant ?? GameContextService.instance.currentTenant;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final GameTenantRef? _tenant;

  GameTenantRef get _resolvedTenant {
    final t = _tenant;
    if (t == null) throw StateError('No game selected');
    return t;
  }

  String? get _medicId => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> get _claimsCol =>
      GameFirestorePaths.deathInterventionClaims(_firestore, _resolvedTenant);

  Stream<DeathInterventionClaim?> watchClaim(String activityEventId) {
    if (activityEventId.isEmpty) return Stream.value(null);
    return _claimsCol
        .doc(activityEventId)
        .snapshots()
        .map((snap) => snap.exists ? DeathInterventionClaim.fromFirestore(snap) : null);
  }

  Future<void> claimIntervention({
    required String activityEventId,
    required String fallenPlayerId,
  }) async {
    final medicId = _medicId;
    if (medicId == null) throw StateError('Not authenticated');
    if (activityEventId.isEmpty) throw ArgumentError('activityEventId required');

    await _claimsCol.doc(activityEventId).set({
      'fallenPlayerId': fallenPlayerId,
      'medicPlayerId': medicId,
      'claimedAt': FieldValue.serverTimestamp(),
      'tenantKey': _resolvedTenant.tenantKey,
      'instanceId': _resolvedTenant.instanceId,
      'eventSlug': _resolvedTenant.eventSlug,
    });
  }

  Future<void> confirmRevival(String activityEventId) async {
    final medicId = _medicId;
    if (medicId == null) throw StateError('Not authenticated');
    if (activityEventId.isEmpty) throw ArgumentError('activityEventId required');

    final ref = _claimsCol.doc(activityEventId);
    final snap = await ref.get();
    if (!snap.exists) throw StateError('No claim found for this event');
    if (snap.get('medicPlayerId') != medicId) {
      throw StateError('Only the medic who claimed can confirm revival');
    }
    await ref.update({
      'revivalConfirmedAt': FieldValue.serverTimestamp(),
    });
  }
}

class DeathInterventionClaim {
  const DeathInterventionClaim({
    required this.activityEventId,
    required this.fallenPlayerId,
    required this.medicPlayerId,
    required this.claimedAt,
    this.revivalConfirmedAt,
  });

  final String activityEventId;
  final String fallenPlayerId;
  final String medicPlayerId;
  final DateTime? claimedAt;
  final DateTime? revivalConfirmedAt;

  static DeathInterventionClaim fromFirestore(DocumentSnapshot snap) {
    final d = snap.data() as Map<String, dynamic>? ?? {};
    final claimedAt = d['claimedAt'];
    final revivalConfirmedAt = d['revivalConfirmedAt'];
    return DeathInterventionClaim(
      activityEventId: snap.id,
      fallenPlayerId: d['fallenPlayerId'] as String? ?? '',
      medicPlayerId: d['medicPlayerId'] as String? ?? '',
      claimedAt: claimedAt is Timestamp
          ? claimedAt.toDate()
          : (claimedAt is DateTime ? claimedAt : null),
      revivalConfirmedAt: revivalConfirmedAt is Timestamp
          ? revivalConfirmedAt.toDate()
          : (revivalConfirmedAt is DateTime ? revivalConfirmedAt : null),
    );
  }
}
