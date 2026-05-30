import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local cache: LM integration was verified working for a tenant (per signed-in user).
class LmIntegrationReadinessCache {
  LmIntegrationReadinessCache({
    SharedPreferences? prefs,
    FirebaseAuth? auth,
  })  : _prefs = prefs,
        _auth = auth ?? FirebaseAuth.instance;

  static const _keyPrefix = 'lm_integration_ready_v1';

  final SharedPreferences? _prefs;
  final FirebaseAuth _auth;

  String _storageKey(String tenantKey) {
    final uid = _auth.currentUser?.uid ?? '';
    return '$_keyPrefix:${uid}_$tenantKey';
  }

  Future<bool> isReady(String tenantKey) async {
    if (tenantKey.isEmpty) return false;
    final prefs = await _resolvePrefs();
    if (prefs == null) return false;
    return prefs.getBool(_storageKey(tenantKey)) ?? false;
  }

  Future<void> markReady(String tenantKey) async {
    if (tenantKey.isEmpty) return;
    final prefs = await _resolvePrefs();
    if (prefs == null) return;
    await prefs.setBool(_storageKey(tenantKey), true);
  }

  Future<void> clear(String tenantKey) async {
    if (tenantKey.isEmpty) return;
    final prefs = await _resolvePrefs();
    if (prefs == null) return;
    await prefs.remove(_storageKey(tenantKey));
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
