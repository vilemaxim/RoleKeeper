import 'member_presence.dart';

/// Server-written latest GPS snapshot on a member doc (ADR 002 hot path).
class LastLocationSnapshot {
  const LastLocationSnapshot({
    required this.latitude,
    required this.longitude,
    required this.source,
    required this.timestamp,
    required this.presenceState,
    required this.inGame,
    this.accuracy,
    this.altitude,
  });

  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? altitude;
  final String source;
  final DateTime timestamp;
  final PresenceState presenceState;
  final bool inGame;

  static LastLocationSnapshot? fromMemberMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    final raw = m['lastLocation'];
    if (raw is! Map) return null;

    final lat = raw['latitude'];
    final lng = raw['longitude'];
    if (lat is! num || lng is! num) return null;

    final ts = _parseTimestamp(raw['timestamp']);
    if (ts == null) return null;

    final source = raw['source'];
    if (source is! String || source.isEmpty) return null;

    final presenceState =
        presenceStateFromWire(raw['presenceState'] as String?);
    final inGame = raw['inGame'] is bool
        ? raw['inGame'] as bool
        : presenceState == PresenceState.inGame;

    return LastLocationSnapshot(
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      accuracy: raw['accuracy'] is num
          ? (raw['accuracy'] as num).toDouble()
          : null,
      altitude: raw['altitude'] is num
          ? (raw['altitude'] as num).toDouble()
          : null,
      source: source,
      timestamp: ts,
      presenceState: presenceState,
      inGame: inGame,
    );
  }

  static DateTime? _parseTimestamp(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    return null;
  }
}
