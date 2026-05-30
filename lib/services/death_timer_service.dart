import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/character.dart';
import '../models/death_rules.dart';

/// Holds an active death timer state. Timer runs in real time; we compute
/// remaining seconds from start times when resuming.
class ActiveDeathTimer {
  ActiveDeathTimer({
    required this.character,
    required this.rules,
    required this.activityEventId,
    required this.deathCountStartedAt,
    this.phase = DeathTimerPhase.deathCount,
    this.interventionStartedAt,
    this.helpingPlayerId,
    this.pendingDeathExpiredLog = false,
  });

  final Character character;
  final DeathRules rules;
  final String activityEventId;
  final DateTime deathCountStartedAt;
  DeathTimerPhase phase;
  DateTime? interventionStartedAt;
  String? helpingPlayerId;

  /// Set when [DeathTimerService.tick] transitions from death count to [DeathTimerPhase.dead].
  /// Cleared after a death-expired event is logged so restores with `phase == dead` do not duplicate.
  bool pendingDeathExpiredLog;

  static const deathCount = DeathTimerPhase.deathCount;
  static const intervention = DeathTimerPhase.intervention;
  static const awaitingMedicScan = DeathTimerPhase.awaitingMedicScan;
  static const healed = DeathTimerPhase.healed;
  static const dead = DeathTimerPhase.dead;
}

enum DeathTimerPhase { deathCount, intervention, awaitingMedicScan, healed, dead }

/// Singleton holding active death timer. Survives navigation.
class DeathTimerService extends ChangeNotifier {
  DeathTimerService._();
  static final DeathTimerService instance = DeathTimerService._();

  /// Tests only: supply a fixed clock for time-based behavior.
  @visibleForTesting
  static DateTime Function()? testClock;

  static DateTime _now() => testClock?.call() ?? DateTime.now();

  ActiveDeathTimer? _active;
  Timer? _ticker;

  ActiveDeathTimer? get active => _active;

  bool get hasActive =>
      _active != null &&
      _active!.phase != DeathTimerPhase.healed &&
      _active!.phase != DeathTimerPhase.dead;

  void setActive(ActiveDeathTimer? timer) {
    _ticker?.cancel();
    _active = timer;
    if (timer != null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        tick();
        // Stop ticking once the death count has finished — otherwise listeners
        // (e.g. DeathTimerScreen) rebuild every second behind the death dialog.
        if (_active?.phase == DeathTimerPhase.dead) {
          _ticker?.cancel();
          _ticker = null;
        }
        notifyListeners();
      });
    }
    notifyListeners();
  }

  void clear() {
    _ticker?.cancel();
    _ticker = null;
    _active = null;
    notifyListeners();
  }

  /// Returns remaining seconds for current phase. Negative if time has elapsed.
  int getRemainingSeconds() {
    final t = _active;
    if (t == null) return 0;
    final now = _now();
    if (t.phase == DeathTimerPhase.deathCount) {
      final elapsed = now.difference(t.deathCountStartedAt).inSeconds;
      return t.rules.totalSeconds - elapsed;
    }
    if (t.phase == DeathTimerPhase.intervention) {
      final start = t.interventionStartedAt ?? t.deathCountStartedAt;
      final elapsed = now.difference(start).inSeconds;
      return t.rules.interventionCountSeconds - elapsed;
    }
    return 0;
  }

  /// Applies elapsed time; returns true if phase changed.
  bool tick() {
    final t = _active;
    if (t == null) return false;
    final remaining = getRemainingSeconds();
    if (remaining > 0) return false;
    if (t.phase == DeathTimerPhase.deathCount) {
      t.phase = DeathTimerPhase.dead;
      t.pendingDeathExpiredLog = true;
      return true;
    }
    if (t.phase == DeathTimerPhase.intervention) {
      t.phase = DeathTimerPhase.awaitingMedicScan;
      return true;
    }
    return false;
  }

  /// Current stage index for death count phase.
  int getCurrentStageIndex() {
    final t = _active;
    if (t == null || t.phase != DeathTimerPhase.deathCount) return -1;
    final elapsed = _now().difference(t.deathCountStartedAt).inSeconds;
    var cum = 0;
    for (var i = 0; i < t.rules.stages.length; i++) {
      cum += t.rules.stages[i].countSeconds;
      if (elapsed < cum) return i;
    }
    return -1;
  }

  void setPhaseIntervention(String medicPlayerId) {
    final t = _active;
    if (t == null) return;
    t.phase = DeathTimerPhase.intervention;
    t.helpingPlayerId = medicPlayerId;
    t.interventionStartedAt = _now();
    notifyListeners();
  }

  void setPhaseHealed() {
    final t = _active;
    if (t == null) return;
    t.phase = DeathTimerPhase.healed;
    notifyListeners();
  }

  /// Expose phase for UI.
  DeathTimerPhase get phase => _active?.phase ?? DeathTimerPhase.healed;
}
