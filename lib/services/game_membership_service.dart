import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/game_role.dart';
import '../models/game_tenant_ref.dart';
import '../utils/game_firestore_paths.dart';
import 'game_context_service.dart';

/// Bidirectional game membership:
/// - `games/{instanceId}/events/{eventSlug}/members/{userId}`
/// - `users/{userId}/gameMemberships/{tenantKey}`
class GameMembershipService {
  GameMembershipService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String? get _uid => _auth.currentUser?.uid;

  Map<String, dynamic> _membershipPayload(GameTenantRef tenant) => {
        'role': GameRole.player.wireName,
        'joinedAt': FieldValue.serverTimestamp(),
        'tenantKey': tenant.tenantKey,
        'instanceId': tenant.instanceId,
        'eventSlug': tenant.eventSlug,
      };

  /// Ensures the signed-in user is a [GameRole.player] member of the current tenant.
  Future<void> ensureMembershipForCurrentGame() async {
    final uid = _uid;
    final tenant = GameContextService.instance.currentTenant;
    if (uid == null || tenant == null) return;

    final memberRef = GameFirestorePaths.member(_firestore, tenant, uid);
    final userMembershipRef =
        GameFirestorePaths.userMembership(_firestore, uid, tenant);

    if ((await memberRef.get()).exists) return;

    final membership = _membershipPayload(tenant);
    final now = FieldValue.serverTimestamp();

    final instanceRef = GameFirestorePaths.instanceDoc(_firestore, tenant);
    final eventRef = GameFirestorePaths.eventDoc(_firestore, tenant);

    if (!(await instanceRef.get()).exists) {
      try {
        await instanceRef.set({
          'instanceId': tenant.instanceId,
          'larpManagerBaseUrl': 'https://${tenant.instanceId}',
          'createdAt': now,
          'updatedAt': now,
        });
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
      }
    }

    if (!(await eventRef.get()).exists) {
      try {
        await eventRef.set({
          'tenantKey': tenant.tenantKey,
          'instanceId': tenant.instanceId,
          'eventSlug': tenant.eventSlug,
          'displayName': tenant.eventSlug.replaceAll('_', ' '),
          'createdAt': now,
          'updatedAt': now,
        });
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
      }
    }

    await memberRef.set(membership);
    await userMembershipRef.set(membership);
  }

  Future<String?> getGameDisplayName(String tenantKey) async {
    final tenant = GameTenantRef.tryParseTenantKey(tenantKey);
    if (tenant == null) return null;
    final doc = await GameFirestorePaths.eventDoc(_firestore, tenant).get();
    return doc.data()?['displayName'] as String?;
  }

  Future<GameRole> getRoleInGame([String? tenantKey]) async {
    final uid = _uid;
    if (uid == null) return GameRole.player;

    final key = tenantKey ?? GameContextService.instance.currentTenantKey;
    final tenant = GameTenantRef.tryParseTenantKey(key);
    if (tenant == null) return GameRole.player;

    final snap = await GameFirestorePaths.member(_firestore, tenant, uid).get();
    if (!snap.exists) return GameRole.player;
    return gameRoleFromWire(snap.data()?['role'] as String?);
  }

  Future<void> joinLarpManagerInstance({
    required GameTenantRef tenant,
    required String baseUrl,
    required String eventSlug,
  }) async {
    final uid = _uid;
    if (uid == null) return;

    final memberRef = GameFirestorePaths.member(_firestore, tenant, uid);
    final userMembershipRef =
        GameFirestorePaths.userMembership(_firestore, uid, tenant);

    final now = FieldValue.serverTimestamp();
    final membership = _membershipPayload(tenant);

    final displayName =
        eventSlug.isNotEmpty ? eventSlug.replaceAll('_', ' ') : tenant.instanceId;

    final instanceRef = GameFirestorePaths.instanceDoc(_firestore, tenant);
    final eventRef = GameFirestorePaths.eventDoc(_firestore, tenant);

    try {
      await instanceRef.set(
        {
          'instanceId': tenant.instanceId,
          'larpManagerBaseUrl': baseUrl,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }

    try {
      await eventRef.set(
        {
          'tenantKey': tenant.tenantKey,
          'instanceId': tenant.instanceId,
          'eventSlug': eventSlug,
          'displayName': displayName,
          'larpManagerBaseUrl': baseUrl,
          'larpManagerEventSlug': eventSlug,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }

    if ((await memberRef.get()).exists) return;

    await memberRef.set({
      ...membership,
      'createdAt': now,
    });
    await userMembershipRef.set({
      ...membership,
      'createdAt': now,
    });
  }

  Future<void> addUserToGame({
    required GameTenantRef tenant,
    required String userId,
    required GameRole role,
  }) async {
    final memberRef = GameFirestorePaths.member(_firestore, tenant, userId);
    final userMembershipRef =
        GameFirestorePaths.userMembership(_firestore, userId, tenant);

    final data = {
      'role': role.wireName,
      'joinedAt': FieldValue.serverTimestamp(),
      'tenantKey': tenant.tenantKey,
      'instanceId': tenant.instanceId,
      'eventSlug': tenant.eventSlug,
    };

    final batch = _firestore.batch();
    batch.set(memberRef, data, SetOptions(merge: true));
    batch.set(userMembershipRef, data, SetOptions(merge: true));
    await batch.commit();
  }
}
