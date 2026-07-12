import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/game_role.dart';
import '../services/active_character_preference_service.dart';
import '../services/characters_repository.dart';
import '../services/death_timer_service.dart';
import '../services/game_context_service.dart';
import '../services/game_membership_service.dart';
import '../services/rules_repository.dart';
import '../utils/error_reporting.dart';
import 'death_timer_screen.dart';

String _capitalize(String s) {
  if (s.isEmpty) return s;
  return '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';
}

/// Confirms starting (or resuming) a death timer for the home active character.
class DeathCountConfirmScreen extends StatefulWidget {
  const DeathCountConfirmScreen({
    super.key,
    this.activeCharacterPrefs,
    this.charactersRepository,
    this.membershipService,
  });

  final ActiveCharacterPreferenceService? activeCharacterPrefs;
  final CharactersRepository? charactersRepository;
  final GameMembershipService? membershipService;

  @override
  State<DeathCountConfirmScreen> createState() =>
      _DeathCountConfirmScreenState();
}

class _DeathCountConfirmScreenState extends State<DeathCountConfirmScreen> {
  static const _noCharacterMessage = 'Select or create a character first';
  static const _playtestCharacter = Character(
    id: '',
    shortId: '000',
    ownerId: '',
    name: 'Playtest',
  );

  bool _playtest = false;
  String _interventionRoleName = 'medic';
  bool _loading = true;
  Character? _activeCharacter;
  GameRole _gameRole = GameRole.player;
  String? _loadError;

  late final ActiveCharacterPreferenceService _activeCharacterPrefs =
      widget.activeCharacterPrefs ?? ActiveCharacterPreferenceService();
  late final CharactersRepository _charactersRepo =
      widget.charactersRepository ?? CharactersRepository();
  late final GameMembershipService _membership =
      widget.membershipService ?? GameMembershipService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Character?> _resolveActiveCharacter(String? activeId) async {
    if (activeId == null || activeId.isEmpty) return null;
    final owned = await _charactersRepo.watchCharacters().first;
    for (final c in owned) {
      if (c.id == activeId) return c;
    }
    return null;
  }

  Future<void> _load() async {
    try {
      final rules = await RulesRepository().getDeathRules();
      final role = await _membership.getRoleInGame();
      final tenantKey = GameContextService.instance.currentTenantKey;
      final activeId =
          await _activeCharacterPrefs.getActiveCharacterId(tenantKey);
      final active = await _resolveActiveCharacter(activeId);
      if (!mounted) return;
      final missingForPlayer =
          active == null && !role.canConfigureDeathRules;
      setState(() {
        _interventionRoleName = rules.interventionRoleName;
        _gameRole = role;
        _activeCharacter = active;
        _loading = false;
        if (missingForPlayer) {
          _loadError = _noCharacterMessage;
        }
      });
      if (missingForPlayer && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(_noCharacterMessage)),
        );
        Navigator.pop(context);
      }
    } catch (e, st) {
      final report =
          reportAppError('DeathCountConfirmScreen.load', e, st);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = report.userMessage;
      });
    }
  }

  void _openTimer(BuildContext context, Character character) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => DeathTimerScreen(character: character),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DeathTimerService.instance,
      builder: (context, _) {
        final hasActive = DeathTimerService.instance.hasActive;
        final timerCharacter = DeathTimerService.instance.active?.character;
        final canPlaytest = _gameRole.canConfigureDeathRules;

        return Scaffold(
          appBar: AppBar(title: const Text('Death Counter')),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
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
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Character ${timerCharacter?.shortId ?? ''} is still dying. The countdown runs in the background.',
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
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 64,
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        hasActive
                            ? 'Or start a new death timer'
                            : 'Start Death Timer?',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _confirmBodyCopy,
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      if (canPlaytest) ...[
                        const SizedBox(height: 24),
                        CheckboxListTile(
                          value: _playtest,
                          onChanged: (v) => setState(() {
                            _playtest = v ?? false;
                          }),
                          title: const Text('Playtest mode'),
                          subtitle: const Text('Use ID 000'),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ],
                      if (_loadError != null && canPlaytest) ...[
                        const SizedBox(height: 12),
                        Text(
                          _loadError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
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

  String get _confirmBodyCopy {
    final role = _capitalize(_interventionRoleName);
    if (_playtest) {
      return 'Playtest mode uses ID 000. A $role can scan the QR code to stop the count.';
    }
    final active = _activeCharacter;
    if (active == null) {
      return '$_noCharacterMessage.';
    }
    return 'Start the death timer for ${active.name} (ID ${active.shortId}). '
        'A $role can scan the QR code to stop the count.';
  }

  void _resume(BuildContext context) {
    final t = DeathTimerService.instance.active;
    if (t == null) return;
    _openTimer(context, t.character);
  }

  void _confirm(BuildContext context) {
    if (_playtest && _gameRole.canConfigureDeathRules) {
      _openTimer(context, _playtestCharacter);
      return;
    }
    final character = _activeCharacter;
    if (character == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_noCharacterMessage)),
      );
      Navigator.pop(context);
      return;
    }
    _openTimer(context, character);
  }
}
