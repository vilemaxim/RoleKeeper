import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/activity_event.dart';
import '../models/game_tenant_ref.dart';
import '../models/location_tracking_rules.dart';
import '../models/member_presence.dart';
import '../services/game_context_service.dart';
import '../utils/location_utils.dart';
import '../utils/startup_permissions_utils.dart';

/// Periodic location pings while tracking is active during a live event.
class LocationPingService {
  LocationPingService({
    FirebaseFunctions? functions,
    GameTenantRef? tenant,
  })  : _functions = functions,
        _tenant = tenant ?? GameContextService.instance.currentTenant;

  final FirebaseFunctions? _functions;
  final GameTenantRef? _tenant;

  static const functionsRegion = 'us-central1';
  static const callableName = 'recordLocationPing';

  bool _running = false;
  Timer? _timer;

  bool get isRunning => _running;

  @visibleForTesting
  Future<void> Function({
    required GameTenantRef tenant,
    required ActivityEventLocation location,
    String? characterId,
  })? debugSendPing;

  FirebaseFunctions get _resolvedFunctions =>
      _functions ?? FirebaseFunctions.instanceFor(region: functionsRegion);

  GameTenantRef get _resolvedTenant {
    final t = _tenant;
    if (t == null) throw StateError('No game selected');
    return t;
  }

  /// Whether client-side conditions allow attempting pinging (excludes permission).
  static bool shouldRun({
    required LocationTrackingRules rules,
    required bool eventLive,
    required MemberPresence presence,
  }) {
    return rules.enabled && eventLive && presence.locationOptIn;
  }

  /// Starts the foreground ping timer when [shouldRun] is true.
  Future<void> start({
    required LocationTrackingRules rules,
    required bool eventLive,
    required MemberPresence presence,
  }) async {
    if (!shouldRun(
      rules: rules,
      eventLive: eventLive,
      presence: presence,
    )) {
      stop();
      return;
    }
    if (_running) return;

    final perm = await requestLocationWhenNeeded(promptIfNeeded: true);
    if (!perm.granted) {
      stop();
      return;
    }

    _running = true;
    unawaited(_sendPing());
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: rules.pingIntervalSeconds),
      (_) => unawaited(_sendPing()),
    );
  }

  /// Stops the timer and clears running state.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  /// Re-evaluates conditions; starts or stops the timer accordingly.
  Future<void> syncConditions({
    required LocationTrackingRules rules,
    required bool eventLive,
    required MemberPresence presence,
  }) async {
    if (shouldRun(
      rules: rules,
      eventLive: eventLive,
      presence: presence,
    )) {
      await start(
        rules: rules,
        eventLive: eventLive,
        presence: presence,
      );
    } else {
      stop();
    }
  }

  void dispose() => stop();

  Future<void> _sendPing() async {
    if (!_running) return;
    try {
      final pos = await LocationUtils.getCurrentPositionOrNull(
        timeLimit: const Duration(seconds: 15),
      );
      if (pos == null) return;

      final location = ActivityEventLocation(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy.isFinite ? pos.accuracy : null,
        altitude: pos.altitude.isFinite ? pos.altitude : null,
        source: 'gps',
      );

      final tenant = _resolvedTenant;
      final debug = debugSendPing;
      if (debug != null) {
        await debug(tenant: tenant, location: location);
        return;
      }

      final callable = _resolvedFunctions.httpsCallable(callableName);
      await callable.call({
        'gameId': tenant.tenantKey,
        'instanceId': tenant.instanceId,
        'eventSlug': tenant.eventSlug,
        'location': location.toMap(),
      });
    } catch (e, st) {
      debugPrint('LocationPingService._sendPing: $e\n$st');
    }
  }
}
