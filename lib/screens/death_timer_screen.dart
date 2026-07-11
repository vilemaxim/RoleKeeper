import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/character.dart';
import '../models/death_rules.dart';
import '../services/activity_events_service.dart';
import '../services/character_status_service.dart';
import '../services/death_intervention_claims_service.dart';
import '../services/death_intervention_secrets_service.dart';
import '../services/death_timer_service.dart';
import '../services/rules_repository.dart';
import '../utils/death_qr_parser.dart';
import 'death_offline_intervention_screen.dart';

String _capitalize(String s) {
  if (s.isEmpty) return s;
  return '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';
}

/// Death timer page: countdown, stages, QR code for intervener (medic/healer).
/// Timer runs in background; state persists when navigating away.
class DeathTimerScreen extends StatefulWidget {
  const DeathTimerScreen({super.key, required this.character});

  final Character character;

  @override
  State<DeathTimerScreen> createState() => _DeathTimerScreenState();
}

class _DeathTimerScreenState extends State<DeathTimerScreen> {
  final _rulesRepo = RulesRepository();
  final _eventsService = ActivityEventsService();
  final _claimsService = DeathInterventionClaimsService();
  final _statusService = CharacterStatusService();
  final _timerService = DeathTimerService.instance;
  final _secretsService = DeathInterventionSecretsService();

  bool _initialized = false;
  String? _qrSigningSecret;

  @override
  void initState() {
    super.initState();
    _timerService.addListener(_onTimerUpdate);
    _init();
  }

  Future<void> _init() async {
    var rules = await _rulesRepo.getDeathRules();
    if (!mounted) return;
    try {
      final secrets = await _secretsService.resolveSecrets();
      _qrSigningSecret = secrets?.qrSigningSecret;
    } catch (_) {
      // QR signing unavailable offline until secrets were cached earlier.
    }
    if (!mounted) return;
    if (!rules.enabled) {
      rules = DeathRules(
        enabled: true,
        countSeconds: 120,
        stages: [
          DeathStage(id: '1', label: 'Dying', countSeconds: 120, playerDescription: 'You are fading...'),
          DeathStage(id: '2', label: 'Critical', countSeconds: 60, playerDescription: 'Almost gone...'),
        ],
        interventionEnabled: true,
        interventionCountSeconds: 60,
        afterDeathTimerText: rules.afterDeathTimerText,
      );
    }

    final existing = _timerService.active;
    if (existing != null) {
      if (mounted) setState(() => _initialized = true);
      return;
    }

    String? activityEventId;
    try {
      activityEventId = await _eventsService.recordDeathCountStarted(
        characterId: widget.character.id.isNotEmpty ? widget.character.id : null,
      );
    } catch (_) {
      // Offline - will sync when back
    }

    if (!mounted) return;

    final now = DateTime.now();
    _timerService.setActive(ActiveDeathTimer(
      character: widget.character,
      rules: rules,
      activityEventId: activityEventId ?? '',
      deathCountStartedAt: now,
    ));
    if (widget.character.id.isNotEmpty) {
      await _statusService.setDeathTimer(
        character: widget.character,
        rules: rules,
        activityEventId: activityEventId ?? '',
        startedAt: now,
      );
    }
    if (!mounted) return;
    setState(() => _initialized = true);
  }

  void _onMedicScannedFromQR(String medicPlayerId) {
    final t = _timerService.active;
    if (t == null) return;
    final fallenId = FirebaseAuth.instance.currentUser?.uid;
    if (fallenId == null) return;
    _timerService.setPhaseIntervention(medicPlayerId);
    try {
      _eventsService.recordDeathTimeStopped(
        injuredPlayerId: fallenId,
        medicPlayerId: medicPlayerId,
        activityEventId: t.activityEventId,
        injuredCharacterId: t.character.id.isNotEmpty ? t.character.id : null,
        fallenShortId: t.character.shortId,
      );
    } catch (_) {}
    if (t.character.id.isNotEmpty) {
      _statusService.updateDeathTimerPhase(
        characterId: t.character.id,
        phase: DeathTimerPhase.intervention,
        interventionStartedAt: DateTime.now(),
        helpingPlayerId: medicPlayerId,
      );
    }
  }

  void _recordInterventionComplete() async {
    final t = _timerService.active;
    if (t?.helpingPlayerId != null) {
      try {
        _eventsService.recordDeathInterventionComplete(
          helpingPlayerId: t!.helpingPlayerId,
          injuredCharacterId: t.character.id.isNotEmpty ? t.character.id : null,
          offline: false,
        );
      } catch (_) {}
    }
    if (t?.character.id != null && t!.character.id.isNotEmpty) {
      await _statusService.clearDeathTimer(t.character.id);
    }
    _timerService.setPhaseHealed();
    _timerService.clear();
  }

  void _openOfflineIntervention() {
    final t = _timerService.active;
    if (t == null) return;
    final playerId = FirebaseAuth.instance.currentUser?.uid ?? '';
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => DeathOfflineInterventionScreen(
          fallenPlayerShortId: t.character.shortId,
          fallenPlayerId: playerId,
          rules: t.rules,
          activityEventId: t.activityEventId,
        ),
      ),
    );
  }

  Future<bool> _onWillPop() async {
    final t = _timerService.active;
    if (t == null) return true;
    if (t.phase == DeathTimerPhase.healed || t.phase == DeathTimerPhase.dead) {
      return true;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave death timer?'),
        content: const Text(
          'You are still dying. If you leave, no one will be able to scan the QR code to help you. The countdown will keep running in the background.\n\nAre you sure you want to leave?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  void dispose() {
    _timerService.removeListener(_onTimerUpdate);
    super.dispose();
  }

  void _onTimerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = _timerService.active;
    if (!_initialized || t == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final remaining = _timerService.getRemainingSeconds();

    final user = FirebaseAuth.instance.currentUser;
    final playerId = user?.uid ?? 'unknown';
    final shortId = t.character.shortId;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final allow = await _onWillPop();
        if (allow && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: StreamBuilder<DeathInterventionClaim?>(
        stream: _claimsService.watchClaim(t.activityEventId),
        builder: (context, claimSnap) {
          final claim = claimSnap.data;
          if (claim != null && t.phase == DeathTimerPhase.deathCount) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _onMedicScannedFromQR(claim.medicPlayerId);
            });
          }
          if (claim != null &&
              claim.revivalConfirmedAt != null &&
              t.phase == DeathTimerPhase.awaitingMedicScan) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _recordInterventionComplete();
            });
          }
          return _buildBody(context, t, shortId, playerId, remaining);
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ActiveDeathTimer t,
    String shortId,
    String playerId,
    int remainingSeconds,
  ) {
    final phase = t.phase;
    final displayRemaining = remainingSeconds.clamp(0, 999);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          phase == DeathTimerPhase.deathCount ? 'Death Timer' : 'Revival',
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${displayRemaining ~/ 60}:${(displayRemaining % 60).toString().padLeft(2, '0')}',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: displayRemaining <= 60 ? Colors.red : null,
                    ),
                textAlign: TextAlign.center,
              ),
              Text(
                'Total: ${t.rules.totalSeconds}s',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (t.rules.stages.isNotEmpty) ...[
                ...t.rules.stages.asMap().entries.map((e) {
                  final idx = e.key;
                  final stage = e.value;
                  final isCurrent = phase == DeathTimerPhase.deathCount &&
                      _timerService.getCurrentStageIndex() == idx;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      color: isCurrent
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      child: ListTile(
                        leading: Icon(
                          isCurrent ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: isCurrent
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Text(stage.label),
                        subtitle: Text(stage.playerDescription),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 24),
              ],
              if (phase == DeathTimerPhase.deathCount && t.rules.interventionEnabled) ...[
                const Spacer(),
                Text(
                  '${_capitalize(t.rules.interventionRoleName)} can scan to stop the count:',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                if (_qrSigningSecret != null)
                  QrImageView(
                    data: buildDeathMedicQrPayload(
                      shortId: shortId,
                      fallenPlayerId: playerId,
                      activityEventId: t.activityEventId,
                      signingSecret: _qrSigningSecret!,
                    ),
                    version: QrVersions.auto,
                    size: 200,
                  )
                else
                  Text(
                    'Connect online once to enable medic QR codes for this event.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _openOfflineIntervention,
                  child: const Text('Offline intervention'),
                ),
                if (kDebugMode)
                  TextButton(
                    onPressed: () => _onMedicScannedFromQR('test-medic-id'),
                    child: Text('[Debug] Simulate ${t.rules.interventionRoleName} scan'),
                  ),
              ],
              if (phase == DeathTimerPhase.intervention) ...[
                const Spacer(),
                Text(
                  '${_capitalize(t.rules.interventionRoleName)} attending. Revival in progress...',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ],
              if (phase == DeathTimerPhase.awaitingMedicScan) ...[
                const Spacer(),
                Text(
                  'Revival complete. ${_capitalize(t.rules.interventionRoleName)}: scan this QR to confirm you stayed near.',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (_qrSigningSecret != null)
                  QrImageView(
                    data: buildDeathRevivalConfirmQrPayload(
                      shortId: shortId,
                      fallenPlayerId: playerId,
                      activityEventId: t.activityEventId,
                      signingSecret: _qrSigningSecret!,
                    ),
                    version: QrVersions.auto,
                    size: 200,
                  )
                else
                  Text(
                    'Connect online once to enable revival confirmation QR.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _recordInterventionComplete,
                  child: Text('${_capitalize(t.rules.interventionRoleName)} has scanned - I\'m revived'),
                ),
                if (kDebugMode)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextButton(
                      onPressed: _recordInterventionComplete,
                      child: Text('[Debug] Skip ${t.rules.interventionRoleName} confirmation'),
                    ),
                  ),
              ],
              if (phase == DeathTimerPhase.healed)
                Text(
                  'Character revived!',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.green,
                      ),
                  textAlign: TextAlign.center,
                ),
              if (phase == DeathTimerPhase.dead)
                Text(
                  t.rules.afterDeathTimerText.trim().isNotEmpty
                      ? t.rules.afterDeathTimerText.trim()
                      : 'Character died.',
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
