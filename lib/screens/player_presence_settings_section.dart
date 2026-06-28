import 'dart:async';

import 'package:flutter/material.dart';

import '../models/member_presence.dart';
import '../models/location_tracking_rules.dart';
import '../services/location_tracking_rules_repository.dart';
import '../services/member_presence_repository.dart';
import '../utils/error_reporting.dart';

/// Location opt-in and in-game / out-of-game toggles for the current player.
///
/// Hidden when location tracking is disabled for the LARP.
class PlayerPresenceSettingsSection extends StatefulWidget {
  const PlayerPresenceSettingsSection({
    super.key,
    required this.presenceRepository,
    required this.locationRulesRepository,
    this.onPresenceUpdated,
  });

  final MemberPresenceRepository presenceRepository;
  final LocationTrackingRulesRepository locationRulesRepository;
  /// Called after opt-in or presence state changes (e.g. to refresh ping timer).
  final VoidCallback? onPresenceUpdated;

  @override
  State<PlayerPresenceSettingsSection> createState() =>
      _PlayerPresenceSettingsSectionState();
}

class _PlayerPresenceSettingsSectionState
    extends State<PlayerPresenceSettingsSection> {
  bool _loading = true;
  bool _trackingEnabled = false;
  MemberPresence _presence = MemberPresence.defaultPresence;
  StreamSubscription<LocationTrackingRules>? _rulesSub;

  @override
  void initState() {
    super.initState();
    _rulesSub = widget.locationRulesRepository.watch().listen((rules) {
      if (!mounted) return;
      setState(() => _trackingEnabled = rules.enabled);
    });
    _load();
  }

  @override
  void dispose() {
    _rulesSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final presence = await widget.presenceRepository.getPresence();
      if (!mounted) return;
      setState(() {
        _presence = presence;
        _loading = false;
      });
    } catch (e, st) {
      final report =
          reportAppError('PlayerPresenceSettingsSection.load', e, st);
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(report.userMessage)),
      );
    }
  }

  Future<void> _onLocationOptInChanged(bool value) async {
    final previous = _presence;
    setState(() => _presence = _presence.copyWith(locationOptIn: value));
    try {
      await widget.presenceRepository.setLocationOptIn(value);
      widget.onPresenceUpdated?.call();
    } catch (e, st) {
      final report =
          reportAppError('PlayerPresenceSettingsSection.locationOptIn', e, st);
      if (!mounted) return;
      setState(() => _presence = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(report.userMessage)),
      );
    }
  }

  Future<void> _onPresenceChanged(bool inGame) async {
    final newState =
        inGame ? PresenceState.inGame : PresenceState.outOfGame;
    final previous = _presence;
    setState(() => _presence = _presence.copyWith(presenceState: newState));
    try {
      await widget.presenceRepository.setPresenceState(newState);
      widget.onPresenceUpdated?.call();
    } catch (e, st) {
      final report =
          reportAppError('PlayerPresenceSettingsSection.presenceState', e, st);
      if (!mounted) return;
      setState(() => _presence = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(report.userMessage)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_trackingEnabled) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.35,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Location & presence',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Location sharing'),
          subtitle: Text(
            'Sharing your location is voluntary. Your position may be used for '
            'anti-cheat, safety, and in-game features. Location sharing does '
            'not stop when you are out of game.',
            style: muted,
          ),
          value: _presence.locationOptIn,
          onChanged: _onLocationOptInChanged,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('In game'),
          subtitle: Text(
            'Out of game affects in-game mechanics only; location sharing '
            'continues if you have opted in.',
            style: muted,
          ),
          value: _presence.presenceState == PresenceState.inGame,
          onChanged: _onPresenceChanged,
        ),
      ],
    );
  }
}
