/// Firestore `type` field for `games/{gameId}/activeEvents` (and mirrored copies).
abstract final class ActiveGameEventType {
  static const deathTimerStarted = 'deathTimerStarted';
  static const deathTimerExpired = 'deathTimerExpired';
  static const deathTimerQrUnavailable = 'deathTimerQrUnavailable';
  static const medicStoppedDeathTimer = 'medicStoppedDeathTimer';
  static const medicRevivedCharacter = 'medicRevivedCharacter';
  static const medicRevivedCharacterOffline = 'medicRevivedCharacterOffline';
}

/// Legacy enum names (older `playerActivityEvents` docs). Prefer [ActiveGameEventType].
enum ActivityEventType {
  deathCountStarted,
  deathTimeStopped,
  deathInterventionComplete,
  deathInterventionCompleteOffline,
}

/// Optional GPS snapshot attached when an event is recorded.
class ActivityEventLocation {
  const ActivityEventLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.altitude,
    this.source = 'gps',
  });

  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? altitude;
  /// Location provider: `gps` in v1; future `beacon`, `wifi`.
  final String source;

  Map<String, dynamic> toMap() => {
        'latitude': latitude,
        'longitude': longitude,
        'source': source,
        if (accuracy != null && accuracy!.isFinite) 'accuracy': accuracy,
        if (altitude != null && altitude!.isFinite) 'altitude': altitude,
      };

  static ActivityEventLocation? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final lat = map['latitude'];
    final lng = map['longitude'];
    if (lat is num && lng is num) {
      return ActivityEventLocation(
        latitude: lat.toDouble(),
        longitude: lng.toDouble(),
        accuracy: (map['accuracy'] as num?)?.toDouble(),
        altitude: (map['altitude'] as num?)?.toDouble(),
        source: map['source'] as String? ?? 'gps',
      );
    }
    return null;
  }
}

/// An activity event - written to both main and per-user collections.
class ActivityEvent {
  const ActivityEvent({
    required this.id,
    required this.type,
    required this.playerId,
    required this.timestamp,
    this.helpingPlayerId,
    this.eventId,
    this.extra,
    this.location,
  });

  final String id;
  final ActivityEventType type;
  final String playerId;
  final DateTime timestamp;
  final String? helpingPlayerId;
  final String? eventId;
  final Map<String, dynamic>? extra;
  final ActivityEventLocation? location;

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'playerId': playerId,
        'timestamp': timestamp.toIso8601String(),
        if (helpingPlayerId != null) 'helpingPlayerId': helpingPlayerId,
        if (eventId != null) 'eventId': eventId,
        if (extra != null && extra!.isNotEmpty) 'extra': extra,
        if (location != null) 'location': location!.toMap(),
      };

  static ActivityEvent fromMap(Map<String, dynamic> m) {
    final typeStr = m['type'] as String?;
    ActivityEventType type;
    try {
      type = ActivityEventType.values.firstWhere((e) => e.name == typeStr);
    } catch (_) {
      type = ActivityEventType.deathCountStarted;
    }
    return ActivityEvent(
      id: m['id'] as String? ?? '',
      type: type,
      playerId: m['playerId'] as String? ?? '',
      timestamp: DateTime.tryParse(m['timestamp'] as String? ?? '') ?? DateTime.now(),
      helpingPlayerId: m['helpingPlayerId'] as String?,
      eventId: m['eventId'] as String?,
      extra: m['extra'] as Map<String, dynamic>?,
      location: ActivityEventLocation.fromMap(m['location']),
    );
  }
}
