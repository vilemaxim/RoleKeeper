/// Player opt-in and in-game / out-of-game presence for a LARP member.
class MemberPresence {
  const MemberPresence({
    required this.locationOptIn,
    required this.presenceState,
    this.presenceUpdatedAt,
  });

  final bool locationOptIn;
  final PresenceState presenceState;
  final DateTime? presenceUpdatedAt;

  static const defaultPresence = MemberPresence(
    locationOptIn: false,
    presenceState: PresenceState.inGame,
  );

  static MemberPresence fromMemberMap(Map<String, dynamic>? m) {
    if (m == null) return defaultPresence;
    return MemberPresence(
      locationOptIn: m['locationOptIn'] as bool? ?? false,
      presenceState: presenceStateFromWire(m['presenceState'] as String?),
      presenceUpdatedAt: _parseTimestamp(m['presenceUpdatedAt']),
    );
  }

  Map<String, dynamic> presenceFieldsToMap() => {
        'locationOptIn': locationOptIn,
        'presenceState': presenceState.wireName,
      };

  MemberPresence copyWith({
    bool? locationOptIn,
    PresenceState? presenceState,
    DateTime? presenceUpdatedAt,
  }) =>
      MemberPresence(
        locationOptIn: locationOptIn ?? this.locationOptIn,
        presenceState: presenceState ?? this.presenceState,
        presenceUpdatedAt: presenceUpdatedAt ?? this.presenceUpdatedAt,
      );

  static DateTime? _parseTimestamp(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    return null;
  }
}

/// In-game vs out-of-game presence (orthogonal to location collection).
enum PresenceState {
  inGame,
  outOfGame,
}

extension PresenceStateX on PresenceState {
  String get wireName => switch (this) {
        PresenceState.inGame => 'in_game',
        PresenceState.outOfGame => 'out_of_game',
      };
}

PresenceState presenceStateFromWire(String? raw) {
  switch (raw) {
    case 'out_of_game':
      return PresenceState.outOfGame;
    case 'in_game':
    default:
      return PresenceState.inGame;
  }
}
