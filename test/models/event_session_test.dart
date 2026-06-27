import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/models/event_session.dart';

void main() {
  group('EventSession', () {
    test('defaultSession has isLive false and no timestamps', () {
      const expected = EventSession.defaultSession;

      expect(expected.isLive, isFalse);
      expect(expected.liveStartedAt, isNull);
      expect(expected.liveEndedAt, isNull);
      expect(expected.scheduledStartAt, isNull);
      expect(expected.scheduledEndAt, isNull);
    });

    test('fromMap(null) returns defaults', () {
      final session = EventSession.fromMap(null);

      expect(session.isLive, isFalse);
      expect(session.liveStartedAt, isNull);
      expect(session.liveEndedAt, isNull);
      expect(session.scheduledStartAt, isNull);
      expect(session.scheduledEndAt, isNull);
    });

    test('fromMap({}) returns defaults', () {
      final session = EventSession.fromMap({});

      expect(session.isLive, isFalse);
      expect(session.liveStartedAt, isNull);
      expect(session.liveEndedAt, isNull);
    });

    test('fromMap parses isLive and timestamp fields', () {
      final started = DateTime.utc(2026, 6, 27, 18, 0);
      final ended = DateTime.utc(2026, 6, 27, 22, 0);
      final scheduledStart = DateTime.utc(2026, 6, 27, 17, 30);
      final scheduledEnd = DateTime.utc(2026, 6, 27, 23, 0);

      final session = EventSession.fromMap({
        'isLive': true,
        'liveStartedAt': Timestamp.fromDate(started),
        'liveEndedAt': Timestamp.fromDate(ended),
        'scheduledStartAt': Timestamp.fromDate(scheduledStart),
        'scheduledEndAt': Timestamp.fromDate(scheduledEnd),
      });

      expect(session.isLive, isTrue);
      expect(session.liveStartedAt, started.toLocal());
      expect(session.liveEndedAt, ended.toLocal());
      expect(session.scheduledStartAt, scheduledStart.toLocal());
      expect(session.scheduledEndAt, scheduledEnd.toLocal());
    });

    test('fromMap treats missing isLive as false', () {
      final session = EventSession.fromMap({
        'liveStartedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      });

      expect(session.isLive, isFalse);
    });

    test('toMap / fromMap round-trip preserves values', () {
      final started = DateTime.utc(2026, 6, 27, 18, 0);
      final original = EventSession(
        isLive: true,
        liveStartedAt: started,
        liveEndedAt: null,
        scheduledStartAt: DateTime.utc(2026, 6, 27, 17, 0),
        scheduledEndAt: DateTime.utc(2026, 6, 27, 23, 0),
      );

      final roundTrip = EventSession.fromMap(original.toMap());

      expect(roundTrip.isLive, isTrue);
      expect(roundTrip.liveStartedAt, started.toLocal());
      expect(roundTrip.liveEndedAt, isNull);
      expect(roundTrip.scheduledStartAt, original.scheduledStartAt?.toLocal());
      expect(roundTrip.scheduledEndAt, original.scheduledEndAt?.toLocal());
    });

    test('toMap omits null optional timestamps', () {
      const session = EventSession.defaultSession;

      final map = session.toMap();

      expect(map['isLive'], isFalse);
      expect(map.containsKey('liveStartedAt'), isFalse);
      expect(map.containsKey('liveEndedAt'), isFalse);
      expect(map.containsKey('scheduledStartAt'), isFalse);
      expect(map.containsKey('scheduledEndAt'), isFalse);
    });

    test('toMap serializes live and scheduled timestamps', () {
      final started = DateTime.utc(2026, 6, 27, 18, 0);
      final session = EventSession(
        isLive: true,
        liveStartedAt: started,
      );

      final map = session.toMap();

      expect(map['isLive'], isTrue);
      expect(map['liveStartedAt'], Timestamp.fromDate(started));
    });
  });
}
