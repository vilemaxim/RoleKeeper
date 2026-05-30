import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/larp_join_helper.dart';
import '../utils/error_reporting.dart';
import '../services/larp_manager_registration_service.dart';
import '../services/larp_registry_repository.dart';
import '../utils/larp_manager_instance_parser.dart';

/// After picking a LarpManager URL, joins the tenant and verifies organizer status
/// from LarpManager (by email). Organizers see LM integration guidance.
class LarpSetupFlowScreen extends StatefulWidget {
  const LarpSetupFlowScreen({
    super.key,
    required this.user,
    required this.target,
  });

  final User user;
  final LarpManagerInstanceTarget target;

  @override
  State<LarpSetupFlowScreen> createState() => _LarpSetupFlowScreenState();
}

class _LarpSetupFlowScreenState extends State<LarpSetupFlowScreen> {
  final _registryRepo = LarpRegistryRepository();
  final _registrationService = LarpManagerRegistrationService();
  bool _loading = true;
  bool _finishing = false;
  String? _error;
  bool _showOrganizerGuide = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tenant = widget.target.tenant;
      if (tenant == null) {
        setState(() {
          _error = 'Enter a LarpManager URL that includes an event (e.g. …/crucible)';
          _loading = false;
        });
        return;
      }

      final r = await _registryRepo.get(tenant);
      if (r != null && r.organizerAccessConfigured) {
        await _completeJoinOnly();
        return;
      }

      await joinLarpAndSaveUserProfile(widget.target);

      var isOrganizer = false;
      try {
        final access = await _registrationService.verifyRegistration(
          tenant.tenantKey,
        );
        isOrganizer = access.isOrganizer;
      } catch (_) {
        // LM integration not configured yet — continue as player.
      }

      if (!mounted) return;

      if (isOrganizer && (r == null || !r.organizerAccessConfigured)) {
        setState(() {
          _loading = false;
          _showOrganizerGuide = true;
        });
        return;
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _completeJoinOnly() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await joinLarpAndSaveUserProfile(widget.target);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _onOrganizerFinished() async {
    setState(() => _finishing = true);
    try {
      final tenant = widget.target.tenant!;
      await _registryRepo.markOrganizerAccessConfigured(
        tenant: tenant,
        larpManagerBaseUrl: widget.target.baseUrl,
        larpManagerEventSlug: widget.target.normalizedEventSlug,
        displayName: widget.target.resolvedDisplayName,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e, st) {
      final report =
          reportAppError('LarpSetupFlowScreen.organizerFinished', e, st);
      if (!mounted) return;
      setState(() => _finishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not finish setup: ${report.userMessage}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slug = widget.target.eventSlug.isEmpty
        ? '(root — use LM Integration to set event slug if needed)'
        : widget.target.eventSlug;

    if (_error != null && !_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('LARP setup')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _loading = true;
                    });
                    _load();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_loading || _finishing) {
      return Scaffold(
        appBar: AppBar(title: const Text('LARP setup')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_showOrganizerGuide) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Organizer setup'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, true),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'LarpManager service account',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your LarpManager account is listed as an event organizer. '
              'Set up the RoleKeeper sync account so players can verify registration.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text('LarpManager base URL', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            SelectableText(
              widget.target.baseUrl,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Text('Event path (slug)', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            SelectableText(slug, style: theme.textTheme.titleMedium),
            const SizedBox(height: 20),
            _bullet(theme, '1', 'Create a dedicated LarpManager account for RoleKeeper '
                '(sign up on your LM site — organizers cannot add users from admin). '
                'Share your org link, register that account for this event, then assign '
                'it an event role with registration and character export permissions.'),
            _bullet(theme, '2', 'Open LM Integration on RoleKeeper home and follow '
                'the setup steps: same base URL and event slug as above, plus that '
                'account’s username and password (stored in Secret Manager).'),
            _bullet(theme, '3', 'Players are checked against LarpManager by '
                'email when they open RoleKeeper — no manual confirmation.'),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _finishing ? null : _onOrganizerFinished,
              child: const Text('Continue — I’ve set up LarpManager'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bullet(ThemeData theme, String n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$n. ', style: theme.textTheme.bodyLarge),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}
