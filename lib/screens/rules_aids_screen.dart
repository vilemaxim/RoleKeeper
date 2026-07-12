import 'package:flutter/material.dart';

import '../models/death_rules.dart';
import '../services/active_character_preference_service.dart';
import '../services/game_context_service.dart';
import '../services/rules_repository.dart';
import 'death_count_confirm_screen.dart';
import 'medic_scan_screen.dart';

String _capitalize(String s) {
  if (s.isEmpty) return s;
  return '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';
}

/// List of available rules aids.
class RulesAidsScreen extends StatefulWidget {
  const RulesAidsScreen({
    super.key,
    this.activeCharacterPrefs,
  });

  final ActiveCharacterPreferenceService? activeCharacterPrefs;

  @override
  State<RulesAidsScreen> createState() => _RulesAidsScreenState();
}

class _RulesAidsScreenState extends State<RulesAidsScreen> {
  bool _loading = true;
  DeathRules _rules = DeathRules.defaultRules;
  String? _activeCharacterId;
  late final ActiveCharacterPreferenceService _activeCharacterPrefs =
      widget.activeCharacterPrefs ?? ActiveCharacterPreferenceService();

  static const _noCharacterMessage = 'Select or create a character first';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rules = await RulesRepository().getDeathRules();
    final activeId = await _activeCharacterPrefs.getActiveCharacterId(
      GameContextService.instance.currentTenantKey,
    );
    if (mounted) {
      setState(() {
        _rules = rules;
        _activeCharacterId = activeId;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveCharacter =
        _activeCharacterId != null && _activeCharacterId!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rules Aids'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_rules.enabled) ...[
                  _deathCounterTile(context, hasActiveCharacter),
                  if (_rules.interventionEnabled) const SizedBox(height: 12),
                ],
                if (_rules.enabled && _rules.interventionEnabled)
                  _AidTile(
                    title: _capitalize(_rules.interventionRoleName),
                    subtitle: 'Scan QR codes to help fallen players',
                    icon: Icons.medical_services,
                    onTap: () => _openInterventionScan(context),
                  ),
                if (!_rules.enabled)
                  Text(
                    'There are no rules enabled for this game.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
              ],
            ),
    );
  }

  Widget _deathCounterTile(BuildContext context, bool hasActiveCharacter) {
    final tile = _AidTile(
      title: 'Death Counter',
      subtitle: hasActiveCharacter
          ? 'Start the death timer when your character is downed'
          : _noCharacterMessage,
      icon: Icons.timer,
      onTap: hasActiveCharacter ? () => _openDeathCounter(context) : null,
    );
    if (hasActiveCharacter) return tile;
    return Tooltip(message: _noCharacterMessage, child: tile);
  }

  void _openDeathCounter(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const DeathCountConfirmScreen(),
      ),
    );
  }

  void _openInterventionScan(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MedicScanScreen(),
      ),
    );
  }
}

class _AidTile extends StatelessWidget {
  const _AidTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: onTap != null ? const Icon(Icons.chevron_right) : null,
        onTap: onTap,
        enabled: onTap != null,
      ),
    );
  }
}
