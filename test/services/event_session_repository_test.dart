import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/models/game_tenant_ref.dart';
import 'package:rolekeeper/services/event_session_repository.dart';
import 'package:rolekeeper/utils/game_firestore_paths.dart';

import '../helpers/game_tenant_test_paths.dart';

void main() {
  group('EventSessionRepository', () {
    test('get returns defaults when config doc is missing', () async {
      final firestore = FakeFirebaseFirestore();
      await seedGameTenantDocs(firestore, kTestGameTenant);

      final repo = EventSessionRepository(
        firestore: firestore,
        tenant: kTestGameTenant,
      );

      final session = await repo.get();

      expect(session.isLive, isFalse);
      expect(session.liveStartedAt, isNull);
      expect(session.liveEndedAt, isNull);
    });

    test('get reads eventSession/config under current tenant', () async {
      final firestore = FakeFirebaseFirestore();
      await seedGameTenantDocs(firestore, kTestGameTenant);
      final started = DateTime.utc(2026, 6, 27, 18, 0);
      await GameFirestorePaths.eventSessionConfig(firestore, kTestGameTenant)
          .set({
        'isLive': true,
        'liveStartedAt': Timestamp.fromDate(started),
      });

      final repo = EventSessionRepository(
        firestore: firestore,
        tenant: kTestGameTenant,
      );

      final session = await repo.get();

      expect(session.isLive, isTrue);
      expect(session.liveStartedAt, started.toLocal());
    });

    test('startEvent sets isLive true, liveStartedAt, and clears liveEndedAt',
        () async {
      final firestore = FakeFirebaseFirestore();
      await seedGameTenantDocs(firestore, kTestGameTenant);
      final previousEnd = DateTime.utc(2026, 6, 26, 22, 0);
      await GameFirestorePaths.eventSessionConfig(firestore, kTestGameTenant)
          .set({
        'isLive': false,
        'liveEndedAt': Timestamp.fromDate(previousEnd),
      });

      final repo = EventSessionRepository(
        firestore: firestore,
        tenant: kTestGameTenant,
      );

      await repo.startEvent();

      final snap =
          await GameFirestorePaths.eventSessionConfig(firestore, kTestGameTenant)
              .get();
      final data = snap.data()!;
      expect(data['isLive'], isTrue);
      expect(data['liveStartedAt'], isNotNull);
      expect(data.containsKey('liveEndedAt'), isFalse);
    });

    test('startEvent then get reflects live session', () async {
      final firestore = FakeFirebaseFirestore();
      await seedGameTenantDocs(firestore, kTestGameTenant);

      final repo = EventSessionRepository(
        firestore: firestore,
        tenant: kTestGameTenant,
      );

      await repo.startEvent();
      final session = await repo.get();

      expect(session.isLive, isTrue);
      expect(session.liveStartedAt, isNotNull);
      expect(session.liveEndedAt, isNull);
    });

    test('endEvent sets isLive false and liveEndedAt', () async {
      final firestore = FakeFirebaseFirestore();
      await seedGameTenantDocs(firestore, kTestGameTenant);
      final started = DateTime.utc(2026, 6, 27, 18, 0);
      await GameFirestorePaths.eventSessionConfig(firestore, kTestGameTenant)
          .set({
        'isLive': true,
        'liveStartedAt': Timestamp.fromDate(started),
      });

      final repo = EventSessionRepository(
        firestore: firestore,
        tenant: kTestGameTenant,
      );

      await repo.endEvent();

      final snap =
          await GameFirestorePaths.eventSessionConfig(firestore, kTestGameTenant)
              .get();
      final data = snap.data()!;
      expect(data['isLive'], isFalse);
      expect(data['liveEndedAt'], isNotNull);
      expect(data['liveStartedAt'], Timestamp.fromDate(started));
    });

    test('endEvent then get reflects ended session', () async {
      final firestore = FakeFirebaseFirestore();
      await seedGameTenantDocs(firestore, kTestGameTenant);
      await GameFirestorePaths.eventSessionConfig(firestore, kTestGameTenant)
          .set({'isLive': true});

      final repo = EventSessionRepository(
        firestore: firestore,
        tenant: kTestGameTenant,
      );

      await repo.endEvent();
      final session = await repo.get();

      expect(session.isLive, isFalse);
      expect(session.liveEndedAt, isNotNull);
    });

    test('start then end transition preserves liveStartedAt', () async {
      final firestore = FakeFirebaseFirestore();
      await seedGameTenantDocs(firestore, kTestGameTenant);

      final repo = EventSessionRepository(
        firestore: firestore,
        tenant: kTestGameTenant,
      );

      await repo.startEvent();
      final liveSession = await repo.get();
      await repo.endEvent();
      final endedSession = await repo.get();

      expect(liveSession.isLive, isTrue);
      expect(endedSession.isLive, isFalse);
      expect(endedSession.liveStartedAt, liveSession.liveStartedAt);
      expect(endedSession.liveEndedAt, isNotNull);
    });

    test('tenant isolation: reads only the configured game', () async {
      final firestore = FakeFirebaseFirestore();
      const other = GameTenantRef(
        instanceId: 'other.local',
        eventSlug: 'default',
      );

      await seedGameTenantDocs(firestore, kTestGameTenant);
      await seedGameTenantDocs(firestore, other);

      await GameFirestorePaths.eventSessionConfig(firestore, kTestGameTenant)
          .set({'isLive': true});
      await GameFirestorePaths.eventSessionConfig(firestore, other)
          .set({'isLive': false});

      final repoTest = EventSessionRepository(
        firestore: firestore,
        tenant: kTestGameTenant,
      );
      final repoOther = EventSessionRepository(
        firestore: firestore,
        tenant: other,
      );

      expect((await repoTest.get()).isLive, isTrue);
      expect((await repoOther.get()).isLive, isFalse);
    });

    test('throws when no tenant is selected', () {
      final repo = EventSessionRepository(
        firestore: FakeFirebaseFirestore(),
        tenant: null,
      );

      expect(repo.get, throwsA(isA<StateError>()));
      expect(() => repo.startEvent(), throwsA(isA<StateError>()));
      expect(() => repo.endEvent(), throwsA(isA<StateError>()));
    });
  });
}
