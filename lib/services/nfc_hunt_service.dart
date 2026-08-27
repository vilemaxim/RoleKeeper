import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/activity_event.dart';
import '../models/game_tenant_ref.dart';
import '../models/nfc_hunt.dart';
import '../models/nfc_hunt_tag.dart';
import '../utils/game_firestore_paths.dart';
import 'game_context_service.dart';

/// Firestore hunt CRUD + `registerNfcHuntTag` callable for tag registration.
class NfcHuntService {
  NfcHuntService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    GameTenantRef? tenant,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance,
        _tenant = tenant ?? GameContextService.instance.currentTenant;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final GameTenantRef? _tenant;

  GameTenantRef get _resolvedTenant {
    final t = _tenant;
    if (t == null) throw StateError('No game selected');
    return t;
  }

  Future<List<NfcHunt>> listHunts() async {
    final snap =
        await GameFirestorePaths.nfcHunts(_firestore, _resolvedTenant).get();
    return snap.docs
        .map((d) => NfcHunt.fromMap(d.id, d.data()))
        .toList(growable: false);
  }

  /// Live hunt list for the current tenant (player scan entry gating).
  Stream<List<NfcHunt>> watchHunts() {
    return GameFirestorePaths.nfcHunts(_firestore, _resolvedTenant)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => NfcHunt.fromMap(d.id, d.data()))
              .toList(growable: false),
        );
  }

  Future<NfcHunt> createHunt({
    required String name,
    required int expectedTagCount,
  }) async {
    final ref =
        GameFirestorePaths.nfcHunts(_firestore, _resolvedTenant).doc();
    final hunt = NfcHunt(
      id: ref.id,
      enabled: false,
      name: name.trim(),
      expectedTagCount: expectedTagCount,
      placerUids: const [],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await ref.set({
      ...hunt.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return hunt;
  }

  Future<void> setEnabled(String huntId, bool enabled) async {
    await GameFirestorePaths.nfcHunt(_firestore, _resolvedTenant, huntId).set(
      {
        'enabled': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> setPlacerUids(String huntId, List<String> placerUids) async {
    await GameFirestorePaths.nfcHunt(_firestore, _resolvedTenant, huntId).set(
      {
        'placerUids': placerUids,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<List<NfcHuntTag>> listTags(String huntId) async {
    final snap = await GameFirestorePaths.nfcHuntTags(
      _firestore,
      _resolvedTenant,
      huntId,
    ).get();
    return snap.docs
        .map((d) => NfcHuntTag.fromMap(d.id, d.data()))
        .toList(growable: false);
  }

  /// Registers or updates a tag via the `registerNfcHuntTag` callable.
  Future<String> registerTag({
    required String huntId,
    required String tagUid,
    required NfcHuntPlacement placement,
    String? label,
    ActivityEventLocation? location,
  }) async {
    final tenant = _resolvedTenant;
    final callable = _functions.httpsCallable('registerNfcHuntTag');
    final body = <String, dynamic>{
      'gameId': tenant.tenantKey,
      'huntId': huntId,
      'tagUid': tagUid,
      'placement':
          placement == NfcHuntPlacement.fixed ? 'fixed' : 'floating',
      if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
      if (placement == NfcHuntPlacement.fixed && location != null)
        'location': location.toMap(),
    };
    final result = await callable.call<Map<String, dynamic>>(body);
    final returned = result.data['tagUid'];
    if (returned is String && returned.isNotEmpty) return returned;
    return tagUid;
  }
}
