import 'dart:async';

import 'package:flutter/material.dart';

import '../models/character.dart';
import '../services/characters_repository.dart';
import '../services/rules_repository.dart';
import '../services/totp_service.dart';

String _capitalize(String s) {
  if (s.isEmpty) return s;
  return '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';
}

/// Intervener's (medic/healer) offline mode: displays character short ID and TOTP code for the
/// fallen player to enter when neither party has connectivity.
class MedicOfflineInterventionScreen extends StatefulWidget {
  const MedicOfflineInterventionScreen({super.key});

  @override
  State<MedicOfflineInterventionScreen> createState() =>
      _MedicOfflineInterventionScreenState();
}

class _MedicOfflineInterventionScreenState
    extends State<MedicOfflineInterventionScreen> {
  final _totp = TotpService();
  Timer? _refreshTimer;
  String _code = '';
  int _secondsUntilRefresh = 30;
  String _roleName = 'medic';

  @override
  void initState() {
    super.initState();
    _updateCode();
    _startRefreshTimer();
    _loadRules();
  }

  Future<void> _loadRules() async {
    final rules = await RulesRepository().getDeathRules();
    if (mounted) setState(() => _roleName = rules.interventionRoleName);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _updateCode() {
    final now = DateTime.now();
    final sec = now.second;
    final remainder = sec % 30;
    _secondsUntilRefresh = remainder == 0 ? 30 : 30 - remainder;
    setState(() {
      _code = _totp.generateCode();
    });
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secondsUntilRefresh--;
        if (_secondsUntilRefresh <= 0) {
          _updateCode();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${_capitalize(_roleName)} – Offline'),
      ),
      body: SafeArea(
        child: StreamBuilder<List<Character>>(
          stream: CharactersRepository().watchCharacters(),
          builder: (context, snap) {
            final characters = snap.data ?? [];
            final shortIds = characters.map((c) => c.shortId).toList();
            final displayId = shortIds.isEmpty
                ? '000'
                : shortIds.join(', ');

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your character ID',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            displayId,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontFamily: 'monospace',
                                ),
                          ),
                          if (characters.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'No characters – use 000 for playtest',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(
                        '6-digit code',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        _code,
                        style: Theme.of(context).textTheme.displayLarge?.copyWith(
                              fontFamily: 'monospace',
                              letterSpacing: 8,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Refreshes in ${_secondsUntilRefresh}s',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'How to use',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'When helping a fallen player who has no connection:\n\n'
                '1. The player taps "Offline intervention" on their death timer.\n\n'
                '2. Tell them your character ID ($displayId) and this code. '
                'They will enter both to start the revival countdown.\n\n'
                '3. Stay with the player. When the countdown finishes, '
                'give them the new code (it updates every 30 seconds).\n\n'
                '4. They enter it again to complete the revival.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
