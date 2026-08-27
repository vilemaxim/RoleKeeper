import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/activity_event.dart';

/// Locally persisted hunt scan waiting for `recordNfcHuntScan` sync.
class PendingNfcHuntScan {
  const PendingNfcHuntScan({
    required this.localId,
    required this.tenantKey,
    required this.huntId,
    required this.tagUid,
    required this.characterId,
    required this.clientScannedAt,
    this.location,
    this.rawQrPayload,
  });

  final String localId;
  final String tenantKey;
  final String huntId;
  final String tagUid;
  final String characterId;
  final DateTime clientScannedAt;
  final ActivityEventLocation? location;
  final String? rawQrPayload;

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'tenantKey': tenantKey,
        'huntId': huntId,
        'tagUid': tagUid,
        'characterId': characterId,
        'clientScannedAt': clientScannedAt.toUtc().toIso8601String(),
        if (location != null) 'location': location!.toMap(),
        if (rawQrPayload != null) 'rawQrPayload': rawQrPayload,
      };

  static PendingNfcHuntScan? fromJson(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    final localId = raw['localId'];
    final tenantKey = raw['tenantKey'];
    final huntId = raw['huntId'];
    final tagUid = raw['tagUid'];
    final characterId = raw['characterId'];
    final scannedAtRaw = raw['clientScannedAt'];
    if (localId is! String ||
        localId.isEmpty ||
        tenantKey is! String ||
        huntId is! String ||
        tagUid is! String ||
        characterId is! String ||
        scannedAtRaw is! String) {
      return null;
    }
    final scannedAt = DateTime.tryParse(scannedAtRaw);
    if (scannedAt == null) return null;
    return PendingNfcHuntScan(
      localId: localId,
      tenantKey: tenantKey,
      huntId: huntId,
      tagUid: tagUid,
      characterId: characterId,
      clientScannedAt: scannedAt.toUtc(),
      location: ActivityEventLocation.fromMap(raw['location']),
      rawQrPayload: raw['rawQrPayload'] as String?,
    );
  }
}

/// SharedPreferences FIFO queue of offline scavenger-hunt scans.
class NfcHuntOfflineQueueService {
  NfcHuntOfflineQueueService({
    SharedPreferences? prefs,
    FirebaseAuth? auth,
  })  : _prefs = prefs,
        _authOverride = auth;

  static const _keyPrefix = 'nfc_hunt_offline_queue_v1';

  final SharedPreferences? _prefs;
  final FirebaseAuth? _authOverride;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  static String storageKeyFor({required String uid}) => '$_keyPrefix:$uid';

  String get _storageKey {
    final uid = _auth.currentUser?.uid ?? '';
    return storageKeyFor(uid: uid);
  }

  Future<List<PendingNfcHuntScan>> loadPending() async {
    final prefs = await _resolvePrefs();
    if (prefs == null) return const [];
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <PendingNfcHuntScan>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final parsed =
            PendingNfcHuntScan.fromJson(Map<String, dynamic>.from(item));
        if (parsed != null) out.add(parsed);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> enqueue(PendingNfcHuntScan item) async {
    final prefs = await _resolvePrefs();
    if (prefs == null) return;
    final pending = [...await loadPending(), item];
    await _persist(prefs, pending);
  }

  Future<void> removeByLocalId(String localId) async {
    final prefs = await _resolvePrefs();
    if (prefs == null) return;
    final pending =
        (await loadPending()).where((e) => e.localId != localId).toList();
    await _persist(prefs, pending);
  }

  Future<void> _persist(
    SharedPreferences prefs,
    List<PendingNfcHuntScan> pending,
  ) async {
    final encoded = jsonEncode(pending.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }

  Future<SharedPreferences?> _resolvePrefs() async {
    final existing = _prefs;
    if (existing != null) return existing;
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }
}
