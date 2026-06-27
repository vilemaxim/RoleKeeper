import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/game_tenant_ref.dart';
import '../models/member_presence.dart';
import '../utils/game_firestore_paths.dart';
import 'game_context_service.dart';

/// Reads and updates presence fields on the signed-in user's member document.
class MemberPresenceRepository {
  MemberPresenceRepository({
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

  String? get _uid => _auth.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> _memberRef(String uid) =>
      GameFirestorePaths.member(_firestore, _resolvedTenant, uid);

  Future<MemberPresence> getPresence() async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');

    final snap = await _memberRef(uid).get();
    return MemberPresence.fromMemberMap(snap.data());
  }

  Future<void> setLocationOptIn(bool optedIn) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');

    await _memberRef(uid).set(
      {
        'locationOptIn': optedIn,
        'presenceUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> setPresenceState(PresenceState state) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');

    await _memberRef(uid).set(
      {
        'presenceState': state.wireName,
        'presenceUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
