import 'package:flutter/material.dart';

import '../models/character.dart';
import '../services/characters_repository.dart';
import '../services/death_timer_service.dart';
import '../services/rules_repository.dart';
import 'death_timer_screen.dart';

String _capitalize(String s) {
  if (s.isEmpty) return s;
  return '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';
}

/// Asks user to select character and confirm before starting death count.
class DeathCountConfirmScreen extends StatefulWidget {
  const DeathCountConfirmScreen({super.key});

  @override
  State<DeathCountConfirmScreen> createState() => _DeathCountConfirmScreenState();
}

class _DeathCountConfirmScreenState extends State<DeathCountConfirmScreen> {
  Character? _selectedCharacter;
  bool _playtest = false;
  String _interventionRoleName = 'medic';

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    final rules = await RulesRepository().getDeathRules();
    if (mounted) setState(() => _interventionRoleName = rules.interventionRoleName);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DeathTimerService.instance,
      builder: (context, _) {
        final hasActive = DeathTimerService.instance.hasActive;
        final activeCharacter = DeathTimerService.instance.active?.character;

        return Scaffold(
      appBar: AppBar(title: const Text('Death Counter')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasActive) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Death timer active',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Character ${activeCharacter?.shortId ?? ''} is still dying. The countdown runs in the background.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => _resume(context),
                      child: const Text('Resume death timer'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
            const Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange),
            const SizedBox(height: 24),
            Text(
              hasActive ? 'Or start a new death timer' : 'Start Death Timer?',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Select which character is downed. A ${_capitalize(_interventionRoleName)} can scan the QR code to stop the count.',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            StreamBuilder<List<Character>>(
              stream: CharactersRepository().watchCharacters(),
              builder: (context, snap) {
                final characters = snap.data ?? [];
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (characters.isEmpty) ...[
                      Text(
                        'No characters. Create one or use playtest.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ] else ...[
                      RadioGroup<Character>(
                        groupValue: _playtest ? null : _selectedCharacter,
                        onChanged: (v) =>
                            setState(() => _selectedCharacter = v),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final c in characters)
                              RadioListTile<Character>(
                                value: c,
                                enabled: !_playtest,
                                title: Text(c.name),
                                subtitle: Text('ID: ${c.shortId}'),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: _playtest,
                      onChanged: (v) => setState(() {
                        _playtest = v ?? false;
                        if (_playtest) _selectedCharacter = null;
                      }),
                      title: const Text('Playtest mode'),
                      subtitle: const Text('Use ID 000'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => _confirm(context),
              child: const Text('Yes, start death timer'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
      },
    );
  }

  void _resume(BuildContext context) {
    final t = DeathTimerService.instance.active;
    if (t == null) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => DeathTimerScreen(character: t.character),
      ),
    );
  }

  void _confirm(BuildContext context) {
    if (!_playtest && _selectedCharacter == null) return;
    final character = _playtest
        ? Character(
            id: '',
            shortId: '000',
            ownerId: '',
            name: 'Playtest',
          )
        : _selectedCharacter!;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => DeathTimerScreen(character: character),
      ),
    );
  }
}
