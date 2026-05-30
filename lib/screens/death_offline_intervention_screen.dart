import 'dart:async';

import 'package:flutter/material.dart';

import '../models/death_rules.dart';
import '../services/activity_events_service.dart';
import '../services/characters_repository.dart';
import '../services/totp_service.dart';
import '../utils/short_id.dart';

/// Manual entry for intervener (medic/healer) when offline: character ID (3 chars) + 6-digit TOTP.
class DeathOfflineInterventionScreen extends StatefulWidget {
  const DeathOfflineInterventionScreen({
    super.key,
    required this.fallenPlayerShortId,
    required this.fallenPlayerId,
    required this.rules,
    required this.activityEventId,
  });

  final String fallenPlayerShortId;
  final String fallenPlayerId;
  final DeathRules rules;
  final String activityEventId;

  @override
  State<DeathOfflineInterventionScreen> createState() =>
      _DeathOfflineInterventionScreenState();
}

class _DeathOfflineInterventionScreenState
    extends State<DeathOfflineInterventionScreen> {
  final _totp = TotpService();
  final _eventsService = ActivityEventsService();
  final _charsRepo = CharactersRepository();
  String _roleName() => widget.rules.interventionRoleName.isNotEmpty
      ? widget.rules.interventionRoleName
      : 'medic';

  final _medicIdController = TextEditingController();
  final _totpController = TextEditingController();
  String? _error;
  bool _phaseIntervention = false;
  int _remainingSeconds = 0;
  Timer? _timer;
  final _medicIdController2 = TextEditingController();
  final _totpController2 = TextEditingController();
  bool _interventionComplete = false;
  bool _timedOutToDeath = false;
  Timer? _timeoutTimer;

  @override
  void dispose() {
    _timer?.cancel();
    _timeoutTimer?.cancel();
    _medicIdController.dispose();
    _totpController.dispose();
    _medicIdController2.dispose();
    _totpController2.dispose();
    super.dispose();
  }

  Future<void> _submitFirst() async {
    final medicShortId = _medicIdController.text.trim().toUpperCase();
    final code = _totpController.text.trim();
    if (medicShortId.isEmpty || code.length != 6) {
      setState(() => _error = 'Enter ${_roleName()} ID (3 chars) and 6-digit code');
      return;
    }
    if (!_totp.verify(code)) {
      setState(() => _error = 'Invalid code');
      return;
    }
    final medicUserId = medicShortId == playtestShortId
        ? 'playtest-medic'
        : await _charsRepo.getOwnerByShortId(medicShortId);
    if (medicUserId == null) {
      setState(() => _error = 'Unknown character ID: $medicShortId');
      return;
    }
    setState(() {
      _error = null;
      _phaseIntervention = true;
      _remainingSeconds = widget.rules.interventionCountSeconds;
    });
    try {
      _eventsService.recordDeathTimeStopped(
        injuredPlayerId: widget.fallenPlayerId,
        medicPlayerId: medicUserId,
        activityEventId: widget.activityEventId,
        fallenShortId: widget.fallenPlayerShortId,
      );
    } catch (_) {}
    _startInterventionTimer();
  }

  void _startInterventionTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remainingSeconds--;
        if (_remainingSeconds <= 0) {
          _timer?.cancel();
          _startSecondVerificationTimeout();
        }
      });
    });
  }

  void _startSecondVerificationTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(minutes: 1), () {
      if (!mounted || _interventionComplete) return;
      setState(() => _timedOutToDeath = true);
    });
  }

  Future<void> _submitSecond() async {
    _timeoutTimer?.cancel();
    final medicShortId = _medicIdController2.text.trim().toUpperCase();
    final code = _totpController2.text.trim();
    if (medicShortId.isEmpty || code.length != 6) {
      setState(() => _error = 'Enter ${_roleName()} ID (3 chars) and 6-digit code');
      return;
    }
    if (!_totp.verify(code)) {
      setState(() => _error = 'Invalid code');
      return;
    }
    final medicUserId = medicShortId == playtestShortId
        ? 'playtest-medic'
        : await _charsRepo.getOwnerByShortId(medicShortId);
    if (medicUserId == null) {
      setState(() => _error = 'Unknown character ID: $medicShortId');
      return;
    }
    setState(() {
      _error = null;
      _interventionComplete = true;
    });
    _eventsService.recordDeathInterventionComplete(
      helpingPlayerId: medicUserId,
      offline: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offline Intervention')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _timedOutToDeath
            ? _buildDeath()
            : _interventionComplete
                ? _buildComplete()
                : _phaseIntervention
                    ? _buildInterventionPhase()
                    : _buildInitialForm(),
      ),
    );
  }

  Widget _buildDeath() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.close, size: 64, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          Text(
            'Character died',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
          Text(
            'No verification received within 1 minute.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your character ID',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          widget.fallenPlayerShortId,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontFamily: 'monospace',
              ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _medicIdController,
          decoration: InputDecoration(
            labelText: '${_roleName()[0].toUpperCase()}${_roleName().substring(1)} character ID (3 chars)',
            hintText: 'e.g. A1B or 000',
          ),
          textCapitalization: TextCapitalization.characters,
          maxLength: 3,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _totpController,
          decoration: InputDecoration(
            labelText: '6-digit code',
            hintText: 'From ${_roleName()}\'s app',
          ),
          keyboardType: TextInputType.number,
          maxLength: 6,
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const Spacer(),
        FilledButton(
          onPressed: _submitFirst,
          child: const Text('Verify and start intervention'),
        ),
      ],
    );
  }

  Widget _buildInterventionPhase() {
    if (_remainingSeconds <= 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Intervention complete. Scan QR on main screen, or enter below:',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _medicIdController2,
            decoration: InputDecoration(
              labelText: '${_roleName()[0].toUpperCase()}${_roleName().substring(1)} character ID (3 chars)',
            ),
            textCapitalization: TextCapitalization.characters,
            maxLength: 3,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _totpController2,
            decoration: const InputDecoration(
              labelText: '6-digit code',
            ),
            keyboardType: TextInputType.number,
            maxLength: 6,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const Spacer(),
          FilledButton(
            onPressed: _submitSecond,
            child: const Text('Complete revival'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Revival in progress...',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        Text(
          '${_remainingSeconds ~/ 60}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}',
          style: Theme.of(context).textTheme.displayMedium,
        ),
        const Spacer(),
        Text(
          'If no verification within 1 minute, character will be marked dead.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildComplete() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 64, color: Colors.green.shade700),
          const SizedBox(height: 16),
          Text(
            'Character revived!',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
