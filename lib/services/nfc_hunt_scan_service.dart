import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';

import '../models/activity_event.dart';
import '../models/game_tenant_ref.dart';
import 'game_context_service.dart';
import 'nfc_hunt_offline_queue_service.dart';

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

/// Result of [NfcHuntScanService.submitScan] (online or queued).
class NfcHuntScanSubmitResult {
  const NfcHuntScanSubmitResult._({
    required this.savedOffline,
    this.result,
    required this.userMessage,
  });

  factory NfcHuntScanSubmitResult.online(NfcHuntScanResult result) =>
      NfcHuntScanSubmitResult._(
        savedOffline: false,
        result: result,
        userMessage: '',
      );

  factory NfcHuntScanSubmitResult.queued() => const NfcHuntScanSubmitResult._(
        savedOffline: true,
        userMessage: NfcHuntScanService.offlineSavedMessage,
      );

  final bool savedOffline;
  final NfcHuntScanResult? result;
  final String userMessage;
}

/// Summary of a FIFO offline-queue drain attempt.
class NfcHuntQueueDrainSummary {
  const NfcHuntQueueDrainSummary({
    required this.syncedCount,
    required this.failedCount,
  });

  final int syncedCount;
  final int failedCount;
}

/// Client for the `recordNfcHuntScan` callable (no direct Firestore writes).
class NfcHuntScanService {
  NfcHuntScanService({
    FirebaseFunctions? functions,
    GameTenantRef? tenant,
    String Function()? localIdGenerator,
  })  : _functions = functions ?? FirebaseFunctions.instance,
        _tenant = tenant ?? GameContextService.instance.currentTenant,
        _localIdGenerator = localIdGenerator ?? _defaultLocalId;

  static const offlineSavedMessage = 'Saved — will sync when online';

  final FirebaseFunctions _functions;
  final GameTenantRef? _tenant;
  final String Function() _localIdGenerator;

  static String _defaultLocalId() {
    final ms = DateTime.now().toUtc().millisecondsSinceEpoch;
    final tie = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return '${ms}_$tie';
  }

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

  /// Online scan with offline enqueue fallback on retryable network errors.
  Future<NfcHuntScanSubmitResult> submitScan({
    required String huntId,
    required String characterId,
    required String tagUid,
    ActivityEventLocation? location,
    DateTime? clientScannedAt,
    String? rawQrPayload,
    required NfcHuntOfflineQueueService offlineQueue,
  }) async {
    final scannedAt = (clientScannedAt ?? DateTime.now()).toUtc();
    try {
      final result = await recordScan(
        huntId: huntId,
        characterId: characterId,
        tagUid: tagUid,
        location: location,
        clientScannedAt: clientScannedAt,
      );
      return NfcHuntScanSubmitResult.online(result);
    } on FirebaseFunctionsException catch (e) {
      if (!_isRetryableNetworkError(e)) rethrow;
      final tenant = _resolvedTenant;
      await offlineQueue.enqueue(
        PendingNfcHuntScan(
          localId: _localIdGenerator(),
          tenantKey: tenant.tenantKey,
          huntId: huntId,
          tagUid: tagUid,
          characterId: characterId,
          clientScannedAt: scannedAt,
          location: location,
          rawQrPayload: rawQrPayload,
        ),
      );
      return NfcHuntScanSubmitResult.queued();
    }
  }

  /// Drains [queue] FIFO via [recordScan] with `queuedOffline: true`.
  ///
  /// Removes an entry only after a successful callable response. On the first
  /// retryable failure, stops and retains that item and all later ones.
  Future<NfcHuntQueueDrainSummary> drainOfflineQueue(
    NfcHuntOfflineQueueService queue,
  ) async {
    var synced = 0;
    var failed = 0;
    final pending = await queue.loadPending();
    for (final item in pending) {
      try {
        await recordScan(
          huntId: item.huntId,
          characterId: item.characterId,
          tagUid: item.tagUid,
          location: item.location,
          clientScannedAt: item.clientScannedAt,
          queuedOffline: true,
        );
        await queue.removeByLocalId(item.localId);
        synced++;
      } catch (e) {
        if (_isRetryableNetworkError(e)) {
          failed++;
          break;
        }
        // Non-retryable (e.g. permission / invalid): drop so the queue unblocks.
        await queue.removeByLocalId(item.localId);
        failed++;
      }
    }
    return NfcHuntQueueDrainSummary(syncedCount: synced, failedCount: failed);
  }

  bool _isRetryableNetworkError(Object e) =>
      e is FirebaseFunctionsException &&
      (e.code == 'unavailable' || e.code == 'deadline-exceeded');
}
