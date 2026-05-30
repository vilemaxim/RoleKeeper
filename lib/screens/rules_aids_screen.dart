import 'package:flutter/material.dart';

import '../models/death_rules.dart';
import '../services/rules_repository.dart';
import 'death_count_confirm_screen.dart';
import 'medic_scan_screen.dart';

String _capitalize(String s) {
  if (s.isEmpty) return s;
  return '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';
}

/// List of available rules aids.
class RulesAidsScreen extends StatefulWidget {
  const RulesAidsScreen({super.key});

  @override
  State<RulesAidsScreen> createState() => _RulesAidsScreenState();
}

class _RulesAidsScreenState extends State<RulesAidsScreen> {
  bool _loading = true;
  DeathRules _rules = DeathRules.defaultRules;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    final rules = await RulesRepository().getDeathRules();
    if (mounted) {
      setState(() {
        _rules = rules;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  _AidTile(
                    title: 'Death Counter',
                    subtitle: 'Start the death timer when your character is downed',
                    icon: Icons.timer,
                    onTap: () => _openDeathCounter(context),
                  ),
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
