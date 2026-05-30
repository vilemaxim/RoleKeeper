import 'package:cloud_firestore/cloud_firestore.dart';

import 'character.dart';
import 'death_rules.dart';
import '../services/death_timer_service.dart';

/// Death timer status stored in Firestore: characters/{characterId}/status/deathTimer.
/// Persists across browser refresh.
class CharacterDeathTimerStatus {
  const CharacterDeathTimerStatus({
    required this.characterId,
    required this.ownerId,
    required this.character,
    required this.activityEventId,
    required this.startedAt,
    required this.phase,
    required this.totalSeconds,
    required this.interventionCountSeconds,
    this.interventionRoleName = 'medic',
    this.afterDeathTimerText = '',
    this.interventionStartedAt,
    this.helpingPlayerId,
  });

  final String characterId;
  final String ownerId;
  final Character character;
  final String activityEventId;
  final DateTime startedAt;
  final String phase;
  final int totalSeconds;
  final int interventionCountSeconds;
  final String interventionRoleName;
  final String afterDeathTimerText;
  final DateTime? interventionStartedAt;
  final String? helpingPlayerId;

  static CharacterDeathTimerStatus? fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return null;
    final characterId = doc.reference.parent.parent?.id;
    if (characterId == null) return null;
    final startedAt = data['startedAt'];
    final interventionStartedAt = data['interventionStartedAt'];
    return CharacterDeathTimerStatus(
      characterId: characterId,
      ownerId: data['ownerId'] as String? ?? '',
      character: Character(
        id: characterId,
        shortId: data['characterShortId'] as String? ?? '000',
        ownerId: data['ownerId'] as String? ?? '',
        name: data['characterName'] as String? ?? '',
      ),
      activityEventId: data['activityEventId'] as String? ?? '',
      startedAt: startedAt is Timestamp
          ? startedAt.toDate()
          : (startedAt is DateTime ? startedAt : DateTime.now()),
      phase: data['phase'] as String? ?? 'deathCount',
      totalSeconds: data['totalSeconds'] as int? ?? 120,
      interventionCountSeconds: data['interventionCountSeconds'] as int? ?? 60,
      interventionRoleName: data['interventionRoleName'] as String? ?? 'medic',
      interventionStartedAt: interventionStartedAt is Timestamp
          ? interventionStartedAt.toDate()
          : (interventionStartedAt is DateTime ? interventionStartedAt : null),
      helpingPlayerId: data['helpingPlayerId'] as String?,
      afterDeathTimerText: data['afterDeathTimerText'] as String? ?? '',
    );
  }

  ActiveDeathTimer toActiveDeathTimer() {
    final rules = DeathRules(
      enabled: true,
      countSeconds: 0,
      stages: [
        DeathStage(
          id: '1',
          label: 'Dying',
          countSeconds: totalSeconds,
          playerDescription: 'Countdown in progress',
        ),
      ],
      interventionEnabled: true,
      interventionCountSeconds: interventionCountSeconds,
      interventionRoleName: interventionRoleName,
      afterDeathTimerText: afterDeathTimerText,
    );
    return ActiveDeathTimer(
      character: character,
      rules: rules,
      activityEventId: activityEventId,
      deathCountStartedAt: startedAt,
      phase: _phaseFromString(phase),
      interventionStartedAt: interventionStartedAt,
      helpingPlayerId: helpingPlayerId,
      pendingDeathExpiredLog: false,
    );
  }

  static DeathTimerPhase _phaseFromString(String s) {
    switch (s) {
      case 'intervention':
        return DeathTimerPhase.intervention;
      case 'awaitingMedicScan':
        return DeathTimerPhase.awaitingMedicScan;
      case 'healed':
        return DeathTimerPhase.healed;
      case 'dead':
        return DeathTimerPhase.dead;
      default:
        return DeathTimerPhase.deathCount;
    }
  }

  Map<String, dynamic> toMap() => {
        'characterId': characterId,
        'ownerId': ownerId,
        'characterShortId': character.shortId,
        'characterName': character.name,
        'activityEventId': activityEventId,
        'startedAt': Timestamp.fromDate(startedAt),
        'phase': phase,
        'totalSeconds': totalSeconds,
        'interventionCountSeconds': interventionCountSeconds,
        'interventionRoleName': interventionRoleName,
        'afterDeathTimerText': afterDeathTimerText,
        if (interventionStartedAt != null)
          'interventionStartedAt': Timestamp.fromDate(interventionStartedAt!),
        if (helpingPlayerId != null) 'helpingPlayerId': helpingPlayerId,
      };
}
