import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/preset_larps.dart';
import '../models/user_game_option.dart';
import '../services/auth_service.dart';
import '../services/game_context_service.dart';
import '../screens/larp_setup_flow_screen.dart';
import '../services/user_profile_service.dart';
import '../utils/larp_manager_instance_parser.dart';
import '../utils/qr_scanner.dart';

/// Choose or add a LARP (LarpManager instance). First-run uses [onFirstRunLarpChosen];
/// [switchMode] is for returning users (e.g. from home) and pops when done.
class LarpPickerScreen extends StatefulWidget {
  const LarpPickerScreen({
    super.key,
    required this.user,
    this.switchMode = false,
    this.onFirstRunLarpChosen,
  }) : assert(
          switchMode || onFirstRunLarpChosen != null,
          'First run must provide onFirstRunLarpChosen',
        );

  final User user;
  final bool switchMode;
  final VoidCallback? onFirstRunLarpChosen;

  @override
  State<LarpPickerScreen> createState() => _LarpPickerScreenState();
}

class _LarpPickerScreenState extends State<LarpPickerScreen> {
  final _profile = UserProfileService();
  bool _busy = false;
  late final Future<List<UserGameOption>> _optionsFuture;

  @override
  void initState() {
    super.initState();
    _optionsFuture = widget.switchMode
        ? _profile.listConfiguredLarpsForSwitcher()
        : Future.value(const <UserGameOption>[]);
  }

  Future<void> _finishAfterSelectingGame(String gameId) async {
    await _profile.setActiveTenantKey(gameId);
    GameContextService.instance.selectGame(gameId);
    if (!mounted) return;
    if (widget.switchMode) {
      Navigator.pop(context, true);
    } else {
      widget.onFirstRunLarpChosen!();
    }
  }

  Future<void> _applyTarget(LarpManagerInstanceTarget target) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          fullscreenDialog: true,
          builder: (ctx) => LarpSetupFlowScreen(
            user: widget.user,
            target: target,
          ),
        ),
      );
      if (!mounted) return;
      if (ok == true) {
        if (widget.switchMode) {
          Navigator.pop(context, true);
        } else {
          widget.onFirstRunLarpChosen!();
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add LARP: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onAddLarpPressed() async {
    if (!mounted) return;
    final choice = await showModalBottomSheet<_AddLarpChoice>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner_outlined),
              title: const Text('Scan QR code'),
              onTap: () => Navigator.pop(ctx, _AddLarpChoice.scan),
            ),
            ListTile(
              leading: const Icon(Icons.language_outlined),
              title: const Text('Enter domain'),
              onTap: () => Navigator.pop(ctx, _AddLarpChoice.domain),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;

    switch (choice) {
      case _AddLarpChoice.scan:
        final raw = await scanQrCode(
          context,
          options: const QrScannerOptions(
            title: 'Scan LARP',
            instructionText: 'Scan the QR for your LarpManager instance or event',
          ),
        );
        if (!mounted || raw == null) return;
        final target = parseLarpManagerInstance(raw);
        if (target == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('That QR code is not a valid URL or domain'),
            ),
          );
          return;
        }
        await _applyTarget(target);
      case _AddLarpChoice.domain:
        final raw = await showDialog<String>(
          context: context,
          builder: (ctx) {
            final controller = TextEditingController();
            return AlertDialog(
              title: const Text('LarpManager domain'),
              content: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'e.g. events.example.com or https://…',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => Navigator.pop(ctx, controller.text),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, controller.text),
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
        if (!mounted || raw == null || raw.trim().isEmpty) return;
        final target = parseLarpManagerInstance(raw);
        if (target == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Enter a valid domain or URL'),
            ),
          );
          return;
        }
        await _applyTarget(target);
    }
  }

  Future<void> _signOut() async {
    final auth = AuthService();
    try {
      await auth.signOut();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign out failed: $e')),
      );
    }
  }

  Future<void> _onPreset(PresetLarp preset) async {
    final target = LarpManagerInstanceTarget(
      baseUrl: preset.baseUrl,
      eventSlug: preset.eventSlug,
      displayNameForProfile: preset.label,
    );
    await _applyTarget(target);
  }

  Widget _quickAddRow(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _busy ? null : () => _onPreset(kPresetCrucible),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            child: Text(
              kPresetCrucible.label,
              style: theme.textTheme.labelMedium,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: _busy ? null : () => _onPreset(kPresetRuinedEarth),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            child: Text(
              kPresetRuinedEarth.label,
              style: theme.textTheme.labelMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.switchMode) {
      final currentId = GameContextService.instance.currentGameId;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Change LARP'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _busy ? null : _signOut,
              tooltip: 'Sign out',
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Your LARPs',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                FutureBuilder<List<UserGameOption>>(
                  future: _optionsFuture,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final options = snap.data ?? [];
                    if (options.isEmpty) {
                      return Text(
                        'No LARPs yet — add one below.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      );
                    }
                    return Column(
                      children: options
                          .map(
                            (o) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(o.label),
                              subtitle: Text(
                                o.tenantKey,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              trailing: o.tenantKey == currentId
                                  ? Icon(
                                      Icons.check_circle,
                                      color: theme.colorScheme.primary,
                                    )
                                  : null,
                              onTap: _busy
                                  ? null
                                  : () => _finishAfterSelectingGame(o.tenantKey),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Add another LARP',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _onAddLarpPressed,
                  child: const Text('Add LARP'),
                ),
                const SizedBox(height: 12),
                const FilledButton(
                  onPressed: null,
                  child: Text('New LARP'),
                ),
                const SizedBox(height: 24),
                Text(
                  'Quick add',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                _quickAddRow(theme),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('RoleKeeper'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _busy ? null : _signOut,
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'No LARPs selected',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Choose a LarpManager instance to continue.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _busy ? null : _onAddLarpPressed,
                child: const Text('Add LARP'),
              ),
              const SizedBox(height: 12),
              const FilledButton(
                onPressed: null,
                child: Text('New LARP'),
              ),
              const Spacer(),
              Text(
                'Quick add',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              _quickAddRow(theme),
            ],
          ),
        ),
      ),
    );
  }
}

enum _AddLarpChoice { scan, domain }
