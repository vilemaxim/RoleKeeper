import 'package:flutter/foundation.dart';

import '../models/game_tenant_ref.dart';

/// Active game (tenant). Empty until restore or the user picks a LARP.
class GameContextService {
  GameContextService._();
  static final GameContextService instance = GameContextService._();

  GameTenantRef? _tenant;

  GameTenantRef? get currentTenant => _tenant;

  /// Flat key (`instanceId::eventSlug`) for callables and legacy fields.
  String get currentTenantKey => _tenant?.tenantKey ?? '';

  /// Alias for [currentTenantKey].
  String get currentGameId => currentTenantKey;

  bool get hasSelectedGame => _tenant != null;

  void selectTenant(GameTenantRef tenant) {
    _tenant = tenant;
  }

  void selectGame(String tenantKey) {
    final t = GameTenantRef.tryParseTenantKey(tenantKey);
    if (t != null) _tenant = t;
  }

  void clearGameContext() => _tenant = null;

  @visibleForTesting
  set currentTenantForTest(GameTenantRef tenant) => _tenant = tenant;

  @visibleForTesting
  set currentGameIdForTest(String tenantKey) => selectGame(tenantKey);

  void resetForTest() => _tenant = null;
}
