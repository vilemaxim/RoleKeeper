import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/character.dart';
import '../models/character_death_timer_status.dart';
import '../models/death_rules.dart';
import '../models/game_tenant_ref.dart';
import '../utils/game_firestore_paths.dart';
import 'death_timer_service.dart';
import 'game_context_service.dart';

/// Result of death timer check on login.
sealed class DeathTimerCheckResult {
  const DeathTimerCheckResult();
  factory DeathTimerCheckResult.none() => DeathTimerCheckNone();
  factory DeathTimerCheckResult.active(CharacterDeathTimerStatus s) =>
      DeathTimerCheckActive(s);
  factory DeathTimerCheckResult.justDied(
    Character c, {
    String afterDeathTimerText = '',
    String activityEventId = '',
  }) =>
      DeathTimerCheckJustDied(
        c,
        afterDeathTimerText: afterDeathTimerText,
        activityEventId: activityEventId,
      );
}

final class DeathTimerCheckNone extends DeathTimerCheckResult {}

final class DeathTimerCheckActive extends DeathTimerCheckResult {
  DeathTimerCheckActive(this.status);
  final CharacterDeathTimerStatus status;
}

final class DeathTimerCheckJustDied extends DeathTimerCheckResult {
  DeathTimerCheckJustDied(
    this.character, {
    this.afterDeathTimerText = '',
    this.activityEventId = '',
  });
  final Character character;
  final String afterDeathTimerText;
  /// Original death-timer start event id (for `deathTimerExpired` chain).
  final String activityEventId;
}

/// Manages character status under `games/.../events/.../characters/{id}/status`.
class CharacterStatusService {
  CharacterStatusService({
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

  static const _deathTimerDocId = 'deathTimer';
  static const _statsCollection = 'stats';

  /// Written to `characters/{id}/stats/{autoId}` when a death counter starts.
  static const statsDocTypeDeathCounterStarted = 'deathCounterStarted';

  String? get _userId => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> get _charactersCol =>
      GameFirestorePaths.characters(_firestore, _resolvedTenant);

  /// Starts death timer status for a character.
  Future<void> setDeathTimer({
    required Character character,
    required DeathRules rules,
    required String activityEventId,
    required DateTime startedAt,
    DeathTimerPhase phase = DeathTimerPhase.deathCount,
    DateTime? interventionStartedAt,
    String? helpingPlayerId,
  }) async {
    final uid = _userId;
    if (uid == null || character.ownerId != uid) return;

    final ref = _charactersCol
        .doc(character.id)
        .collection('status')
        .doc(_deathTimerDocId);

    await ref.set({
      'characterId': character.id,
      'ownerId': uid,
      'characterShortId': character.shortId,
      'characterName': character.name,
      'activityEventId': activityEventId,
      'startedAt': Timestamp.fromDate(startedAt),
      'phase': _phaseToString(phase),
      'totalSeconds': rules.totalSeconds,
      'interventionCountSeconds': rules.interventionCountSeconds,
      'interventionRoleName': rules.interventionRoleName,
      'afterDeathTimerText': rules.afterDeathTimerText,
      if (interventionStartedAt case final d?)
        'interventionStartedAt': Timestamp.fromDate(d),
      'helpingPlayerId': ?helpingPlayerId,
    });

    await _charactersCol.doc(character.id).collection(_statsCollection).add({
      'type': statsDocTypeDeathCounterStarted,
      'startedAt': Timestamp.fromDate(startedAt),
      'activityEventId': activityEventId,
      'phase': _phaseToString(phase),
    });
  }

  /// Updates death timer phase (e.g. when medic intervenes).
  Future<void> updateDeathTimerPhase({
    required String characterId,
    required DeathTimerPhase phase,
    DateTime? interventionStartedAt,
    String? helpingPlayerId,
  }) async {
    final uid = _userId;
    if (uid == null) return;

    final ref = _charactersCol
        .doc(characterId)
        .collection('status')
        .doc(_deathTimerDocId);

    final updates = <String, dynamic>{
      'phase': _phaseToString(phase),
    };
    if (interventionStartedAt != null) {
      updates['interventionStartedAt'] =
          Timestamp.fromDate(interventionStartedAt);
    }
    if (helpingPlayerId != null) {
      updates['helpingPlayerId'] = helpingPlayerId;
    }
    await ref.update(updates);
  }

  /// Removes death timer status (healed or dead).
  Future<void> clearDeathTimer(String characterId) async {
    final uid = _userId;
    if (uid == null) return;

    await _charactersCol
        .doc(characterId)
        .collection('status')
        .doc(_deathTimerDocId)
        .delete();
  }

  /// Result of checking for an active death timer on login.
  /// - active: timer is running, restore it
  /// - justDied: timer expired while away, character died
  /// - none: no active timer
  Future<DeathTimerCheckResult> checkDeathTimerOnLogin() async {
    final uid = _userId;
    if (uid == null) return DeathTimerCheckResult.none();

    final charsSnap = await _charactersCol
        .where('ownerId', isEqualTo: uid)
        .where('isArchived', isEqualTo: false)
        .get();

    for (final charDoc in charsSnap.docs) {
      final statusSnap = await charDoc.reference
          .collection('status')
          .doc(_deathTimerDocId)
          .get();

      if (!statusSnap.exists) continue;

      final status = CharacterDeathTimerStatus.fromFirestore(statusSnap);
      if (status == null) continue;

      if (status.phase == 'healed' || status.phase == 'dead') continue;

      final now = DateTime.now();
      final expired = _isExpired(status, now);
      if (expired) {
        await clearDeathTimer(status.characterId);
        return DeathTimerCheckResult.justDied(
          status.character,
          afterDeathTimerText: status.afterDeathTimerText,
          activityEventId: status.activityEventId,
        );
      }
      return DeathTimerCheckResult.active(status);
    }
    return DeathTimerCheckResult.none();
  }

  bool _isExpired(CharacterDeathTimerStatus status, DateTime now) {
    // Only deathCount phase can expire to dead. Intervention/awaitingMedicScan
    // transition to awaitingMedicScan, not death.
    if (status.phase != 'deathCount') return false;
    final end = status.startedAt.add(Duration(seconds: status.totalSeconds));
    return now.isAfter(end) || now.isAtSameMomentAs(end);
  }

  static String _phaseToString(DeathTimerPhase p) {
    switch (p) {
      case DeathTimerPhase.intervention:
        return 'intervention';
      case DeathTimerPhase.awaitingMedicScan:
        return 'awaitingMedicScan';
      case DeathTimerPhase.healed:
        return 'healed';
      case DeathTimerPhase.dead:
        return 'dead';
      default:
        return 'deathCount';
    }
  }
}
