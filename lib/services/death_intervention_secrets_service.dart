import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/game_tenant_ref.dart';
import '../utils/game_firestore_paths.dart';
import 'game_context_service.dart';

/// Per-event secrets for offline TOTP and signed death QR payloads.
class DeathInterventionSecrets {
  const DeathInterventionSecrets({
    required this.totpSecret,
    required this.qrSigningSecret,
  });

  final String totpSecret;
  final String qrSigningSecret;

  Map<String, dynamic> toJson() => {
        'totpSecret': totpSecret,
        'qrSigningSecret': qrSigningSecret,
      };

  static DeathInterventionSecrets? fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final totp = m['totpSecret'] as String?;
      final qr = m['qrSigningSecret'] as String?;
      if (totp == null || totp.isEmpty || qr == null || qr.isEmpty) return null;
      return DeathInterventionSecrets(totpSecret: totp, qrSigningSecret: qr);
    } catch (_) {
      return null;
    }
  }
}

/// Fetches and caches death intervention secrets per tenant.
class DeathInterventionSecretsService {
  DeathInterventionSecretsService({
    FlutterSecureStorage? secureStorage,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    GameTenantRef? tenant,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance,
        _tenant = tenant ?? GameContextService.instance.currentTenant;

  final FlutterSecureStorage _secureStorage;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final GameTenantRef? _tenant;

  GameTenantRef get _resolvedTenant {
    final t = _tenant;
    if (t == null) throw StateError('No game selected');
    return t;
  }

  @visibleForTesting
  static String storageKeyForTenant(String tenantKey) =>
      'death_intervention_secrets_$tenantKey';

  Future<DeathInterventionSecrets?> getCachedSecrets() async {
    final raw = await _secureStorage.read(
      key: storageKeyForTenant(_resolvedTenant.tenantKey),
    );
    return DeathInterventionSecrets.fromJson(raw);
  }

  Future<DeathInterventionSecrets?> fetchAndCacheSecrets() async {
    final tenant = _resolvedTenant;
    final callable = _functions.httpsCallable('getDeathInterventionSecrets');
    final result = await callable.call<Map<String, dynamic>>({
      'gameId': tenant.tenantKey,
    });
    final data = result.data;
    final totpSecret = data['totpSecret'] as String?;
    final qrSigningSecret = data['qrSigningSecret'] as String?;
    if (totpSecret == null ||
        totpSecret.isEmpty ||
        qrSigningSecret == null ||
        qrSigningSecret.isEmpty) {
      return null;
    }
    final secrets = DeathInterventionSecrets(
      totpSecret: totpSecret,
      qrSigningSecret: qrSigningSecret,
    );
    await _secureStorage.write(
      key: storageKeyForTenant(tenant.tenantKey),
      value: jsonEncode(secrets.toJson()),
    );
    return secrets;
  }

  /// Reads Firestore config directly (e.g. when callable unavailable in tests).
  Future<DeathInterventionSecrets?> readSecretsFromFirestore() async {
    final doc = await GameFirestorePaths.eventSessionConfig(
      _firestore,
      _resolvedTenant,
    ).get();
    final data = doc.data();
    if (data == null) return null;
    final totpSecret = data['deathTotpSecret'] as String?;
    final qrSigningSecret = data['deathQrSigningSecret'] as String?;
    if (totpSecret == null ||
        totpSecret.isEmpty ||
        qrSigningSecret == null ||
        qrSigningSecret.isEmpty) {
      return null;
    }
    return DeathInterventionSecrets(
      totpSecret: totpSecret,
      qrSigningSecret: qrSigningSecret,
    );
  }

  Future<DeathInterventionSecrets?> resolveSecrets({
    bool tryCallable = true,
  }) async {
    final cached = await getCachedSecrets();
    if (cached != null) return cached;

    if (tryCallable) {
      try {
        final fetched = await fetchAndCacheSecrets();
        if (fetched != null) return fetched;
      } catch (_) {
        // Fall through to Firestore read (emulators / offline cache warm-up).
      }
    }

    final fromFirestore = await readSecretsFromFirestore();
    if (fromFirestore != null) {
      await _secureStorage.write(
        key: storageKeyForTenant(_resolvedTenant.tenantKey),
        value: jsonEncode(fromFirestore.toJson()),
      );
    }
    return fromFirestore;
  }
}
