import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/activity_event.dart';
import 'location_utils.dart';

/// Game-scoped activity log: `games/{gameId}/activeEvents`.
/// A Cloud Function mirrors each doc to `users/.../activityEvents` and
/// `games/.../characters/{id}/events` when character ids are present.
///
/// Events are created via the `createActiveGameEvent` Cloud Function (server timestamp + time-based id).
abstract final class ActiveEventsUtils {
  static const collectionName = 'activeEvents';
  static const _functionsRegion = 'us-central1';

  static HttpsCallable _createActiveGameEventCallable() =>
      FirebaseFunctions.instanceFor(region: _functionsRegion).httpsCallable('createActiveGameEvent');

  /// Best-effort GPS snapshot for the event (short timeout; failures are ignored).
  static Future<ActivityEventLocation?> captureLocationForEvent() async {
    try {
      final pos = await LocationUtils.getCurrentPositionOrNull(
        timeLimit: const Duration(seconds: 10),
      );
      if (pos == null) return null;
      return ActivityEventLocation(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy.isFinite ? pos.accuracy : null,
        altitude: pos.altitude.isFinite ? pos.altitude : null,
      );
    } catch (e, st) {
      debugPrint('ActiveEventsUtils.captureLocationForEvent: $e\n$st');
      return null;
    }
  }

  static Map<String, dynamic> _callableBody({
    required String gameId,
    required String type,
    required String playerId,
    String? relatedPlayerId,
    String? characterId,
    String? relatedCharacterId,
    String? chainActivityEventId,
    ActivityEventLocation? location,
  }) {
    return {
      'gameId': gameId,
      'type': type,
      'playerId': playerId,
      if (relatedPlayerId != null && relatedPlayerId.isNotEmpty) 'relatedPlayerId': relatedPlayerId,
      if (characterId != null && characterId.isNotEmpty) 'characterId': characterId,
      if (relatedCharacterId != null && relatedCharacterId.isNotEmpty)
        'relatedCharacterId': relatedCharacterId,
      if (chainActivityEventId != null && chainActivityEventId.isNotEmpty)
        'chainActivityEventId': chainActivityEventId,
      if (location != null) 'location': location.toMap(),
    };
  }

  static Future<String> _invokeCreateActiveGameEvent(Map<String, dynamic> body) async {
    final callable = _createActiveGameEventCallable();
    final result = await callable.call(body);
    final raw = result.data;
    if (raw is! Map) {
      throw StateError('createActiveGameEvent: expected map response');
    }
    final map = Map<String, dynamic>.from(raw);
    final id = map['eventId'] as String?;
    if (id == null || id.isEmpty) {
      throw StateError('createActiveGameEvent: missing eventId');
    }
    return id;
  }

  static Future<String> recordDeathTimerStarted({
    required String gameId,
    required String playerId,
    String? characterId,
  }) async {
    final loc = await captureLocationForEvent();
    return _invokeCreateActiveGameEvent(
      _callableBody(
        gameId: gameId,
        type: ActiveGameEventType.deathTimerStarted,
        playerId: playerId,
        characterId: characterId,
        location: loc,
      ),
    );
  }

  static Future<void> recordDeathTimerExpired({
    required String gameId,
    required String playerId,
    required String chainActivityEventId,
    String? characterId,
  }) async {
    final loc = await captureLocationForEvent();
    await _invokeCreateActiveGameEvent(
      _callableBody(
        gameId: gameId,
        type: ActiveGameEventType.deathTimerExpired,
        playerId: playerId,
        characterId: characterId,
        chainActivityEventId: chainActivityEventId,
        location: loc,
      ),
    );
  }

  /// [playerId] is the injured player; [relatedPlayerId] is the medic.
  static Future<void> recordMedicStoppedDeathTimer({
    required String gameId,
    required String injuredPlayerId,
    required String medicPlayerId,
    required String chainActivityEventId,
    String? injuredCharacterId,
    String? medicCharacterId,
  }) async {
    final loc = await captureLocationForEvent();
    await _invokeCreateActiveGameEvent(
      _callableBody(
        gameId: gameId,
        type: ActiveGameEventType.medicStoppedDeathTimer,
        playerId: injuredPlayerId,
        relatedPlayerId: medicPlayerId,
        characterId: injuredCharacterId,
        relatedCharacterId: medicCharacterId,
        chainActivityEventId: chainActivityEventId,
        location: loc,
      ),
    );
  }

  /// [playerId] is the revived (injured) player; [relatedPlayerId] is the medic when known.
  static Future<void> recordMedicRevivedCharacter({
    required String gameId,
    required String injuredPlayerId,
    String? medicPlayerId,
    String? injuredCharacterId,
    String? medicCharacterId,
    required bool offline,
  }) async {
    final loc = await captureLocationForEvent();
    await _invokeCreateActiveGameEvent(
      _callableBody(
        gameId: gameId,
        type: offline
            ? ActiveGameEventType.medicRevivedCharacterOffline
            : ActiveGameEventType.medicRevivedCharacter,
        playerId: injuredPlayerId,
        relatedPlayerId: medicPlayerId,
        characterId: injuredCharacterId,
        relatedCharacterId: medicCharacterId,
        location: loc,
      ),
    );
  }
}
