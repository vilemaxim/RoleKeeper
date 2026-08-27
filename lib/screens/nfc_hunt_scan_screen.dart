import 'package:flutter/material.dart';

import '../models/activity_event.dart';
import '../models/nfc_hunt.dart';
import '../services/game_context_service.dart';
import '../services/nfc_hunt_offline_queue_service.dart';
import '../services/nfc_hunt_scan_service.dart';
import '../utils/active_events_utils.dart';
import '../utils/error_reporting.dart';
import '../utils/qr_scanner.dart' as qr;
import '../utils/scavenger_hunt_qr_parser.dart';

typedef ScanQrCodeFn = Future<String?> Function(BuildContext context);
typedef CaptureLocationFn = Future<ActivityEventLocation?> Function();

/// Player scavenger-hunt tag scan entry and online credit flow.
///
/// Shows “Scan hunt tag” when [hunts] contains at least one enabled hunt.
/// Requires [activeCharacterId]; otherwise shows the shared character gate copy.
class NfcHuntScanScreen extends StatelessWidget {
  const NfcHuntScanScreen({
    super.key,
    required this.hunts,
    this.activeCharacterId,
    this.scanService,
    this.offlineQueue,
    this.expectedTenantKey,
    this.scanQrCode,
    this.captureLocation,
  });

  final List<NfcHunt> hunts;
  final String? activeCharacterId;
  final NfcHuntScanService? scanService;
  final NfcHuntOfflineQueueService? offlineQueue;
  final String? expectedTenantKey;
  final ScanQrCodeFn? scanQrCode;
  final CaptureLocationFn? captureLocation;

  static const noCharacterMessage = 'Select or create a character first';
  static const scanButtonLabel = 'Scan hunt tag';
  static const creditedMessage = 'Tag credited successfully';
  static const alreadyScannedMessage = 'You already scanned this tag';
  static const unknownTagMessage =
      'Unknown tag — take a photo in case plot needs it';

  bool get _hasEnabledHunt => hunts.any((h) => h.enabled);

  bool get _hasActiveCharacter =>
      activeCharacterId != null && activeCharacterId!.trim().isNotEmpty;

  String get _tenantKey =>
      expectedTenantKey ??
      GameContextService.instance.currentTenant?.tenantKey ??
      '';

  Future<void> _performScan(BuildContext context) async {
    final characterId = activeCharacterId?.trim();
    if (characterId == null || characterId.isEmpty) return;

    final scan = scanQrCode ??
        (BuildContext ctx) => qr.scanQrCode(
              ctx,
              options: const qr.QrScannerOptions(
                title: 'Scan hunt tag',
                instructionText: 'Scan the QR code on the hunt tag',
              ),
            );

    final raw = await scan(context);
    if (!context.mounted || raw == null) return;

    final parsed = parseScavengerHuntQr(
      raw,
      expectedTenantKey: _tenantKey.isEmpty ? null : _tenantKey,
    );
    if (parsed == null) {
      final message = raw.contains('rolekeeper:scavenger:') &&
              _tenantKey.isNotEmpty &&
              !raw.contains(_tenantKey)
          ? 'QR code is for a different tenant'
          : 'Invalid scavenger hunt QR code';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }

    final huntEnabled = hunts.any((h) => h.id == parsed.huntId && h.enabled);
    if (!huntEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This hunt is not enabled')),
      );
      return;
    }

    final capture = captureLocation ?? ActiveEventsUtils.captureLocationForEvent;
    ActivityEventLocation? location;
    try {
      location = await capture();
    } catch (_) {
      location = null;
    }
    if (!context.mounted) return;

    final service = scanService ?? NfcHuntScanService();
    final queue = offlineQueue ?? NfcHuntOfflineQueueService();
    try {
      final submit = await service.submitScan(
        huntId: parsed.huntId,
        characterId: characterId,
        tagUid: parsed.tagUid,
        location: location,
        clientScannedAt: DateTime.now().toUtc(),
        rawQrPayload: raw,
        offlineQueue: queue,
      );
      if (!context.mounted) return;
      if (submit.savedOffline) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(submit.userMessage)),
        );
        return;
      }
      _showOutcome(context, submit.result!);
    } catch (e, st) {
      if (!context.mounted) return;
      final report = reportAppError('NfcHuntScanScreen.recordScan', e, st);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(report.userMessage)),
      );
    }
  }

  void _showOutcome(BuildContext context, NfcHuntScanResult result) {
    final message = switch (result.outcome) {
      NfcHuntScanOutcome.credited => creditedMessage,
      NfcHuntScanOutcome.alreadyScanned => alreadyScannedMessage,
      NfcHuntScanOutcome.unknownTag => unknownTagMessage,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasEnabledHunt) {
      return const SizedBox.shrink();
    }

    final enabled = _hasActiveCharacter;
    final button = FilledButton.tonalIcon(
      onPressed: enabled ? () => _performScan(context) : null,
      icon: const Icon(Icons.qr_code_scanner),
      label: const Text(scanButtonLabel),
    );

    if (enabled) {
      return SizedBox(width: double.infinity, child: button);
    }

    return SizedBox(
      width: double.infinity,
      child: Tooltip(
        message: noCharacterMessage,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            button,
            const SizedBox(height: 8),
            Text(
              noCharacterMessage,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
