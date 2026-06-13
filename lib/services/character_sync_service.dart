import 'package:cloud_functions/cloud_functions.dart';

import '../models/game_tenant_ref.dart';

/// Result of a player-driven per-character refresh.
///
/// `ok == true` means the LM session was established and the mirror
/// doc was updated successfully. `ok == false` means a per-character
/// fetch failed; [error] carries a user-facing message prefixed with
/// "Could not refresh:" that the UI can render verbatim in a snackbar.
class CharacterSyncResult {
  const CharacterSyncResult({required this.ok, this.error});

  final bool ok;
  final String? error;
}

/// Calls the Task 013 `syncMyLarpManagerCharacterCallable` to refresh
/// one LM-synced character the current user owns. Mirrors the
/// constructor / region pattern from
/// [LarpManagerIntegrationSaveService] and [CharacterStatsRepository]
/// so the Flutter test layer can inject a fake [FirebaseFunctions] or
/// stub the service entirely.
class CharacterSyncService {
  CharacterSyncService({FirebaseFunctions? functions}) : _functions = functions;

  static const functionsRegion = 'us-central1';
  static const callableName = 'syncMyLarpManagerCharacterCallable';

  final FirebaseFunctions? _functions;

  FirebaseFunctions get _resolvedFunctions =>
      _functions ?? FirebaseFunctions.instanceFor(region: functionsRegion);

  /// Builds the callable body. The server tenant resolver accepts
  /// either `gameId` (flat key) or `instanceId`+`eventSlug`; we send
  /// both for symmetry with [LarpManagerIntegrationSaveService] so a
  /// mismatch surfaces in tests rather than on the wire.
  Map<String, dynamic> buildCallablePayload({
    required GameTenantRef tenant,
    required String characterUuid,
  }) {
    return {
      'gameId': tenant.tenantKey,
      'instanceId': tenant.instanceId,
      'eventSlug': tenant.eventSlug,
      'characterUuid': characterUuid,
    };
  }

  /// Translates the callable's `{ok, error?}` payload into
  /// [CharacterSyncResult]. Defensive against malformed payloads —
  /// anything that isn't a `Map` resolves to `ok: false`.
  CharacterSyncResult parseResult(Object? data) {
    if (data is Map) {
      final ok = data['ok'] == true;
      final error = data['error'];
      return CharacterSyncResult(
        ok: ok,
        error: error is String ? error : null,
      );
    }
    return const CharacterSyncResult(ok: false);
  }

  /// Invokes the callable. Lets `FirebaseFunctionsException` propagate
  /// unchanged so the caller can route through `reportAppError` per
  /// `.cursor/rules/error-handling.mdc`.
  Future<CharacterSyncResult> refresh({
    required GameTenantRef tenant,
    required String characterUuid,
  }) async {
    final callable = _resolvedFunctions.httpsCallable(callableName);
    final result = await callable.call(
      buildCallablePayload(tenant: tenant, characterUuid: characterUuid),
    );
    return parseResult(result.data);
  }
}
