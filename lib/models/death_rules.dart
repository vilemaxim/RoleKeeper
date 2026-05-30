/// Death rules configuration - universal for all players.
class DeathRules {
  const DeathRules({
    required this.enabled,
    required this.countSeconds,
    required this.stages,
    required this.interventionEnabled,
    this.interventionCountSeconds = 0,
    this.interventionRoleName = 'medic',
    this.afterDeathTimerText = '',
  });

  final bool enabled;
  final int countSeconds;
  final List<DeathStage> stages;
  final bool interventionEnabled;
  final int interventionCountSeconds;
  /// Name for the character type that can intervene (e.g. medic, healer).
  final String interventionRoleName;
  /// Shown when the death count reaches zero (empty = use built-in default).
  final String afterDeathTimerText;

  int get totalSeconds {
    var total = countSeconds;
    for (final s in stages) {
      total += s.countSeconds;
    }
    return total;
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'countSeconds': countSeconds,
        'stages': stages.map((s) => s.toMap()).toList(),
        'interventionEnabled': interventionEnabled,
        'interventionCountSeconds': interventionCountSeconds,
        'interventionRoleName': interventionRoleName,
        'afterDeathTimerText': afterDeathTimerText,
      };

  static DeathRules fromMap(Map<String, dynamic>? m) {
    if (m == null) return DeathRules.defaultRules;
    final stagesList = m['stages'] as List<dynamic>?;
    return DeathRules(
      enabled: m['enabled'] as bool? ?? false,
      countSeconds: (m['countSeconds'] as num?)?.toInt() ?? 300,
      stages: stagesList
              ?.map((s) => DeathStage.fromMap(s as Map<String, dynamic>))
              .toList() ??
          [],
      interventionEnabled: m['interventionEnabled'] as bool? ?? false,
      interventionCountSeconds:
          (m['interventionCountSeconds'] as num?)?.toInt() ?? 60,
      interventionRoleName:
          m['interventionRoleName'] as String? ?? 'medic',
      afterDeathTimerText: m['afterDeathTimerText'] as String? ?? '',
    );
  }

  static const defaultRules = DeathRules(
    enabled: false,
    countSeconds: 300,
    stages: [],
    interventionEnabled: false,
    interventionCountSeconds: 60,
    interventionRoleName: 'medic',
    afterDeathTimerText: '',
  );

  /// Body for the death dialog when the count hits zero (custom or default).
  String get deathExpiredDialogBody {
    final t = afterDeathTimerText.trim();
    if (t.isNotEmpty) return t;
    return 'The count has reached zero. Your character has died.';
  }

  /// Message when the timer expired while the player was away (login check).
  String deathExpiredWhileAwayBody(String characterName) =>
      DeathRules.deathExpiredWhileAwayFromStrings(characterName, afterDeathTimerText);

  /// Same logic as [deathExpiredWhileAwayBody] when you only have stored text + name.
  static String deathExpiredWhileAwayFromStrings(
    String characterName,
    String afterDeathTimerText,
  ) {
    final t = afterDeathTimerText.trim();
    if (t.isNotEmpty) return t;
    final name = characterName.trim();
    if (name.isEmpty) {
      return 'Your character has died. The death count reached zero while you were away.';
    }
    return '$name has died. The death count reached zero while you were away.';
  }
}

class DeathStage {
  const DeathStage({
    required this.id,
    required this.label,
    required this.countSeconds,
    required this.playerDescription,
  });

  final String id;
  final String label;
  final int countSeconds;
  final String playerDescription;

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'countSeconds': countSeconds,
        'playerDescription': playerDescription,
      };

  static DeathStage fromMap(Map<String, dynamic> m) => DeathStage(
        id: m['id'] as String? ?? '',
        label: m['label'] as String? ?? '',
        countSeconds: (m['countSeconds'] as num?)?.toInt() ?? 60,
        playerDescription: m['playerDescription'] as String? ?? '',
      );
}
