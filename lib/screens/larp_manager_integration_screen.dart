import 'package:flutter/material.dart';

import '../services/game_context_service.dart';
import '../services/larp_manager_integration_repository.dart';
import '../services/larp_manager_integration_save_service.dart';
import '../services/larp_manager_integration_status_service.dart';
import '../services/larp_manager_registration_service.dart';
import '../utils/error_reporting.dart';

/// Organizer setup: LarpManager connection + dedicated service account credentials.
///
/// Task 012 (`docs/adr/0001-remove-fetchdetails-toggle.md`) removed the
/// "Fetch inventory & abilities JSON" toggle that used to live in the
/// Advanced options expander. Admin sync is always full; there is no
/// per-game knob.
class LarpManagerIntegrationScreen extends StatefulWidget {
  const LarpManagerIntegrationScreen({
    super.key,
    this.repository,
  });

  /// Optional injection point so widget tests can drive the screen
  /// against a [FakeFirebaseFirestore]-backed repository without
  /// booting Firebase. Production callers pass `null` and the screen
  /// builds the default singleton-backed repository in [State.initState].
  final LarpManagerIntegrationRepository? repository;

  @override
  State<LarpManagerIntegrationScreen> createState() =>
      _LarpManagerIntegrationScreenState();
}

class _LarpManagerIntegrationScreenState
    extends State<LarpManagerIntegrationScreen> {
  late final LarpManagerIntegrationRepository _repo =
      widget.repository ?? LarpManagerIntegrationRepository();
  final _baseUrl = TextEditingController();
  final _eventSlug = TextEditingController();
  final _loginPath = TextEditingController(text: '/login/');
  final _username = TextEditingController();
  final _password = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _hadCredentials = false;
  bool _advancedExpanded = false;
  String? _feedbackMessage;
  bool _feedbackIsError = false;

  // `_saveService` and `_statusService` are intentionally `late final`
  // so the Firebase-backed defaults aren't instantiated until Save is
  // actually pressed. The screen's initial render and `_load()` only
  // need `_repo`; widget tests can therefore render the screen with an
  // injected `repository:` and a `FakeFirebaseFirestore`-backed repo
  // without booting Firebase.
  late final _saveService = LarpManagerIntegrationSaveService();
  late final _statusService = LarpManagerIntegrationStatusService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _eventSlug.dispose();
    _loginPath.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _feedbackMessage = null;
    });
    try {
      final c = await _repo.get();
      var baseUrl = c.baseUrl;
      var eventSlug = c.eventSlug;
      if (baseUrl.isEmpty || eventSlug.isEmpty) {
        final link =
            await LarpManagerRegistrationService().getEventLinkForTenant(
          GameContextService.instance.currentTenantKey,
        );
        if (link != null) {
          baseUrl = baseUrl.isEmpty ? link.baseUrl : baseUrl;
          eventSlug = eventSlug.isEmpty ? link.eventSlug : eventSlug;
        }
      }
      if (!mounted) return;
      final loginPath = c.loginPath.isNotEmpty ? c.loginPath : '/login/';
      setState(() {
        _baseUrl.text = baseUrl;
        _eventSlug.text = eventSlug;
        _loginPath.text = loginPath;
        _hadCredentials = c.credentialsConfigured;
        _advancedExpanded = loginPath != '/login/';
        _loading = false;
      });
    } catch (e, st) {
      final report = reportAppError('LarpManagerIntegrationScreen.load', e, st);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _feedbackMessage = 'Could not load settings: ${report.userMessage}';
        _feedbackIsError = true;
      });
      _showSnackBar(_feedbackMessage!, isError: true);
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? scheme.error : null,
        duration: Duration(seconds: isError ? 10 : 5),
      ),
    );
  }

  void _setFeedback(String message, {required bool isError}) {
    setState(() {
      _feedbackMessage = message;
      _feedbackIsError = isError;
    });
    _showSnackBar(message, isError: isError);
  }

  Future<void> _finishSaveSuccess() async {
    logInfoToTerminal(
      'LarpManagerIntegrationScreen.save',
      'LarpManager integration saved successfully',
    );
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(Icons.check_circle_outline, color: scheme.primary, size: 40),
        title: const Text('LarpManager connected'),
        content: const Text(
          'Your connection and credentials are saved, and RoleKeeper verified '
          'it can reach LarpManager.\n\n'
          'Next: on Home, open LarpManager sync and tap Sync now '
          'to pull registrations and characters.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.pop(context, true);
            },
            child: const Text('Back to Home'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final baseUrl = _baseUrl.text.trim();
    final eventSlug = _eventSlug.text.trim();
    if (baseUrl.isEmpty || eventSlug.isEmpty) {
      _setFeedback('Base URL and event slug are required', isError: true);
      return;
    }

    final u = _username.text.trim();
    final p = _password.text;
    if (u.isNotEmpty != p.isNotEmpty) {
      _setFeedback(
        'Enter both username and password, or leave both empty to keep saved credentials',
        isError: true,
      );
      return;
    }
    if (!_hadCredentials && (u.isEmpty || p.isEmpty)) {
      _setFeedback(
        'Enter the service account username and password from LarpManager',
        isError: true,
      );
      return;
    }

    final tenant = GameContextService.instance.currentTenant;
    if (tenant == null) {
      _setFeedback(
        'No LARP selected — pick a LARP from home first',
        isError: true,
      );
      return;
    }

    setState(() {
      _saving = true;
      _feedbackMessage = null;
      _feedbackIsError = false;
    });
    try {
      await _saveService.save(
        tenant: tenant,
        baseUrl: baseUrl,
        larpManagerEventSlug: eventSlug,
        loginPath: _loginPath.text.trim().isEmpty
            ? '/login/'
            : _loginPath.text.trim(),
        username: u.isNotEmpty ? u : null,
        password: p.isNotEmpty ? p : null,
      );
      if (!mounted) return;
      _password.clear();
      setState(() {
        _hadCredentials = true;
        _feedbackMessage = 'Saved. Verifying LarpManager connection…';
        _feedbackIsError = false;
      });

      final evaluation = await _statusService.evaluate(forceSync: true);
      if (!mounted) return;
      if (!evaluation.isReady) {
        final err = evaluation.lastError ??
            Exception('LarpManager connection could not be verified');
        final report = reportAppError(
          'LarpManagerIntegrationScreen.verify',
          err,
        );
        _setFeedback(
          'Settings saved, but LarpManager is not working yet: ${report.userMessage}',
          isError: true,
        );
        return;
      }

      await _finishSaveSuccess();
    } catch (e, st) {
      final report = reportAppError('LarpManagerIntegrationScreen.save', e, st);
      if (!mounted) return;
      _setFeedback('Save failed: ${report.userMessage}', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _loginTestUrl {
    final base = _baseUrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    var path = _loginPath.text.trim();
    if (path.isEmpty) path = '/login/';
    if (!path.startsWith('/')) path = '/$path';
    return '$base$path';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('LM Integration'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _loading ? null : _save,
              child: const Text('Save'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
              children: [
                if (_feedbackMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Material(
                      color: _feedbackIsError
                          ? scheme.errorContainer
                          : scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _feedbackIsError
                                  ? Icons.error_outline
                                  : Icons.info_outline,
                              color: _feedbackIsError
                                  ? scheme.onErrorContainer
                                  : scheme.onPrimaryContainer,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _feedbackMessage!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: _feedbackIsError
                                      ? scheme.onErrorContainer
                                      : scheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: LinearProgressIndicator(),
                  ),
                Card(
                  color: scheme.primaryContainer.withValues(alpha: 0.35),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Create a LarpManager service account',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'RoleKeeper uses a dedicated LarpManager login (not your '
                          'personal account) so the server can export registrations and '
                          'characters. LarpManager does not let organizers create user '
                          'accounts from the admin panel — the export account must sign up '
                          'and register like any player, then you assign permissions.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _SetupStep(
                          number: '1',
                          title: 'Create a LarpManager account for RoleKeeper',
                          body:
                              'Sign up on your LarpManager site with a dedicated email '
                              '(e.g. rolekeeper-export@yourgame.invalid). Use a strong '
                              'password you can rotate later — not your personal organizer '
                              'login. This must be a real LM user account; admins cannot '
                              'add users without that person registering first.',
                        ),
                        _SetupStep(
                          number: '2',
                          title: 'Share the organization & register for the event',
                          body:
                              'Share your organization link so that account can grant '
                              'data-sharing permission. Then have it register for this '
                              'event (open registration on the event) so it appears on '
                              'the participant list — same as any player signup.',
                        ),
                        _SetupStep(
                          number: '3',
                          title: 'Assign an event role with export access',
                          body:
                              'In Event → Roles, add that user to a role with permissions '
                              'for registration export, character export, and related '
                              'manage pages your host requires. You can use Organizer or a '
                              'custom staff/export role; RoleKeeper only needs export access, '
                              'not full organizer UI.',
                        ),
                        _SetupStep(
                          number: '4',
                          title: 'Confirm sign-in works',
                          body:
                              'Sign in to LarpManager in a browser as that account. If login '
                              'fails, ask your LM host which login URL they use — you may '
                              'need to change Login path under Advanced below '
                              '(default /login/).',
                        ),
                        _SetupStep(
                          number: '5',
                          title: 'Enter details below and Save',
                          body:
                              'Paste the same base URL and event slug as this LARP, then '
                              'the service account username and password. Credentials are '
                              'stored in Google Secret Manager, not Firestore.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Event connection',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Must match the LarpManager instance and event run players use.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _baseUrl,
                  decoration: const InputDecoration(
                    labelText: 'LarpManager base URL',
                    hintText: 'https://yourorg.larpmanager.com',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _eventSlug,
                  decoration: const InputDecoration(
                    labelText: 'Event (run) slug',
                    hintText: 'crucible',
                    border: OutlineInputBorder(),
                  ),
                  autocorrect: false,
                ),
                const Divider(height: 40),
                Text(
                  'Service account',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (_hadCredentials)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Credentials are saved. Leave username and password empty to keep '
                      'them, or enter both to replace.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  Text(
                    'Username and password for the dedicated LarpManager user from step 1.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _username,
                  decoration: const InputDecoration(
                    labelText: 'Service account username',
                    border: OutlineInputBorder(),
                  ),
                  autocorrect: false,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  decoration: const InputDecoration(
                    labelText: 'Service account password',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  autocorrect: false,
                ),
                const SizedBox(height: 8),
                Text(
                  'Password must not contain ":". After saving, run LarpManager sync '
                  'from home to pull characters.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                ExpansionTile(
                  initiallyExpanded: _advancedExpanded,
                  onExpansionChanged: (v) =>
                      setState(() => _advancedExpanded = v),
                  title: const Text('Advanced options'),
                  subtitle: const Text('Login path'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        'Login path is a per-event setting (stored with this game). '
                        'RoleKeeper posts to {base URL}{login path} when signing in as '
                        'the service account. Default /login/ works for most LarpManager '
                        'sites; use /accounts/login/ only if your host says so.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _loginPath,
                        decoration: const InputDecoration(
                          labelText: 'Login path',
                          hintText: '/login/',
                          border: OutlineInputBorder(),
                        ),
                        autocorrect: false,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (_baseUrl.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SelectableText(
                          'Test URL: $_loginTestUrl',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ],
            ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 24,
                  child: SafeArea(
                    child: FilledButton(
                      onPressed: _saving || _loading ? null : _save,
                      child: _saving
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text('Saving…'),
                              ],
                            )
                          : const Text('Save integration'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SetupStep extends StatelessWidget {
  const _SetupStep({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            child: Text(
              number,
              style: theme.textTheme.labelMedium,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
