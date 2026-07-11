import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/game_tenant_ref.dart';
import '../models/larp_registry_entry.dart';
import '../utils/game_firestore_paths.dart';

/// Global LARP catalog: `larpRegistry/{instanceId}/events/{eventSlug}`.
class LarpRegistryRepository {
  LarpRegistryRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String? get _uid => _auth.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> _ref(GameTenantRef tenant) =>
      GameFirestorePaths.larpRegistryEvent(_firestore, tenant);

  Future<LarpRegistryEntry?> get(GameTenantRef tenant) async {
    final snap = await _ref(tenant).get();
    if (!snap.exists) return null;
    return LarpRegistryEntry.fromMap(tenant, snap.data());
  }

  /// Writes client-safe registry metadata only. `organizerAccessConfigured` is
  /// set server-side by `saveLarpManagerIntegrationConfig` after LM verification.
  Future<void> markOrganizerAccessConfigured({
    required GameTenantRef tenant,
    required String larpManagerBaseUrl,
    required String larpManagerEventSlug,
    required String displayName,
  }) async {
    final uid = _uid;
    if (uid == null) return;

    final now = FieldValue.serverTimestamp();
    final ref = _ref(tenant);
    final snap = await ref.get();
    final payload = {
      'tenantKey': tenant.tenantKey,
      'instanceId': tenant.instanceId,
      'eventSlug': tenant.eventSlug,
      'larpManagerBaseUrl': larpManagerBaseUrl,
      'larpManagerEventSlug': larpManagerEventSlug,
      'displayName': displayName,
      'updatedAt': now,
    };
    if (!snap.exists) {
      await ref.set({
        ...payload,
        'createdByUid': uid,
        'createdAt': now,
      });
    } else {
      await ref.set(payload, SetOptions(merge: true));
    }
  }
}
