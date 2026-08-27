import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/larp_manager_event_link.dart';
import '../models/larp_manager_registration_check_result.dart';
import '../screens/characters_screen.dart';
import '../screens/death_timer_screen.dart';
import '../screens/home_assistant_integration_screen.dart';
import '../screens/larp_manager_integration_screen.dart';
import '../screens/larp_manager_sync_settings_screen.dart';
import '../screens/larp_picker_screen.dart';
import '../screens/nfc_hunt_scan_screen.dart';
import '../screens/player_presence_settings_section.dart';
import '../screens/rules_aids_screen.dart';
import '../screens/rules_screen.dart';
import '../models/character.dart';
import '../models/death_rules.dart';
import '../models/event_session.dart';
import '../models/game_role.dart';
import '../models/member_presence.dart';
import '../models/nfc_hunt.dart';
import '../services/active_character_preference_service.dart';
import '../services/auth_service.dart';
import '../services/activity_events_service.dart';
import '../services/character_status_service.dart';
import '../services/characters_repository.dart';
import '../services/death_intervention_secrets_service.dart';
import '../services/death_timer_service.dart';
import '../services/event_session_repository.dart';
import '../services/game_context_service.dart';
import '../services/game_membership_service.dart';
import '../services/larp_manager_integration_status_service.dart';
import '../services/larp_manager_registration_service.dart';
import '../services/location_ping_service.dart';
import '../services/location_tracking_rules_repository.dart';
import '../services/member_presence_repository.dart';
import '../services/nfc_hunt_service.dart';
import '../services/user_profile_service.dart';
import '../utils/error_reporting.dart';
import '../widgets/lm_integration_setup_prompt.dart';
import '../widgets/location_opt_in_prompt.dart';

/// Main home screen shown after sign-in.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.user,
    this.authService,
  });

  final User user;
  final AuthService? authService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _membershipService = GameMembershipService();
  final _registrationService = LarpManagerRegistrationService();
  final _lmStatusService = LarpManagerIntegrationStatusService();
  final _locationPingService = LocationPingService();
  final _locationRulesRepo = LocationTrackingRulesRepository();
  final _eventSessionRepo = EventSessionRepository();
  final _presenceRepo = MemberPresenceRepository();
  final _charactersRepo = CharactersRepository();
  final _activeCharacterPrefs = ActiveCharacterPreferenceService();
  final _nfcHuntService = NfcHuntService();
  StreamSubscription? _eventSessionSub;
  StreamSubscription? _locationRulesSub;
  StreamSubscription? _charactersSub;
  StreamSubscription? _nfcHuntsSub;
  GameRole _gameRole = GameRole.player;
  LmIntegrationEvaluation? _lmEvaluation;
  bool _bootstrapDone = false;
  String? _currentLarpLabel;
  bool _larpManagerRegistered = true;
  bool _hasCharacter = true;
  LarpManagerEventLink? _larpManagerEventLink;
  String? _registrationMessage;
  String? _characterMessage;
  bool _checkingRegistration = false;
  bool _trackingEnabled = false;
  bool _eventLive = false;
  MemberPresence _presence = MemberPresence.defaultPresence;
  bool _locationOptInPromptDismissed = false;
  EventSession _lastEventSession = EventSession.defaultSession;
  List<Character> _ownedCharacters = const [];
  String? _activeCharacterId;
  List<NfcHunt> _nfcHunts = const [];

  @override
  void initState() {
    super.initState();
    _eventSessionSub = _eventSessionRepo.watch().listen((session) {
      if (!_lastEventSession.isLive && session.isLive) {
        _locationOptInPromptDismissed = false;
      }
      _lastEventSession = session;
      if (mounted) {
        setState(() => _eventLive = session.isLive);
      }
      unawaited(_syncLocationPings());
    });
    _locationRulesSub = _locationRulesRepo.watch().listen((rules) {
      if (mounted) {
        setState(() => _trackingEnabled = rules.enabled);
      }
      unawaited(_syncLocationPings());
    });
    _charactersSub = _charactersRepo.watchCharacters().listen((chars) {
      unawaited(_onOwnedCharactersChanged(chars));
    });
    _nfcHuntsSub = _nfcHuntService.watchHunts().listen((hunts) {
      if (mounted) setState(() => _nfcHunts = hunts);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _eventSessionSub?.cancel();
    _locationRulesSub?.cancel();
    _charactersSub?.cancel();
    _nfcHuntsSub?.cancel();
    _locationPingService.dispose();
    super.dispose();
  }

  Future<void> _onOwnedCharactersChanged(List<Character> chars) async {
    final tenantKey = GameContextService.instance.currentTenantKey;
    final active = await _activeCharacterPrefs.reconcileOwnedCharacters(
      tenantKey,
      chars.map((c) => c.id).toList(),
    );
    if (!mounted) return;
    setState(() {
      _ownedCharacters = chars;
      _activeCharacterId = active;
    });
  }

  Character? get _activeCharacter {
    final id = _activeCharacterId;
    if (id == null) return null;
    for (final c in _ownedCharacters) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _pickActiveCharacter() async {
    if (!ActiveCharacterSelection.showSwitcher(_ownedCharacters.length)) {
      return;
    }
    final selected = await showModalBottomSheet<Character>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Playing as',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final c in _ownedCharacters)
                ListTile(
                  title: Text(c.name),
                  subtitle: Text('ID: ${c.shortId}'),
                  trailing: c.id == _activeCharacterId
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(context, c),
                ),
            ],
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    final tenantKey = GameContextService.instance.currentTenantKey;
    await _activeCharacterPrefs.setActiveCharacterId(tenantKey, selected.id);
    if (!mounted) return;
    setState(() => _activeCharacterId = selected.id);
  }

  Future<void> _syncLocationPings() async {
    try {
      final rules = await _locationRulesRepo.get();
      final session = await _eventSessionRepo.get();
      final presence = await _presenceRepo.getPresence();
      if (mounted) {
        setState(() {
          _trackingEnabled = rules.enabled;
          _eventLive = session.isLive;
          _presence = presence;
        });
      }
      await _locationPingService.syncConditions(
        rules: rules,
        eventLive: session.isLive,
        presence: presence,
      );
    } catch (e, st) {
      debugPrint('HomeScreen._syncLocationPings: $e\n$st');
    }
  }

  bool get _showLocationOptInPrompt =>
      _trackingEnabled &&
      _eventLive &&
      !_presence.locationOptIn &&
      !_locationOptInPromptDismissed;

  Future<void> _bootstrap() async {
    await _membershipService.ensureMembershipForCurrentGame();
    final role = await _membershipService.getRoleInGame();
    final gameId = GameContextService.instance.currentGameId;
    final profile = UserProfileService();
    final label = await profile.getConfiguredLarpLabel(gameId) ??
        await _membershipService.getGameDisplayName(gameId);
    final evaluation = await _lmStatusService.evaluate();
    if (!mounted) return;
    setState(() {
      _gameRole = role;
      _currentLarpLabel = label;
      _lmEvaluation = evaluation;
      _bootstrapDone = true;
    });

    if (evaluation.isReady && evaluation.checkResult != null) {
      await _applyRegistrationCheck(evaluation.checkResult!);
    } else if (evaluation.isReady && evaluation.fromCache) {
      _refreshLmInBackground();
    } else if (!evaluation.isReady) {
      setState(() {
        _larpManagerRegistered = false;
        _hasCharacter = false;
      });
    }
    await _checkDeathTimerOnLogin();
    await _prefetchDeathInterventionSecrets();
    await _syncLocationPings();
  }

  /// Eagerly caches per-event TOTP + QR signing secrets while online so
  /// death timer / offline intervention work later without a network round-trip.
  Future<void> _prefetchDeathInterventionSecrets() async {
    final secretsService = DeathInterventionSecretsService();
    try {
      final secrets = await secretsService.fetchAndCacheSecrets();
      if (secrets != null) return;
      final report = reportAppError(
        'HomeScreen.deathSecretsPrefetch',
        Exception('Death intervention secrets unavailable'),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(report.userMessage)),
      );
    } catch (e, st) {
      final cached = await secretsService.getCachedSecrets();
      final likelyOffline = e is FirebaseFunctionsException &&
          (e.code == 'unavailable' || e.code == 'deadline-exceeded');
      if (likelyOffline && cached != null) {
        // Warm cache offline — fine; refresh can wait until connectivity returns.
        return;
      }
      final report = reportAppError(
        'HomeScreen.deathSecretsPrefetch',
        e,
        st,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(report.userMessage)),
      );
    }
  }

  /// Refreshes registration/LM status without blocking the first paint after cache hit.
  Future<void> _refreshLmInBackground() async {
    final evaluation =
        await _lmStatusService.evaluate(useCache: false, forceSync: false);
    if (!mounted) return;
    setState(() => _lmEvaluation = evaluation);
    if (evaluation.isReady && evaluation.checkResult != null) {
      await _applyRegistrationCheck(evaluation.checkResult!);
    } else if (!evaluation.isReady) {
      setState(() {
        _larpManagerRegistered = false;
        _hasCharacter = false;
      });
    }
  }

  bool get _lmReady => _lmEvaluation?.isReady ?? false;

  String? get _lmSetupErrorDetail {
    final err = _lmEvaluation?.lastError;
    if (err == null) return null;
    return reportAppError('HomeScreen.lmStatus', err).userMessage;
  }

  Future<void> _reevaluateLmIntegration({bool forceSync = false}) async {
    final evaluation = await _lmStatusService.evaluate(forceSync: forceSync);
    if (!mounted) return;
    setState(() => _lmEvaluation = evaluation);
    if (evaluation.isReady && evaluation.checkResult != null) {
      await _applyRegistrationCheck(evaluation.checkResult!);
    } else if (!evaluation.isReady) {
      setState(() {
        _larpManagerRegistered = false;
        _hasCharacter = false;
      });
    }
  }

  Future<void> _applyRegistrationCheck(
    LarpManagerRegistrationCheckResult check,
  ) async {
    LarpManagerEventLink? eventLink = _larpManagerEventLink;
    if (eventLink == null &&
        check.registrationPageUrl != null &&
        check.registrationPageUrl!.isNotEmpty) {
      eventLink = await _registrationService.getEventLinkForTenant(
        GameContextService.instance.currentTenantKey,
      );
    }
    final existing = eventLink;
    if (existing != null &&
        (check.registrationPageUrl != null ||
            check.characterCreatePageUrl != null)) {
      eventLink = LarpManagerEventLink(
        baseUrl: existing.baseUrl,
        eventSlug: existing.eventSlug,
        registrationPageUrl:
            check.registrationPageUrl ?? existing.registrationPageUrl,
        characterCreatePageUrl:
            check.characterCreatePageUrl ?? existing.characterCreatePageUrl,
      );
    } else {
      eventLink ??= await _registrationService.getEventLinkForTenant(
        GameContextService.instance.currentTenantKey,
      );
    }
    final role = await _membershipService.getRoleInGame();
    if (!mounted) return;
    setState(() {
      _larpManagerRegistered = check.registered;
      _hasCharacter = check.hasCharacter;
      _registrationMessage = check.message;
      _characterMessage = check.characterMessage;
      _larpManagerEventLink = eventLink;
      _gameRole = role;
    });
  }

  void _openLmIntegration() {
    Navigator.push(
      context,
      MaterialPageRoute<bool>(
        builder: (context) => const LarpManagerIntegrationScreen(),
      ),
    ).then((saved) async {
      if (saved == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'LarpManager integration saved. Open LarpManager sync to pull data.',
            ),
          ),
        );
      }
      await _reevaluateLmIntegration(forceSync: true);
    });
  }

  Future<void> _openLarpManagerCharacterCreate() async {
    final url = _larpManagerEventLink?.characterCreatePageUrl;
    if (url == null || url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Character creation link is not available for this LARP. '
            'Ask your organizer for the LarpManager character page.',
          ),
        ),
      );
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid character URL: $url')),
      );
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open: $url')),
      );
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      await _refreshRegistrationStatus(forceRefresh: true);
    }
  }

  Future<void> _openLarpManagerRegistration() async {
    final url = _larpManagerEventLink?.registrationPageUrl ??
        (await _registrationService.getEventLinkForTenant(
          GameContextService.instance.currentTenantKey,
        ))
            ?.registrationPageUrl;
    if (url == null || url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Registration link is not available for this LARP. '
            'Ask your organizer for the LarpManager signup page.',
          ),
        ),
      );
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid registration URL: $url')),
      );
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open: $url')),
      );
      return;
    }
    // Re-check after player returns from LarpManager signup.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      await _refreshRegistrationStatus(forceRefresh: true);
    }
  }

  Future<void> _refreshRegistrationStatus({bool forceRefresh = false}) async {
    if (_checkingRegistration) return;
    if (!_lmReady) return;
    setState(() => _checkingRegistration = true);
    try {
      final evaluation =
          await _lmStatusService.evaluate(forceSync: forceRefresh);
      if (!mounted) return;
      setState(() {
        _lmEvaluation = evaluation;
        _checkingRegistration = false;
      });
      if (evaluation.isReady && evaluation.checkResult != null) {
        await _applyRegistrationCheck(evaluation.checkResult!);
      } else if (!evaluation.isReady) {
        setState(() {
          _larpManagerRegistered = false;
          _hasCharacter = false;
        });
      }
    } catch (e, st) {
      final report = reportAppError('HomeScreen.refreshRegistration', e, st);
      if (!mounted) return;
      setState(() => _checkingRegistration = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(report.userMessage)),
      );
    }
  }

  Future<void> _openChangeLarp() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (context) => LarpPickerScreen(
          user: widget.user,
          switchMode: true,
        ),
      ),
    );
    if (changed == true && mounted) {
      setState(() {
        _bootstrapDone = false;
        _lmEvaluation = null;
      });
      await _bootstrap();
    }
  }

  String _profileInitials() {
    final u = widget.user;
    final name = u.displayName?.trim();
    if (name != null && name.isNotEmpty) {
      final parts = name.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        return ('${parts[0][0]}${parts[1][0]}').toUpperCase();
      }
      if (name.length >= 2) {
        return name.substring(0, 2).toUpperCase();
      }
      return name[0].toUpperCase();
    }
    final em = u.email;
    if (em != null && em.isNotEmpty) {
      return em[0].toUpperCase();
    }
    return '?';
  }

  String _profileDisplayName() {
    return widget.user.displayName?.trim().isNotEmpty == true
        ? widget.user.displayName!.trim()
        : (widget.user.email ?? 'Player');
  }

  Future<void> _checkDeathTimerOnLogin() async {
    final result = await CharacterStatusService().checkDeathTimerOnLogin();
    if (!mounted) return;
    switch (result) {
      case DeathTimerCheckJustDied(
          :final character,
          :final afterDeathTimerText,
          :final activityEventId,
        ):
        try {
          await ActivityEventsService().recordDeathTimerExpired(
            activityEventId: activityEventId,
            characterId: character.id.isNotEmpty ? character.id : null,
          );
        } catch (_) {}
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Death'),
            content: Text(
              DeathRules.deathExpiredWhileAwayFromStrings(
                character.name,
                afterDeathTimerText,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        break;
      case DeathTimerCheckActive(:final status):
        DeathTimerService.instance.setActive(status.toActiveDeathTimer());
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => DeathTimerScreen(character: status.character),
            ),
          );
        }
        break;
      case DeathTimerCheckNone():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.authService ?? AuthService();

    if (!_bootstrapDone) {
      return Scaffold(
        appBar: AppBar(title: const Text('RoleKeeper')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('RoleKeeper'),
        actions: [
          if (ActiveCharacterSelection.showSwitcher(_ownedCharacters.length) &&
              _activeCharacter != null)
            TextButton(
              onPressed: _pickActiveCharacter,
              child: Text(
                'Playing as: ${_activeCharacter!.name} ▾',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 4),
            child: PopupMenuButton<String>(
              tooltip: 'Account',
              offset: const Offset(0, 8),
              onSelected: (value) async {
                if (value == 'changeLarp') {
                  await _openChangeLarp();
                  return;
                }
                if (value == 'signout') {
                  try {
                    await auth.signOut();
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Sign out failed: $e')),
                    );
                  }
                }
              },
              itemBuilder: (BuildContext context) {
                final scheme = Theme.of(context).colorScheme;
                return [
                  PopupMenuItem<String>(
                    enabled: false,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      minLeadingWidth: 0,
                      leading: _ProfileAvatar(
                        user: widget.user,
                        radius: 22,
                        initials: _profileInitials(),
                      ),
                      title: Text(_profileDisplayName()),
                      subtitle: widget.user.email != null
                          ? Text(widget.user.email!)
                          : null,
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: 'changeLarp',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      minLeadingWidth: 36,
                      leading: Icon(Icons.swap_horiz, color: scheme.onSurface),
                      title: const Text('Change LARP'),
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'signout',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      minLeadingWidth: 36,
                      leading: Icon(Icons.logout, color: scheme.onSurface),
                      title: const Text('Sign out'),
                    ),
                  ),
                ];
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _ProfileAvatar(
                  user: widget.user,
                  radius: 18,
                  initials: _profileInitials(),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_currentLarpLabel != null &&
                  _currentLarpLabel!.trim().isNotEmpty) ...[
                Text(
                  'Current LARP',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  _currentLarpLabel!,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
              const SizedBox(height: 24),
              if (!_lmReady)
                LmIntegrationSetupPrompt(
                  readiness: _lmEvaluation?.readiness ??
                      LmIntegrationReadiness.notConfigured,
                  onOpenIntegration: _openLmIntegration,
                  errorDetail: _lmSetupErrorDetail,
                )
              else if (!_larpManagerRegistered)
                _LarpManagerRegistrationPrompt(
                  eventLink: _larpManagerEventLink,
                  checking: _checkingRegistration,
                  message: _registrationMessage,
                  onOpenRegistration: _openLarpManagerRegistration,
                  onCheckAgain: () =>
                      _refreshRegistrationStatus(forceRefresh: true),
                )
              else ...[
                if (!_hasCharacter && !_gameRole.canConfigureDeathRules) ...[
                  _LarpManagerCharacterPrompt(
                    eventLink: _larpManagerEventLink,
                    checking: _checkingRegistration,
                    message: _characterMessage,
                    onOpenCreate: _openLarpManagerCharacterCreate,
                    onCheckAgain: () =>
                        _refreshRegistrationStatus(forceRefresh: true),
                  ),
                  const SizedBox(height: 24),
                ],
                Row(
                  children: [
                    if (_gameRole.canConfigureDeathRules) ...[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RulesScreen(),
                            ),
                          ),
                          icon: const Icon(Icons.rule),
                          label: const Text('Rules'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RulesAidsScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.medical_information),
                        label: const Text('Rules Aid'),
                      ),
                    ),
                  ],
                ),
                if (_nfcHunts.any((h) => h.enabled)) ...[
                  const SizedBox(height: 12),
                  // Home entry: Scan hunt tag (gated on enabled hunts + active character).
                  NfcHuntScanScreen(
                    hunts: _nfcHunts,
                    activeCharacterId: _activeCharacterId,
                  ),
                ],
                if (_gameRole.canConfigureDeathRules) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const LarpManagerIntegrationScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.integration_instructions_outlined),
                      label: const Text('LM Integration'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const LarpManagerSyncSettingsScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.cloud_sync_outlined),
                      label: const Text('LarpManager sync'),
                    ),
                  ),
                ],
                if (_gameRole.canConfigureStaffIntegrations) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const HomeAssistantIntegrationScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.home_outlined),
                      label: const Text('Home Assistant'),
                    ),
                  ),
                ],
                if (_hasCharacter || _gameRole.canConfigureDeathRules) ...[
                const SizedBox(height: 32),
                if (_showLocationOptInPrompt) ...[
                  LocationOptInPrompt(
                    presenceRepository: _presenceRepo,
                    visible: true,
                    onOptInEnabled: () => unawaited(_syncLocationPings()),
                    onDismiss: () {
                      setState(() => _locationOptInPromptDismissed = true);
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                PlayerPresenceSettingsSection(
                  presenceRepository: _presenceRepo,
                  locationRulesRepository: _locationRulesRepo,
                  onPresenceUpdated: () => unawaited(_syncLocationPings()),
                ),
                const SizedBox(height: 24),
                Card(
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CharactersScreen(),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.person_outline,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Characters',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Spacer(),
                              Icon(
                                Icons.chevron_right,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Manage your character portfolio.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when the player has no LarpManager character for this event.
class _LarpManagerCharacterPrompt extends StatelessWidget {
  const _LarpManagerCharacterPrompt({
    required this.eventLink,
    required this.checking,
    required this.message,
    required this.onOpenCreate,
    required this.onCheckAgain,
  });

  final LarpManagerEventLink? eventLink;
  final bool checking;
  final String? message;
  final VoidCallback onOpenCreate;
  final VoidCallback onCheckAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasLink = eventLink != null;

    return Card(
      color: scheme.secondaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.person_add_outlined, color: scheme.secondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Create your character',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              message ??
                  (hasLink
                      ? 'You are registered, but no character is linked to your '
                          'registration on LarpManager yet. Create one there, '
                          'then return here.'
                      : 'This LARP is not linked to LarpManager yet. '
                          'Ask your organizer to complete LM Integration.'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (hasLink) ...[
              const SizedBox(height: 12),
              SelectableText(
                eventLink!.characterCreatePageUrl,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: hasLink && !checking ? onOpenCreate : null,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Create character on LarpManager'),
              ),
            ),
            const SizedBox(height: 8),
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
                label: const Text('Check character status'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the player is not on the LarpManager registration list for this event.
class _LarpManagerRegistrationPrompt extends StatelessWidget {
  const _LarpManagerRegistrationPrompt({
    required this.eventLink,
    required this.checking,
    required this.message,
    required this.onOpenRegistration,
    required this.onCheckAgain,
  });

  final LarpManagerEventLink? eventLink;
  final bool checking;
  final String? message;
  final VoidCallback onOpenRegistration;
  final VoidCallback onCheckAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasLink = eventLink != null;

    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.how_to_reg, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Register on LarpManager',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              message ??
                  (hasLink
                      ? 'You are not registered for this event on LarpManager yet. '
                          'Use the same email as RoleKeeper when you sign up.'
                      : 'This LARP is not linked to LarpManager yet. '
                          'Ask your organizer to complete LM Integration.'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (hasLink) ...[
              const SizedBox(height: 12),
              SelectableText(
                eventLink!.registrationPageUrl,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: hasLink && !checking ? onOpenRegistration : null,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Register on LarpManager'),
              ),
            ),
            const SizedBox(height: 8),
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
                label: const Text('Check registration status'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// App bar profile chip: LarpManager / Google [User.photoURL] or initials.
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.user,
    required this.initials,
    this.radius = 18,
  });

  final User user;
  final String initials;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textStyle = TextStyle(
      fontSize: radius * 0.9,
      fontWeight: FontWeight.w600,
      color: scheme.onPrimaryContainer,
    );
    final url = user.photoURL;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: scheme.primaryContainer,
        child: ClipOval(
          child: Image.network(
            url,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Text(initials, style: textStyle),
              );
            },
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: Text(initials, style: textStyle),
    );
  }
}
