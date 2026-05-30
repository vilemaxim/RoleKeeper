import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/game_tenant_ref.dart';
import '../models/larp_manager_event_link.dart';
import '../models/larp_manager_registration_check_result.dart';
import '../utils/game_firestore_paths.dart';
import 'game_context_service.dart';
import 'larp_registry_repository.dart';

/// LarpManager registration status: verified server-side against LM export.
class LarpManagerRegistrationService {
  LarpManagerRegistrationService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    LarpRegistryRepository? registry,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _functions = functions,
        _registry = registry ?? LarpRegistryRepository();

  static const kLarpManagerRegisteredAtField = 'larpManagerRegisteredAt';

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions? _functions;
  final LarpRegistryRepository _registry;

  String? get _uid => _auth.currentUser?.uid;

  Future<LarpManagerEventLink?> getEventLinkForTenant(String tenantKey) async {
    final tenant = GameTenantRef.tryParseTenantKey(tenantKey);
    if (tenant == null) return null;

    String? baseUrl;
    String? eventSlug;

    final uid = _uid;
    if (uid != null) {
      final userSnap = await _firestore.collection('users').doc(uid).get();
      final larps = userSnap.data()?['configuredLarps'];
      if (larps is Map) {
        final entry = larps[tenantKey];
        if (entry is Map) {
          baseUrl = (entry['larpManagerBaseUrl'] as String?)?.trim();
          eventSlug = (entry['larpManagerEventSlug'] as String?)?.trim();
        }
      }
    }

    final eventSnap = await GameFirestorePaths.eventDoc(_firestore, tenant).get();
    final game = eventSnap.data();
    baseUrl ??= (game?['larpManagerBaseUrl'] as String?)?.trim();
    eventSlug ??= (game?['larpManagerEventSlug'] as String?)?.trim();

    if ((baseUrl == null || baseUrl.isEmpty) ||
        (eventSlug == null || eventSlug.isEmpty)) {
      final reg = await _registry.get(tenant);
      if (reg != null) {
        baseUrl ??= reg.larpManagerBaseUrl.trim();
        eventSlug ??= reg.larpManagerEventSlug.trim();
      }
    }

    if (baseUrl == null ||
        baseUrl.isEmpty ||
        eventSlug == null ||
        eventSlug.isEmpty) {
      return null;
    }

    return LarpManagerEventLink.fromBaseAndSlug(
      baseUrl: baseUrl,
      eventSlug: eventSlug,
    );
  }

  /// Fast path: membership already marked registered by Cloud Function.
  Future<bool> isRegisteredForTenant(String tenantKey) async {
    final uid = _uid;
    final tenant = GameTenantRef.tryParseTenantKey(tenantKey);
    if (uid == null || tenant == null) return false;

    final snap =
        await GameFirestorePaths.userMembership(_firestore, uid, tenant).get();
    if (!snap.exists) return false;
    return snap.data()?[kLarpManagerRegisteredAtField] != null;
  }

  /// Calls [checkLarpManagerRegistrationCallable] to sync LM registrations and verify email.
  Future<LarpManagerRegistrationCheckResult> verifyRegistration(
    String tenantKey, {
    bool forceRefresh = false,
  }) async {
    final functions = _functions ??
        FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable =
        functions.httpsCallable('checkLarpManagerRegistrationCallable');
    final result = await callable.call<Map<String, dynamic>>({
      'gameId': tenantKey,
      if (forceRefresh) 'forceRefresh': true,
    });
    return LarpManagerRegistrationCheckResult.fromCallable(
      Map<String, dynamic>.from(result.data),
    );
  }

  Future<LarpManagerRegistrationCheckResult> verifyRegistrationForCurrentGame({
    bool forceRefresh = false,
  }) async {
    final key = GameContextService.instance.currentTenantKey;
    if (key.isEmpty) {
      return const LarpManagerRegistrationCheckResult(
        registered: false,
        message: 'No LARP selected',
      );
    }
    return verifyRegistration(key, forceRefresh: forceRefresh);
  }
}
