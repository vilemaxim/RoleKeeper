import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/models/member_presence.dart';

void main() {
  group('MemberPresence', () {
    test('fromMemberMap(null) returns defaults', () {
      const expected = MemberPresence.defaultPresence;

      final presence = MemberPresence.fromMemberMap(null);

      expect(presence.locationOptIn, expected.locationOptIn);
      expect(presence.presenceState, expected.presenceState);
      expect(presence.presenceUpdatedAt, isNull);
    });

    test('fromMemberMap({}) returns defaults', () {
      final presence = MemberPresence.fromMemberMap({});

      expect(presence.locationOptIn, isFalse);
      expect(presence.presenceState, PresenceState.inGame);
      expect(presence.presenceUpdatedAt, isNull);
    });

    test('fromMemberMap parses locationOptIn and presenceState', () {
      final presence = MemberPresence.fromMemberMap({
        'locationOptIn': true,
        'presenceState': 'out_of_game',
        'role': 'player',
      });

      expect(presence.locationOptIn, isTrue);
      expect(presence.presenceState, PresenceState.outOfGame);
    });

    test('fromMemberMap ignores unknown presenceState and defaults to in_game',
        () {
      final presence = MemberPresence.fromMemberMap({
        'presenceState': 'invalid',
      });

      expect(presence.presenceState, PresenceState.inGame);
    });

    test('presenceFieldsToMap serializes opt-in and presence state', () {
      const presence = MemberPresence(
        locationOptIn: true,
        presenceState: PresenceState.outOfGame,
      );

      expect(presence.presenceFieldsToMap(), {
        'locationOptIn': true,
        'presenceState': 'out_of_game',
      });
    });

    test('presenceStateFromWire round-trips wire names', () {
      expect(presenceStateFromWire('in_game'), PresenceState.inGame);
      expect(presenceStateFromWire('out_of_game'), PresenceState.outOfGame);
      expect(presenceStateFromWire(null), PresenceState.inGame);
    });
  });
}
