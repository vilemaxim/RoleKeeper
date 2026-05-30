import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/death_rules.dart';
import '../models/game_tenant_ref.dart';
import '../utils/game_firestore_paths.dart';
import 'game_context_service.dart';

/// Loads and saves death rules under `games/{instanceId}/events/{eventSlug}/rules/death`.
class RulesRepository {
  RulesRepository({
    FirebaseFirestore? firestore,
    SharedPreferences? prefs,
    GameTenantRef? tenant,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _prefs = prefs,
        _tenant = tenant ?? GameContextService.instance.currentTenant;

  final FirebaseFirestore _firestore;
  final SharedPreferences? _prefs;
  final GameTenantRef? _tenant;

  GameTenantRef get _resolvedTenant {
    final t = _tenant;
    if (t == null) throw StateError('No game selected');
    return t;
  }

  String get _cacheKey => 'rules_death_cached_${_resolvedTenant.tenantKey}';

  DocumentReference<Map<String, dynamic>> get _deathRulesRef =>
      GameFirestorePaths.deathRules(_firestore, _resolvedTenant);

  Future<DeathRules> getDeathRules() async {
    try {
      final doc = await _deathRulesRef.get();
      final data = doc.data();
      final rules = DeathRules.fromMap(data);
      if (rules.enabled) {
        await _cacheRules(rules);
      }
      return rules;
    } catch (_) {
      return await _getCachedRules();
    }
  }

  Future<DeathRules> _getCachedRules() async {
    SharedPreferences? prefs = _prefs;
    if (prefs == null) {
      try {
        prefs = await SharedPreferences.getInstance();
      } catch (_) {
        return DeathRules.defaultRules;
      }
    }
    final json = prefs.getString(_cacheKey);
    if (json == null) return DeathRules.defaultRules;
    try {
      return DeathRules.fromMap(
        jsonDecode(json) as Map<String, dynamic>,
      );
    } catch (_) {
      return DeathRules.defaultRules;
    }
  }

  Future<void> _cacheRules(DeathRules rules) async {
    SharedPreferences? prefs = _prefs;
    if (prefs == null) {
      try {
        prefs = await SharedPreferences.getInstance();
      } catch (_) {
        return;
      }
    }
    await prefs.setString(_cacheKey, jsonEncode(rules.toMap()));
  }

  Future<void> saveDeathRules(DeathRules rules) async {
    await _deathRulesRef.set(rules.toMap());
    if (rules.enabled) {
      await _cacheRules(rules);
    }
  }
}
