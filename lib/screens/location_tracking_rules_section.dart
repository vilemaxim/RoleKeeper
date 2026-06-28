import 'package:flutter/material.dart';

import '../models/location_tracking_rules.dart';
import '../services/location_tracking_rules_repository.dart';
import '../utils/error_reporting.dart';

/// Admin toggle for tenant-scoped location tracking on the Rules screen.
class LocationTrackingRulesSection extends StatefulWidget {
  const LocationTrackingRulesSection({
    super.key,
    required this.locationRulesRepository,
  });

  final LocationTrackingRulesRepository locationRulesRepository;

  @override
  State<LocationTrackingRulesSection> createState() =>
      _LocationTrackingRulesSectionState();
}

class _LocationTrackingRulesSectionState
    extends State<LocationTrackingRulesSection> {
  bool _loading = true;
  bool _saving = false;
  LocationTrackingRules _rules = LocationTrackingRules.defaultRules;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rules = await widget.locationRulesRepository.get();
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _loading = false;
      });
    } catch (e, st) {
      final report = reportAppError('LocationTrackingRulesSection.load', e, st);
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(report.userMessage)),
      );
    }
  }

  Future<void> _onEnabledChanged(bool value) async {
    final previous = _rules;
    setState(() {
      _rules = previous.copyWith(enabled: value);
      _saving = true;
    });
    try {
      await widget.locationRulesRepository.save(_rules);
    } catch (e, st) {
      final report = reportAppError('LocationTrackingRulesSection.save', e, st);
      if (!mounted) return;
      setState(() => _rules = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(report.userMessage)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
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

    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.35,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Location tracking',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'When enabled, players can opt in to location sharing voluntarily. '
          'Location pings run only while the event is live.',
          style: muted,
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable location tracking'),
          value: _rules.enabled,
          onChanged: _saving ? null : _onEnabledChanged,
        ),
        if (_saving)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}
