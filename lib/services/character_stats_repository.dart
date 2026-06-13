import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/character_stats.dart';
import '../models/game_tenant_ref.dart';
import '../utils/game_firestore_paths.dart';
import 'game_context_service.dart';

/// Reads the per-character LarpManager mirror written by
/// `runLarpManagerSync` in `functions/src/larpmanager/sync.ts`. The mirror
/// path (`games/{instanceId}/events/{eventSlug}/larpManagerMirrorChars/{uuid}`)
/// is already game-member readable per `firestore.rules:222-225`.
class CharacterStatsRepository {
  CharacterStatsRepository({
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

  /// Streams [CharacterStats] for the LM-synced character with the given
  /// [characterUuid]. Emits `null` when the mirror doc does not exist.
  ///
  /// Tolerates malformed payloads — see [CharacterStats.fromMirrorDoc].
  Stream<CharacterStats?> watchStats({required String characterUuid}) {
    final doc = GameFirestorePaths.larpManagerMirrorChars(
      _firestore,
      _resolvedTenant,
    ).doc(characterUuid);

    return doc.snapshots().map((snap) {
      if (!snap.exists) return null;
      return CharacterStats.fromMirrorDoc(snap);
    });
  }
}
