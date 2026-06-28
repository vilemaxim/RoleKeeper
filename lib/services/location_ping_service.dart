import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

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

  /// Minimum movement (meters) before sending another ping.
  static const movementThresholdMeters = 10.0;

  /// Send a ping at least this often even when stationary (seconds).
  static const heartbeatIntervalSeconds = 300;

  /// New fix must improve accuracy by at least this much to re-ping in place.
  static const accuracyImprovementMeters = 5.0;

  bool _running = false;
  Timer? _timer;

  DateTime? _lastSentAt;
  double? _lastSentLat;
  double? _lastSentLng;
  double? _lastSentAccuracy;
  bool _forceNextPing = false;

  LocationTrackingRules? _activeRules;
  MemberPresence? _activePresence;

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

  /// Whether a fix should be sent given last-sent state and movement/heartbeat rules.
  @visibleForTesting
  static bool shouldSendPing({
    required double latitude,
    required double longitude,
    required double? accuracy,
    required double? lastSentLat,
    required double? lastSentLng,
    required double? lastSentAccuracy,
    required DateTime? lastSentAt,
    required DateTime now,
    required bool force,
  }) {
    if (force) return true;
    if (lastSentAt == null || lastSentLat == null || lastSentLng == null) {
      return true;
    }

    final elapsed = now.difference(lastSentAt);
    if (elapsed >= const Duration(seconds: heartbeatIntervalSeconds)) {
      return true;
    }

    final distance = Geolocator.distanceBetween(
      lastSentLat,
      lastSentLng,
      latitude,
      longitude,
    );
    if (distance >= movementThresholdMeters) return true;

    if (accuracy != null &&
        lastSentAccuracy != null &&
        lastSentAccuracy - accuracy >= accuracyImprovementMeters) {
      return true;
    }

    return false;
  }

  static bool _presenceChanged(MemberPresence? prior, MemberPresence next) {
    return prior != null &&
        (prior.presenceState != next.presenceState ||
            prior.locationOptIn != next.locationOptIn);
  }

  static bool _rulesChanged(
    LocationTrackingRules? prior,
    LocationTrackingRules next,
  ) {
    return prior != null &&
        (prior.enabled != next.enabled ||
            prior.pingIntervalSeconds != next.pingIntervalSeconds);
  }

  void _clearLastSentState() {
    _lastSentAt = null;
    _lastSentLat = null;
    _lastSentLng = null;
    _lastSentAccuracy = null;
    _forceNextPing = false;
  }

  void _recordSent(ActivityEventLocation location) {
    _lastSentAt = DateTime.now();
    _lastSentLat = location.latitude;
    _lastSentLng = location.longitude;
    _lastSentAccuracy = location.accuracy;
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
    _activeRules = rules;
    _activePresence = presence;
    _forceNextPing = true;
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
    _activeRules = null;
    _activePresence = null;
    _clearLastSentState();
  }

  /// Re-evaluates conditions; starts or stops the timer accordingly.
  Future<void> syncConditions({
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

    final presenceChanged =
        _running && _presenceChanged(_activePresence, presence);
    final rulesChanged = _running && _rulesChanged(_activeRules, rules);

    _activeRules = rules;
    _activePresence = presence;

    if (_running) {
      if (presenceChanged || rulesChanged) {
        _forceNextPing = true;
        unawaited(_sendPing());
      }
      return;
    }

    await start(
      rules: rules,
      eventLive: eventLive,
      presence: presence,
    );
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

      final force = _forceNextPing;
      _forceNextPing = false;
      if (!shouldSendPing(
        latitude: location.latitude,
        longitude: location.longitude,
        accuracy: location.accuracy,
        lastSentLat: _lastSentLat,
        lastSentLng: _lastSentLng,
        lastSentAccuracy: _lastSentAccuracy,
        lastSentAt: _lastSentAt,
        now: DateTime.now(),
        force: force,
      )) {
        return;
      }

      final tenant = _resolvedTenant;
      final debug = debugSendPing;
      if (debug != null) {
        await debug(tenant: tenant, location: location);
      } else {
        final callable = _resolvedFunctions.httpsCallable(callableName);
        await callable.call({
          'gameId': tenant.tenantKey,
          'instanceId': tenant.instanceId,
          'eventSlug': tenant.eventSlug,
          'location': location.toMap(),
        });
      }

      _recordSent(location);
    } catch (e, st) {
      debugPrint('LocationPingService._sendPing: $e\n$st');
    }
  }
}
