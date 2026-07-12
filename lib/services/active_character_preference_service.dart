import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pure helpers for active-character selection rules.
class ActiveCharacterSelection {
  /// Show the home "Playing as" switcher only when the player owns 2+ characters.
  static bool showSwitcher(int ownedCount) => ownedCount >= 2;

  /// Resolve which character id should be active given owned ids (ordered) and
  /// an optional persisted id.
  ///
  /// - 0 owned → null
  /// - 1 owned → that id
  /// - 2+ owned → [persistedId] if still owned, else first
  static String? resolve({
    required List<String> ownedCharacterIds,
    String? persistedId,
  }) {
    if (ownedCharacterIds.isEmpty) return null;
    if (ownedCharacterIds.length == 1) return ownedCharacterIds.first;
    if (persistedId != null && ownedCharacterIds.contains(persistedId)) {
      return persistedId;
    }
    return ownedCharacterIds.first;
  }
}

/// Persists the player's active character id per LARP tenant (and uid).
class ActiveCharacterPreferenceService {
  ActiveCharacterPreferenceService({
    SharedPreferences? prefs,
    FirebaseAuth? auth,
  })  : _prefs = prefs,
        _auth = auth ?? FirebaseAuth.instance;

  static const _keyPrefix = 'active_character_v1';

  final SharedPreferences? _prefs;
  final FirebaseAuth _auth;

  static String storageKeyFor({
    required String uid,
    required String tenantKey,
  }) =>
      '$_keyPrefix:${uid}_$tenantKey';

  String _storageKey(String tenantKey) {
    final uid = _auth.currentUser?.uid ?? '';
    return storageKeyFor(uid: uid, tenantKey: tenantKey);
  }

  Future<String?> getActiveCharacterId(String tenantKey) async {
    if (tenantKey.isEmpty) return null;
    final prefs = await _resolvePrefs();
    if (prefs == null) return null;
    return prefs.getString(_storageKey(tenantKey));
  }

  Future<void> setActiveCharacterId(String tenantKey, String characterId) async {
    if (tenantKey.isEmpty || characterId.isEmpty) return;
    final prefs = await _resolvePrefs();
    if (prefs == null) return;
    await prefs.setString(_storageKey(tenantKey), characterId);
  }

  Future<void> clearActiveCharacterId(String tenantKey) async {
    if (tenantKey.isEmpty) return;
    final prefs = await _resolvePrefs();
    if (prefs == null) return;
    await prefs.remove(_storageKey(tenantKey));
  }

  /// Reconcile persisted selection with [ownedCharacterIds] and persist the
  /// result. Returns the active id after sync (null if none).
  Future<String?> reconcileOwnedCharacters(
    String tenantKey,
    List<String> ownedCharacterIds,
  ) async {
    if (tenantKey.isEmpty) return null;
    final persisted = await getActiveCharacterId(tenantKey);
    final resolved = ActiveCharacterSelection.resolve(
      ownedCharacterIds: ownedCharacterIds,
      persistedId: persisted,
    );
    if (resolved == null) {
      await clearActiveCharacterId(tenantKey);
      return null;
    }
    if (resolved != persisted) {
      await setActiveCharacterId(tenantKey, resolved);
    }
    return resolved;
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
