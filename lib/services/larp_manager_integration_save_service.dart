import 'package:cloud_functions/cloud_functions.dart';

import '../models/game_tenant_ref.dart';

/// Builds and invokes [saveLarpManagerIntegrationConfig].
class LarpManagerIntegrationSaveService {
  LarpManagerIntegrationSaveService({FirebaseFunctions? functions})
      : _functions = functions;

  static const functionsRegion = 'us-central1';

  final FirebaseFunctions? _functions;

  FirebaseFunctions get _resolved =>
      _functions ?? FirebaseFunctions.instanceFor(region: functionsRegion);

  /// Callable body: [gameId] selects the RoleKeeper tenant; [eventSlug] is the LM run slug.
  Map<String, dynamic> buildCallablePayload({
    required GameTenantRef tenant,
    required String baseUrl,
    required String larpManagerEventSlug,
    required String loginPath,
    required bool fetchDetails,
    String? username,
    String? password,
  }) {
    return {
      'gameId': tenant.tenantKey,
      'instanceId': tenant.instanceId,
      'baseUrl': baseUrl,
      'eventSlug': larpManagerEventSlug,
      'loginPath': loginPath,
      'fetchDetails': fetchDetails,
      if (username != null && username.isNotEmpty) 'username': username,
      if (password != null && password.isNotEmpty) 'password': password,
    };
  }

  Future<void> save({
    required GameTenantRef tenant,
    required String baseUrl,
    required String larpManagerEventSlug,
    required String loginPath,
    required bool fetchDetails,
    String? username,
    String? password,
  }) async {
    final callable =
        _resolved.httpsCallable('saveLarpManagerIntegrationConfig');
    await callable.call(
      buildCallablePayload(
        tenant: tenant,
        baseUrl: baseUrl,
        larpManagerEventSlug: larpManagerEventSlug,
        loginPath: loginPath,
        fetchDetails: fetchDetails,
        username: username,
        password: password,
      ),
    );
  }
}
