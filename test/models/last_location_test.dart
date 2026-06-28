import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/models/last_location.dart';
import 'package:rolekeeper/models/member_presence.dart';

void main() {
  group('LastLocationSnapshot', () {
    test('fromMemberMap(null) returns null', () {
      expect(LastLocationSnapshot.fromMemberMap(null), isNull);
    });

    test('fromMemberMap({}) returns null when lastLocation absent', () {
      expect(LastLocationSnapshot.fromMemberMap({}), isNull);
    });

    test('fromMemberMap parses lastLocation snapshot fields', () {
      final at = DateTime.utc(2026, 6, 27, 13, 50);

      final snapshot = LastLocationSnapshot.fromMemberMap({
        'role': 'player',
        'lastLocation': {
          'latitude': 51.5074,
          'longitude': -0.1278,
          'accuracy': 8.0,
          'altitude': 42.5,
          'source': 'gps',
          'timestamp': at,
          'presenceState': 'out_of_game',
          'inGame': false,
        },
      });

      expect(snapshot, isNotNull);
      expect(snapshot!.latitude, 51.5074);
      expect(snapshot.longitude, -0.1278);
      expect(snapshot.accuracy, 8.0);
      expect(snapshot.altitude, 42.5);
      expect(snapshot.source, 'gps');
      expect(snapshot.timestamp, at);
      expect(snapshot.presenceState, PresenceState.outOfGame);
      expect(snapshot.inGame, isFalse);
    });

    test('fromMemberMap returns null for malformed lastLocation', () {
      expect(
        LastLocationSnapshot.fromMemberMap({
          'lastLocation': {'latitude': 51.0},
        }),
        isNull,
      );
    });
  });
}
