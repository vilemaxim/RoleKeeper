import 'package:cloud_functions/cloud_functions.dart';

import '../models/activity_event.dart';
import '../models/game_tenant_ref.dart';
import 'game_context_service.dart';

/// Outcome from the `recordNfcHuntScan` callable (ADR 007).
enum NfcHuntScanOutcome {
  credited,
  alreadyScanned,
  unknownTag,
}

/// Parsed result of a player hunt-tag scan.
class NfcHuntScanResult {
  const NfcHuntScanResult({
    required this.outcome,
    this.scanId,
  });

  final NfcHuntScanOutcome outcome;
  final String? scanId;

  static NfcHuntScanResult fromMap(Map<String, dynamic> data) {
    final raw = data['outcome'];
    final outcome = switch (raw) {
      'already_scanned' => NfcHuntScanOutcome.alreadyScanned,
      'unknown_tag' => NfcHuntScanOutcome.unknownTag,
      _ => NfcHuntScanOutcome.credited,
    };
    final scanId = data['scanId'];
    return NfcHuntScanResult(
      outcome: outcome,
      scanId: scanId is String && scanId.isNotEmpty ? scanId : null,
    );
  }
}

/// Client for the `recordNfcHuntScan` callable (no direct Firestore writes).
class NfcHuntScanService {
  NfcHuntScanService({
    FirebaseFunctions? functions,
    GameTenantRef? tenant,
  })  : _functions = functions ?? FirebaseFunctions.instance,
        _tenant = tenant ?? GameContextService.instance.currentTenant;

  final FirebaseFunctions _functions;
  final GameTenantRef? _tenant;

  GameTenantRef get _resolvedTenant {
    final t = _tenant;
    if (t == null) throw StateError('No game selected');
    return t;
  }

  /// Credits a scan (or returns already_scanned / unknown_tag) via callable.
  Future<NfcHuntScanResult> recordScan({
    required String huntId,
    required String characterId,
    required String tagUid,
    ActivityEventLocation? location,
    DateTime? clientScannedAt,
    bool queuedOffline = false,
  }) async {
    final tenant = _resolvedTenant;
    final callable = _functions.httpsCallable('recordNfcHuntScan');
    final body = <String, dynamic>{
      'gameId': tenant.tenantKey,
      'huntId': huntId,
      'characterId': characterId,
      'tagUid': tagUid,
      if (location != null) 'location': location.toMap(),
      if (clientScannedAt != null)
        'clientScannedAt': clientScannedAt.toUtc().toIso8601String(),
      if (queuedOffline) 'queuedOffline': true,
    };
    final result = await callable.call<Map<String, dynamic>>(body);
    return NfcHuntScanResult.fromMap(result.data);
  }
}
