import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/game_tenant_ref.dart';
import '../models/user_game_option.dart';
import '../utils/game_firestore_paths.dart';
import 'game_context_service.dart';

/// User profile on `users/{uid}` and configured LARPs in [kConfiguredLarpsField]
/// (map keyed by [GameTenantRef.tenantKey]).
class UserProfileService {
  UserProfileService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const kConfiguredLarpsField = 'configuredLarps';

  String? get _uid => _auth.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _firestore.collection('users').doc(uid);

  Map<String, dynamic> _asStringKeyedMap(Object? raw) {
    if (raw is! Map) return {};
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  Future<void> migrateLegacyMembershipsToUserLarpsIfNeeded() async {
    final uid = _uid;
    if (uid == null) return;

    final userRef = _userRef(uid);
    final userSnap = await userRef.get();
    final existing = _asStringKeyedMap(userSnap.data()?[kConfiguredLarpsField]);
    if (existing.isNotEmpty) return;

    const legacyDefaultId = 'default';
    final larps = <String, dynamic>{};
    final memSnap = await userRef.collection('gameMemberships').get();
    for (final doc in memSnap.docs) {
      final tenantKey = doc.id;
      if (tenantKey == legacyDefaultId) continue;

      final tenant = GameTenantRef.tryParseTenantKey(tenantKey);
      if (tenant == null) continue;

      final eventSnap =
          await GameFirestorePaths.eventDoc(_firestore, tenant).get();
      final m = eventSnap.data();
      larps[tenantKey] = {
        'tenantKey': tenantKey,
        'instanceId': tenant.instanceId,
        'eventSlug': tenant.eventSlug,
        'displayName': m?['displayName'] as String? ?? tenant.eventSlug,
        if (m != null && m['larpManagerBaseUrl'] != null)
          'larpManagerBaseUrl': m['larpManagerBaseUrl'],
        if (m != null && m['larpManagerEventSlug'] != null)
          'larpManagerEventSlug': m['larpManagerEventSlug'],
        'configuredAt': FieldValue.serverTimestamp(),
      };
    }

    if (larps.isNotEmpty) {
      await userRef.set(
        {kConfiguredLarpsField: larps},
        SetOptions(merge: true),
      );
    }
  }

  Future<bool> shouldShowLarpPicker() async {
    final uid = _uid;
    if (uid == null) return false;

    await migrateLegacyMembershipsToUserLarpsIfNeeded();

    final snap = await _userRef(uid).get();
    final larps = _asStringKeyedMap(snap.data()?[kConfiguredLarpsField]);
    return larps.isEmpty;
  }

  Future<void> setActiveTenantKey(String tenantKey) async {
    final uid = _uid;
    if (uid == null) return;
    await _userRef(uid).set(
      {'activeGameId': tenantKey, 'activeTenantKey': tenantKey},
      SetOptions(merge: true),
    );
  }

  @Deprecated('Use setActiveTenantKey')
  Future<void> setActiveGameId(String tenantKey) => setActiveTenantKey(tenantKey);

  Future<void> upsertConfiguredLarp({
    required GameTenantRef tenant,
    required String displayName,
    String? baseUrl,
    String? eventSlug,
  }) async {
    final uid = _uid;
    if (uid == null) return;

    final userRef = _userRef(uid);
    final snap = await userRef.get();
    final map = _asStringKeyedMap(snap.data()?[kConfiguredLarpsField]);
    map[tenant.tenantKey] = {
      'tenantKey': tenant.tenantKey,
      'instanceId': tenant.instanceId,
      'eventSlug': tenant.eventSlug,
      'displayName': displayName,
      if (baseUrl != null && baseUrl.isNotEmpty) 'larpManagerBaseUrl': baseUrl,
      if (eventSlug != null && eventSlug.isNotEmpty)
        'larpManagerEventSlug': eventSlug,
      'configuredAt': FieldValue.serverTimestamp(),
    };
    await userRef.set({kConfiguredLarpsField: map}, SetOptions(merge: true));
  }

  Future<String?> getConfiguredLarpLabel(String tenantKey) async {
    final uid = _uid;
    if (uid == null) return null;
    final snap = await _userRef(uid).get();
    final larps = _asStringKeyedMap(snap.data()?[kConfiguredLarpsField]);
    final entry = larps[tenantKey];
    if (entry is! Map) return null;
    final n = entry['displayName'] as String?;
    if (n == null || n.trim().isEmpty) return null;
    return n.trim();
  }

  List<UserGameOption> _sortedOptionsFromLarpsMap(Map<String, dynamic> larps) {
    final rows = <_LarpRowSort>[];
    for (final e in larps.entries) {
      final tenantKey = e.key;
      final raw = e.value;
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final ts = m['configuredAt'];
      DateTime? t;
      if (ts is Timestamp) t = ts.toDate();
      final label = (m['displayName'] as String?)?.trim();
      rows.add(
        _LarpRowSort(
          tenantKey: tenantKey,
          label: (label != null && label.isNotEmpty) ? label : tenantKey,
          configuredAt: t,
        ),
      );
    }
    rows.sort((a, b) {
      final ad = a.configuredAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.configuredAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return rows
        .map((r) => UserGameOption(tenantKey: r.tenantKey, label: r.label))
        .toList();
  }

  Future<List<UserGameOption>> listConfiguredLarpsForSwitcher() async {
    final uid = _uid;
    if (uid == null) return [];

    await migrateLegacyMembershipsToUserLarpsIfNeeded();

    final snap = await _userRef(uid).get();
    final larps = _asStringKeyedMap(snap.data()?[kConfiguredLarpsField]);
    return _sortedOptionsFromLarpsMap(larps);
  }

  Future<void> restoreActiveGameContext() async {
    final uid = _uid;
    if (uid == null) return;

    await migrateLegacyMembershipsToUserLarpsIfNeeded();

    final userRef = _userRef(uid);
    final userSnap = await userRef.get();
    final active = (userSnap.data()?['activeTenantKey'] as String?) ??
        (userSnap.data()?['activeGameId'] as String?);

    final larps = _asStringKeyedMap(userSnap.data()?[kConfiguredLarpsField]);
    final larpKeys = larps.keys.toSet();

    Future<void> pickAndPersist(String tenantKey) async {
      final tenant = GameTenantRef.tryParseTenantKey(tenantKey);
      if (tenant == null) return;
      GameContextService.instance.selectTenant(tenant);
      await userRef.set(
        {'activeGameId': tenantKey, 'activeTenantKey': tenantKey},
        SetOptions(merge: true),
      );
    }

    if (larps.isEmpty) {
      GameContextService.instance.clearGameContext();
      if (active != null) {
        await userRef.set(
          {
            'activeGameId': FieldValue.delete(),
            'activeTenantKey': FieldValue.delete(),
          },
          SetOptions(merge: true),
        );
      }
      return;
    }

    if (active != null && larpKeys.contains(active)) {
      GameContextService.instance.selectGame(active);
      return;
    }

    if (active != null && !larpKeys.contains(active)) {
      await userRef.set(
        {
          'activeGameId': FieldValue.delete(),
          'activeTenantKey': FieldValue.delete(),
        },
        SetOptions(merge: true),
      );
    }

    final sorted = _sortedOptionsFromLarpsMap(larps);
    await pickAndPersist(sorted.first.tenantKey);
  }
}

class _LarpRowSort {
  const _LarpRowSort({
    required this.tenantKey,
    required this.label,
    this.configuredAt,
  });
  final String tenantKey;
  final String label;
  final DateTime? configuredAt;
}
