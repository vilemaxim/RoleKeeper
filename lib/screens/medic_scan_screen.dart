import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/activity_events_service.dart';
import '../services/death_intervention_secrets_service.dart';
import '../services/rules_repository.dart';
import 'medic_offline_intervention_screen.dart';
import '../services/death_intervention_claims_service.dart';
import '../utils/death_qr_parser.dart';
import '../utils/qr_scanner.dart';

String _capitalize(String s) {
  if (s.isEmpty) return s;
  return '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';
}

/// Intervener (medic/healer) scans fallen player's QR codes: first to claim intervention, second to confirm revival.
class MedicScanScreen extends StatefulWidget {
  const MedicScanScreen({super.key});

  @override
  State<MedicScanScreen> createState() => _MedicScanScreenState();
}

enum _MedicPhase { idle, claimed, confirming }

class _MedicScanScreenState extends State<MedicScanScreen> {
  final _claimsService = DeathInterventionClaimsService();
  final _eventsService = ActivityEventsService();
  final _secretsService = DeathInterventionSecretsService();

  _MedicPhase _phase = _MedicPhase.idle;
  String? _error;
  String _roleName = 'medic';
  String? _qrSigningSecret;

  @override
  void initState() {
    super.initState();
    _loadRules();
    _loadSigningSecret();
  }

  Future<void> _loadSigningSecret() async {
    try {
      final secrets = await _secretsService.resolveSecrets();
      if (mounted) setState(() => _qrSigningSecret = secrets?.qrSigningSecret);
    } catch (_) {
      // Offline until secrets were cached while online.
    }
  }

  Future<void> _loadRules() async {
    final rules = await RulesRepository().getDeathRules();
    if (mounted) setState(() => _roleName = rules.interventionRoleName);
  }

  Future<void> _performScan() async {
    setState(() => _error = null);

    final raw = await scanQrCode(
      context,
      options: QrScannerOptions(
        title: '${_capitalize(_roleName)} – Scan QR',
        instructionText: 'Scan the QR code on the fallen player\'s screen',
        validate: isDeathInterventionQr,
      ),
    );

    if (!mounted) return;
    if (raw == null) return; // User cancelled

    setState(() => _error = null);

    final signingSecret = _qrSigningSecret;
    if (signingSecret == null || signingSecret.isEmpty) {
      setState(() => _error = 'Connect online once to verify medic QR codes.');
      return;
    }

    if (!verifyDeathInterventionQr(raw, signingSecret: signingSecret)) {
      setState(() => _error = 'Invalid or unsigned QR code');
      return;
    }

    final parsed = parseDeathInterventionQr(raw, signingSecret: signingSecret);
    if (parsed == null) {
      setState(() => _error = 'Invalid QR code');
      return;
    }

    try {
      if (isDeathInterventionMedicQr(raw)) {
        await _claimIntervention(parsed);
      } else if (isDeathInterventionRevivalConfirmQr(raw)) {
        await _confirmRevival(parsed);
      }
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _claimIntervention(DeathQrParsed parsed) async {
    if (parsed.activityEventId.isEmpty) {
      throw StateError('Invalid QR: missing event ID');
    }

    final medicId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (medicId.isEmpty) throw StateError('Not signed in');

    await _claimsService.claimIntervention(
      activityEventId: parsed.activityEventId,
      fallenPlayerId: parsed.fallenPlayerId,
    );
    await _eventsService.recordDeathTimeStopped(
      injuredPlayerId: parsed.fallenPlayerId,
      medicPlayerId: medicId,
      activityEventId: parsed.activityEventId,
      fallenShortId: parsed.shortId,
    );

    if (mounted) setState(() => _phase = _MedicPhase.claimed);
  }

  Future<void> _confirmRevival(DeathQrParsed parsed) async {
    if (parsed.activityEventId.isEmpty) {
      throw StateError('Invalid QR: missing event ID');
    }

    await _claimsService.confirmRevival(parsed.activityEventId);

    if (mounted) setState(() => _phase = _MedicPhase.confirming);
  }

  void _reset() {
    setState(() {
      _phase = _MedicPhase.idle;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${_capitalize(_roleName)} – Scan QR'),
      ),
      body: _phase == _MedicPhase.idle ? _buildIdle() : _buildResult(),
    );
  }

  Widget _buildIdle() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Icon(
              Icons.qr_code_scanner,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Scan QR codes to help fallen players',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'First scan: claim intervention and stop the death count.\n'
              'Second scan: confirm you stayed near when revival completes.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            if (_error != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const Spacer(),
            FilledButton.icon(
              onPressed: _performScan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR code'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MedicOfflineInterventionScreen(),
                ),
              ),
              icon: const Icon(Icons.signal_cellular_off),
              label: const Text('Offline mode'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final isClaimed = _phase == _MedicPhase.claimed;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isClaimed ? Icons.medical_services : Icons.check_circle,
              size: 80,
              color: isClaimed
                  ? Theme.of(context).colorScheme.primary
                  : Colors.green,
            ),
            const SizedBox(height: 24),
            Text(
              isClaimed ? 'Intervention started' : 'Revival confirmed',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              isClaimed
                  ? 'Stay with the player until the revival countdown finishes. '
                    'Then scan the second QR to confirm you stayed near.'
                  : 'The player has been revived.',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () {
                _reset();
                _performScan();
              },
              child: const Text('Scan another'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
