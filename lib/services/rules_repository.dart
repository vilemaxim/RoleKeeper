import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/death_rules.dart';
import '../models/game_tenant_ref.dart';
import '../utils/game_firestore_paths.dart';
import 'game_context_service.dart';

/// Loads and saves death rules under `games/{instanceId}/events/{eventSlug}/rules/death`.
class RulesRepository {
  RulesRepository({
    FirebaseFirestore? firestore,
    FlutterSecureStorage? secureStorage,
    GameTenantRef? tenant,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _tenant = tenant ?? GameContextService.instance.currentTenant;

  final FirebaseFirestore _firestore;
  final FlutterSecureStorage _secureStorage;
  final GameTenantRef? _tenant;

  GameTenantRef get _resolvedTenant {
    final t = _tenant;
    if (t == null) throw StateError('No game selected');
    return t;
  }

  @visibleForTesting
  static String storageKeyForTenant(String tenantKey) =>
      'rules_death_cached_$tenantKey';

  String get _cacheKey => storageKeyForTenant(_resolvedTenant.tenantKey);

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
    try {
      final json = await _secureStorage.read(key: _cacheKey);
      if (json == null) return DeathRules.defaultRules;
      return DeathRules.fromMap(
        jsonDecode(json) as Map<String, dynamic>,
      );
    } catch (_) {
      return DeathRules.defaultRules;
    }
  }

  Future<void> _cacheRules(DeathRules rules) async {
    try {
      await _secureStorage.write(
        key: _cacheKey,
        value: jsonEncode(rules.toMap()),
      );
    } catch (_) {
      // Offline cache is best-effort.
    }
  }

  Future<void> saveDeathRules(DeathRules rules) async {
    await _deathRulesRef.set(rules.toMap());
    if (rules.enabled) {
      await _cacheRules(rules);
    }
  }
}
