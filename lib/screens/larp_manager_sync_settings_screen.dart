import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../services/game_context_service.dart';
import '../utils/error_reporting.dart';
import '../widgets/lm_integration_gate.dart';

/// Owner / superAdmin: manual LarpManager pull into Firestore.
class LarpManagerSyncSettingsScreen extends StatefulWidget {
  const LarpManagerSyncSettingsScreen({super.key});

  @override
  State<LarpManagerSyncSettingsScreen> createState() =>
      _LarpManagerSyncSettingsScreenState();
}

class _LarpManagerSyncSettingsScreenState
    extends State<LarpManagerSyncSettingsScreen> {
  bool _manualRunning = false;

  Future<void> _runManualSync() async {
    setState(() => _manualRunning = true);
    try {
      const region = 'us-central1';
      final callable = FirebaseFunctions.instanceFor(region: region)
          .httpsCallable('runLarpManagerSyncCallable');
      final gameId = GameContextService.instance.currentGameId;
      final result = await callable.call({'gameId': gameId});
      if (!mounted) return;
      final raw = result.data;
      final data =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final count = data['characterCount'];
      final errs = data['errors'] as List<dynamic>?;
      final msg = errs != null && errs.isNotEmpty
          ? 'Synced ($count chars); some detail errors — check summary in Firestore'
          : 'Synced ($count characters)';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e, st) {
      final report =
          reportAppError('LarpManagerSyncSettingsScreen.manualSync', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync failed: ${report.userMessage}')),
      );
    } finally {
      if (mounted) setState(() => _manualRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LmIntegrationGate(
      title: 'LarpManager sync',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('LarpManager sync'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Pull from LarpManager',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Configure base URL and credentials under Home → LM Integration first. '
              'Use Sync now to copy registrations and characters into Firestore for this event.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.35,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _manualRunning ? null : _runManualSync,
              icon: _manualRunning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text(_manualRunning ? 'Syncing…' : 'Sync now'),
            ),
          ],
        ),
      ),
    );
  }
}
