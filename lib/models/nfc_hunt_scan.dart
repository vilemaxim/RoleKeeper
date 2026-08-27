import 'package:cloud_firestore/cloud_firestore.dart';

import 'activity_event.dart';

/// Credited or review scavenger-hunt scan (ADR 007).
class NfcHuntScan {
  const NfcHuntScan({
    required this.id,
    required this.characterId,
    required this.ownerUid,
    required this.tagUid,
    required this.scannedAt,
    required this.queuedOffline,
    required this.tenantKey,
    required this.huntId,
    this.clientScannedAt,
    this.location,
    this.reason,
  });

  final String id;
  final String characterId;
  final String ownerUid;
  final String tagUid;
  final DateTime scannedAt;
  final bool queuedOffline;
  final String tenantKey;
  final String huntId;
  final DateTime? clientScannedAt;
  final ActivityEventLocation? location;
  final String? reason;

  static NfcHuntScan fromMap(String id, Map<String, dynamic>? m) {
    final data = m ?? const <String, dynamic>{};
    return NfcHuntScan(
      id: id,
      characterId: data['characterId'] as String? ?? '',
      ownerUid: data['ownerUid'] as String? ?? '',
      tagUid: data['tagUid'] as String? ?? '',
      scannedAt: _parseTimestamp(data['scannedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      queuedOffline: data['queuedOffline'] == true,
      tenantKey: data['tenantKey'] as String? ?? '',
      huntId: data['huntId'] as String? ?? '',
      clientScannedAt: _parseTimestamp(data['clientScannedAt']),
      location: ActivityEventLocation.fromMap(data['location']),
      reason: data['reason'] as String?,
    );
  }

  static DateTime? _parseTimestamp(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }
}
