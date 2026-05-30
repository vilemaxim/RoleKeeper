/// Role within a game for permissions (owner > superAdmin > staff > player).
enum GameRole {
  owner,
  superAdmin,
  staff,
  player,
}

extension GameRoleX on GameRole {
  /// Firestore string value.
  String get wireName => switch (this) {
        GameRole.owner => 'owner',
        GameRole.superAdmin => 'superAdmin',
        GameRole.staff => 'staff',
        GameRole.player => 'player',
      };

  /// Death rules UI: only owner and superAdmin configure [RulesScreen].
  bool get canConfigureDeathRules =>
      this == GameRole.owner || this == GameRole.superAdmin;
}

GameRole gameRoleFromWire(String? raw) {
  switch (raw) {
    case 'owner':
      return GameRole.owner;
    case 'superAdmin':
      return GameRole.superAdmin;
    case 'staff':
      return GameRole.staff;
    case 'player':
      return GameRole.player;
    default:
      return GameRole.player;
  }
}
