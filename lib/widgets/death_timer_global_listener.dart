import 'dart:async';

import 'package:flutter/material.dart';

import '../auth_gate.dart';
import '../services/activity_events_service.dart';
import '../services/character_status_service.dart';
import '../services/death_timer_service.dart';

/// Shows the death acknowledgement dialog whenever the active timer hits the
/// dead phase, including when the user is not on [DeathTimerScreen].
class DeathTimerGlobalListener extends StatefulWidget {
  const DeathTimerGlobalListener({
    super.key,
    required this.navigatorKey,
    required this.child,
    this.statusService,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final CharacterStatusService? statusService;

  @override
  State<DeathTimerGlobalListener> createState() =>
      _DeathTimerGlobalListenerState();
}

class _DeathTimerGlobalListenerState extends State<DeathTimerGlobalListener> {
  late final CharacterStatusService _statusService =
      widget.statusService ?? CharacterStatusService();

  bool _deathDialogShown = false;

  @override
  void initState() {
    super.initState();
    DeathTimerService.instance.addListener(_onTimerService);
  }

  @override
  void dispose() {
    DeathTimerService.instance.removeListener(_onTimerService);
    super.dispose();
  }

  /// After [pushReplacement] from home, the death screen may be the only route;
  /// [popUntil] would not leave the timer. Reset stack to [AuthGate] in that case.
  void _popToMainAfterDeath() {
    final nav = widget.navigatorKey.currentState;
    if (nav == null) return;
    if (nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    } else {
      nav.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => AuthGate()),
        (route) => false,
      );
    }
  }

  void _onTimerService() {
    if (!mounted) return;
    final t = DeathTimerService.instance.active;
    if (t == null) {
      if (_deathDialogShown) {
        if (mounted) setState(() => _deathDialogShown = false);
      }
      return;
    }
    if (t.phase == DeathTimerPhase.dead && !_deathDialogShown) {
      if (t.pendingDeathExpiredLog) {
        t.pendingDeathExpiredLog = false;
        unawaited(_emitDeathExpired(t));
      }
      _deathDialogShown = true;
      _showDeathDialog(t);
    }
  }

  Future<void> _emitDeathExpired(ActiveDeathTimer t) async {
    try {
      await ActivityEventsService().recordDeathTimerExpired(
        activityEventId: t.activityEventId,
        characterId: t.character.id.isNotEmpty ? t.character.id : null,
      );
    } catch (_) {}
  }

  Future<void> _showDeathDialog(ActiveDeathTimer t) async {
    final nav = widget.navigatorKey.currentState;
    if (nav == null || !nav.mounted) return;
    final dialogContext = nav.overlay?.context ?? nav.context;
    if (!dialogContext.mounted) return;

    final body = t.rules.deathExpiredDialogBody;
    await showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Death'),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final characterId = t.character.id;
              if (characterId.isNotEmpty) {
                await _statusService.clearDeathTimer(characterId);
              }
              DeathTimerService.instance.clear();
              _popToMainAfterDeath();
              if (mounted) setState(() => _deathDialogShown = false);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
