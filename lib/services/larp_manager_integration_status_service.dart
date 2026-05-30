import 'package:cloud_functions/cloud_functions.dart';

import '../models/larp_manager_registration_check_result.dart';
import 'game_context_service.dart';
import 'larp_manager_integration_repository.dart';
import 'larp_manager_registration_service.dart';
import 'lm_integration_readiness_cache.dart';

/// Whether RoleKeeper can reach LarpManager for the current game (not just Firestore flags).
enum LmIntegrationReadiness {
  /// No credentials / integration config on the server yet.
  notConfigured,

  /// Config exists but Cloud Function sync failed (Secret Manager, LM login, etc.).
  notOperational,

  /// [verifyRegistration] succeeded — safe to show registration/character flows.
  ready,
}

class LmIntegrationEvaluation {
  const LmIntegrationEvaluation({
    required this.readiness,
    this.checkResult,
    this.lastError,
    this.fromCache = false,
  });

  final LmIntegrationReadiness readiness;
  final LarpManagerRegistrationCheckResult? checkResult;
  final Object? lastError;

  /// True when [readiness] came from local cache (no network verify this call).
  final bool fromCache;

  bool get isReady => readiness == LmIntegrationReadiness.ready;
}

/// Probes Firestore config + a real sync call to decide if LM integration is usable.
class LarpManagerIntegrationStatusService {
  LarpManagerIntegrationStatusService({
    LarpManagerIntegrationRepository? integrationRepo,
    LarpManagerRegistrationService? registrationService,
    LmIntegrationReadinessCache? readinessCache,
  })  : _integrationRepo =
            integrationRepo ?? LarpManagerIntegrationRepository(),
        _registrationService =
            registrationService ?? LarpManagerRegistrationService(),
        _readinessCache = readinessCache ?? LmIntegrationReadinessCache();

  final LarpManagerIntegrationRepository _integrationRepo;
  final LarpManagerRegistrationService _registrationService;
  final LmIntegrationReadinessCache _readinessCache;

  Future<LmIntegrationEvaluation> evaluate({
    bool forceSync = false,
    bool useCache = true,
  }) async {
    final tenantKey = GameContextService.instance.currentTenantKey;

    if (useCache && !forceSync && tenantKey.isNotEmpty) {
      final cached = await _readinessCache.isReady(tenantKey);
      if (cached) {
        return const LmIntegrationEvaluation(
          readiness: LmIntegrationReadiness.ready,
          fromCache: true,
        );
      }
    }

    final configured = await _integrationRepo.credentialsConfigured();
    if (!configured) {
      if (tenantKey.isNotEmpty) {
        await _readinessCache.clear(tenantKey);
      }
      return const LmIntegrationEvaluation(
        readiness: LmIntegrationReadiness.notConfigured,
      );
    }

    try {
      final check = await _registrationService.verifyRegistrationForCurrentGame(
        forceRefresh: forceSync,
      );
      if (tenantKey.isNotEmpty) {
        await _readinessCache.markReady(tenantKey);
      }
      return LmIntegrationEvaluation(
        readiness: LmIntegrationReadiness.ready,
        checkResult: check,
      );
    } catch (e) {
      if (tenantKey.isNotEmpty) {
        await _readinessCache.clear(tenantKey);
      }
      return LmIntegrationEvaluation(
        readiness: LmIntegrationReadiness.notOperational,
        lastError: e,
      );
    }
  }

  /// True when sync cannot run due to setup/IAM, not player registration state.
  static bool isInfrastructureFailure(Object? error) {
    if (error == null) return false;
    if (error is FirebaseFunctionsException) {
      final code = error.code;
      final msg = (error.message ?? '').toLowerCase();
      if (code == 'failed-precondition' &&
          msg.contains('larpmanager is not connected')) {
        return true;
      }
      if (code == 'internal') return true;
      if (code == 'permission-denied' &&
          (msg.contains('secret manager') || msg.contains('secretmanager'))) {
        return true;
      }
    }
    final s = error.toString().toLowerCase();
    return s.contains('secretmanager') || s.contains('secret manager');
  }
}
