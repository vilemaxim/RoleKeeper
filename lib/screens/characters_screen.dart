import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/character.dart';
import '../models/game_role.dart';
import '../models/larp_manager_event_link.dart';
import '../services/characters_repository.dart';
import '../services/game_context_service.dart';
import '../services/game_membership_service.dart';
import '../services/larp_manager_registration_service.dart';
import '../utils/error_reporting.dart';
import '../widgets/lm_integration_gate.dart';
import 'character_detail_screen.dart';
import 'larp_manager_integration_screen.dart';

/// Character list (portfolio) for the current user.
class CharactersScreen extends StatefulWidget {
  const CharactersScreen({super.key});

  @override
  State<CharactersScreen> createState() => _CharactersScreenState();
}

class _CharactersScreenState extends State<CharactersScreen> {
  final _repo = CharactersRepository();
  final _registrationService = LarpManagerRegistrationService();
  final _membershipService = GameMembershipService();

  GameRole _role = GameRole.player;
  bool _checking = false;
  String? _characterMessage;
  LarpManagerEventLink? _eventLink;
  bool _lmIntegrationMissing = false;
  String? _syncError;

  bool get _isOrganizer => _role.canConfigureDeathRules;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    await _loadEventLink();
    final role = await _membershipService.getRoleInGame();
    if (!mounted) return;
    setState(() => _role = role);
    await _refreshCharacterStatus();
  }

  Future<void> _loadEventLink() async {
    final link = await _registrationService.getEventLinkForTenant(
      GameContextService.instance.currentTenantKey,
    );
    if (!mounted) return;
    setState(() => _eventLink = link);
  }

  Future<void> _refreshCharacterStatus({bool forceRefresh = false}) async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _syncError = null;
      _lmIntegrationMissing = false;
    });
    try {
      await _loadEventLink();

      final check =
          await _registrationService.verifyRegistrationForCurrentGame(
        forceRefresh: forceRefresh,
      );

      var link = _eventLink;
      final existing = link;
      if (existing != null &&
          (check.registrationPageUrl != null ||
              check.characterCreatePageUrl != null)) {
        link = LarpManagerEventLink(
          baseUrl: existing.baseUrl,
          eventSlug: existing.eventSlug,
          registrationPageUrl:
              check.registrationPageUrl ?? existing.registrationPageUrl,
          characterCreatePageUrl:
              check.characterCreatePageUrl ?? existing.characterCreatePageUrl,
        );
      }

      final role = await _membershipService.getRoleInGame();
      if (!mounted) return;
      setState(() {
        _role = role;
        _eventLink = link;
        _characterMessage = check.characterMessage;
        _checking = false;
      });
    } on FirebaseFunctionsException catch (e, st) {
      final report = reportAppError('CharactersScreen.sync', e, st);
      final integrationMissing = e.code == 'failed-precondition' &&
          (e.message ?? '').toLowerCase().contains('larpmanager is not connected');
      if (!mounted) return;
      setState(() {
        _lmIntegrationMissing = integrationMissing;
        _syncError = integrationMissing ? null : report.userMessage;
        _checking = false;
      });
    } catch (e, st) {
      final report = reportAppError('CharactersScreen.sync', e, st);
      if (!mounted) return;
      setState(() {
        _syncError = report.userMessage;
        _checking = false;
      });
    }
  }

  Future<void> _openLarpManagerCharacterCreate() async {
    final url = _eventLink?.characterCreatePageUrl;
    if (url == null || url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Character creation link is not available. '
            'Re-select this LARP from the home screen or complete LM Integration.',
          ),
        ),
      );
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open: $url')),
      );
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted) await _refreshCharacterStatus(forceRefresh: true);
  }

  void _openLmIntegration() {
    Navigator.push(
      context,
      MaterialPageRoute<bool>(
        builder: (context) => const LarpManagerIntegrationScreen(),
      ),
    ).then((saved) {
      if (saved == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'LarpManager integration saved. Open LarpManager sync on home to pull data.',
            ),
          ),
        );
      }
      _refreshCharacterStatus(forceRefresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    return LmIntegrationGate(
      title: 'Characters',
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Characters'),
        actions: [
          IconButton(
            onPressed: _checking
                ? null
                : () => _refreshCharacterStatus(forceRefresh: true),
            tooltip: 'Sync characters',
            icon: _checking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: userId == null
          ? const Center(child: Text('Not signed in'))
          : StreamBuilder<List<Character>>(
              stream: _repo.watchCharacters(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error: ${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final characters = snapshot.data ?? [];
                if (characters.isEmpty) {
                  return _EmptyCharactersBody(
                    isOrganizer: _isOrganizer,
                    checking: _checking,
                    message: _characterMessage,
                    eventLink: _eventLink,
                    integrationMissing: _lmIntegrationMissing,
                    syncError: _syncError,
                    onOpenCreate: _openLarpManagerCharacterCreate,
                    onCheckAgain: () =>
                        _refreshCharacterStatus(forceRefresh: true),
                    onOpenLmIntegration: _openLmIntegration,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: characters.length,
                  itemBuilder: (context, index) {
                    final c = characters[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            c.name.isNotEmpty
                                ? c.name[0].toUpperCase()
                                : '?',
                          ),
                        ),
                        title: Text(c.name),
                        subtitle: Text(
                          c.gameSystemName != null
                              ? '${c.shortId} • ${c.gameSystemName!}'
                              : c.shortId,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openDetail(context, c),
                      ),
                    );
                  },
                );
              },
            ),
      ),
    );
  }

  void _openDetail(BuildContext context, Character character) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CharacterDetailScreen(character: character),
      ),
    );
  }
}

class _EmptyCharactersBody extends StatelessWidget {
  const _EmptyCharactersBody({
    required this.isOrganizer,
    required this.checking,
    required this.message,
    required this.eventLink,
    required this.integrationMissing,
    required this.syncError,
    required this.onOpenCreate,
    required this.onCheckAgain,
    required this.onOpenLmIntegration,
  });

  final bool isOrganizer;
  final bool checking;
  final String? message;
  final LarpManagerEventLink? eventLink;
  final bool integrationMissing;
  final String? syncError;
  final VoidCallback onOpenCreate;
  final VoidCallback onCheckAgain;
  final VoidCallback onOpenLmIntegration;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasLink = eventLink != null;

    final bodyText = _bodyText(hasLink: hasLink);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_outline,
              size: 64,
              color: scheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No character yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              bodyText,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            if (syncError != null && syncError!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                syncError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            if (hasLink) ...[
              const SizedBox(height: 12),
              SelectableText(
                eventLink!.characterCreatePageUrl,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            ..._actions(context, hasLink: hasLink),
          ],
        ),
      ),
    );
  }

  String _bodyText({required bool hasLink}) {
    if (message != null && message!.isNotEmpty) return message!;

    if (isOrganizer) {
      if (!hasLink) {
        return 'This LARP is not linked to a LarpManager URL in RoleKeeper yet. '
            'Use Change LARP on the home screen and pick Crucible (or paste your '
            'LarpManager event URL) so RoleKeeper knows which event to sync.';
      }
      if (integrationMissing) {
        return 'Crucible is linked to LarpManager, but server sync is not set up yet. '
            'As the organizer, add a LarpManager service account in LM Integration '
            'so RoleKeeper can sync registrations and characters for players.';
      }
      return 'Create a character on LarpManager for this event. '
          'Tap Sync characters after players assign characters on LarpManager.';
    }

    if (!hasLink) {
      return 'This LARP is not linked to LarpManager in RoleKeeper yet. '
          'Ask your organizer to select the event or complete LM Integration.';
    }
    if (integrationMissing) {
      return 'LarpManager server sync is not set up for this event yet. '
          'If you are the organizer, tap Set up LM Integration below. '
          'Otherwise ask your organizer to complete it — you can still create a '
          'character on LarpManager in the meantime.';
    }
    return 'Create a character on LarpManager for this event and assign it to your '
        'registration. RoleKeeper will sync it here automatically.';
  }

  List<Widget> _actions(BuildContext context, {required bool hasLink}) {
    final widgets = <Widget>[];

    if (integrationMissing) {
      widgets.add(
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: checking ? null : onOpenLmIntegration,
            icon: const Icon(Icons.integration_instructions_outlined),
            label: const Text('Set up LM Integration'),
          ),
        ),
      );
      widgets.add(const SizedBox(height: 8));
    }

    if (hasLink) {
      widgets.add(
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: checking ? null : onOpenCreate,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Create character on LarpManager'),
          ),
        ),
      );
      widgets.add(const SizedBox(height: 8));
    }

    widgets.add(
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: checking ? null : onCheckAgain,
          icon: checking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          label: const Text('Sync characters'),
        ),
      ),
    );

    return widgets;
  }
}
