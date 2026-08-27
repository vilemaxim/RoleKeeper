import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/models/activity_event.dart';
import 'package:rolekeeper/services/game_context_service.dart';
import 'package:rolekeeper/services/nfc_hunt_offline_queue_service.dart';
import 'package:rolekeeper/services/nfc_hunt_scan_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class MockHttpsCallable extends Mock implements HttpsCallable {}

class _FakeHttpsCallableResult<T> implements HttpsCallableResult<T> {
  _FakeHttpsCallableResult(this.data);
  @override
  final T data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late MockFirebaseAuth auth;

  const scannedAt = '2026-08-19T18:59:00.000Z';

  PendingNfcHuntScan samplePending({
    String localId = 'local-1',
    String tagUid = 'tag-oak-01',
  }) {
    return PendingNfcHuntScan(
      localId: localId,
      tenantKey: kTestTenantKey,
      huntId: 'hunt-forest',
      tagUid: tagUid,
      characterId: 'char-42',
      clientScannedAt: DateTime.parse(scannedAt),
      location: const ActivityEventLocation(
        latitude: 45.5,
        longitude: -122.6,
        accuracy: 8,
      ),
      rawQrPayload:
          'rolekeeper:scavenger:v1:$kTestTenantKey:hunt-forest:$tagUid',
    );
  }

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'user-a'),
    );
    GameContextService.instance.currentTenantForTest = kTestGameTenant;
  });

  tearDown(GameContextService.instance.resetForTest);

  group('NfcHuntOfflineQueueService persistence', () {
    test('enqueue, persist, and reload pending scans FIFO', () async {
      final queue = NfcHuntOfflineQueueService(prefs: prefs, auth: auth);

      expect(await queue.loadPending(), isEmpty);

      await queue.enqueue(samplePending(localId: 'local-a', tagUid: 'tag-a'));
      await queue.enqueue(samplePending(localId: 'local-b', tagUid: 'tag-b'));

      final loaded = await queue.loadPending();
      expect(loaded, hasLength(2));
      expect(loaded.map((e) => e.localId).toList(), ['local-a', 'local-b']);
      expect(loaded.first.tenantKey, kTestTenantKey);
      expect(loaded.first.huntId, 'hunt-forest');
      expect(loaded.first.characterId, 'char-42');
      expect(loaded.first.clientScannedAt.toUtc().toIso8601String(), scannedAt);
      expect(loaded.first.location?.latitude, 45.5);
      expect(loaded.first.rawQrPayload, contains('tag-a'));

      final restored = NfcHuntOfflineQueueService(
        prefs: await SharedPreferences.getInstance(),
        auth: auth,
      );
      final reloaded = await restored.loadPending();
      expect(reloaded.map((e) => e.localId).toList(), ['local-a', 'local-b']);
    });

    test('removeByLocalId drops only that entry', () async {
      final queue = NfcHuntOfflineQueueService(prefs: prefs, auth: auth);
      await queue.enqueue(samplePending(localId: 'local-a', tagUid: 'tag-a'));
      await queue.enqueue(samplePending(localId: 'local-b', tagUid: 'tag-b'));

      await queue.removeByLocalId('local-a');

      final left = await queue.loadPending();
      expect(left.map((e) => e.localId).toList(), ['local-b']);
    });

    test('storage key is scoped by uid', () {
      expect(
        NfcHuntOfflineQueueService.storageKeyFor(uid: 'user-a'),
        contains('user-a'),
      );
      expect(
        NfcHuntOfflineQueueService.storageKeyFor(uid: 'user-a'),
        isNot(NfcHuntOfflineQueueService.storageKeyFor(uid: 'user-b')),
      );
    });
  });

  group('NfcHuntScanService offline enqueue path', () {
    late MockFirebaseFunctions functions;
    late MockHttpsCallable mockCallable;

    NfcHuntScanService makeSvc() => NfcHuntScanService(
          functions: functions,
          tenant: kTestGameTenant,
        );

    setUp(() {
      functions = MockFirebaseFunctions();
      mockCallable = MockHttpsCallable();
      when(() => functions.httpsCallable('recordNfcHuntScan'))
          .thenReturn(mockCallable);
    });

    test(
      'submitScan enqueues and returns saved-offline when callable is unavailable',
      () async {
        when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
          FirebaseFunctionsException(
            code: 'unavailable',
            message: 'network down',
          ),
        );

        final queue = NfcHuntOfflineQueueService(prefs: prefs, auth: auth);
        final submit = await makeSvc().submitScan(
          huntId: 'hunt-forest',
          characterId: 'char-42',
          tagUid: 'tag-oak-01',
          location: const ActivityEventLocation(
            latitude: 45.5,
            longitude: -122.6,
          ),
          clientScannedAt: DateTime.parse(scannedAt),
          rawQrPayload:
              'rolekeeper:scavenger:v1:$kTestTenantKey:hunt-forest:tag-oak-01',
          offlineQueue: queue,
        );

        expect(submit.savedOffline, isTrue);
        expect(submit.result, isNull);
        expect(
          submit.userMessage,
          NfcHuntScanService.offlineSavedMessage,
        );
        expect(
          NfcHuntScanService.offlineSavedMessage,
          'Saved — will sync when online',
        );

        final pending = await queue.loadPending();
        expect(pending, hasLength(1));
        expect(pending.single.tagUid, 'tag-oak-01');
        expect(pending.single.huntId, 'hunt-forest');
        expect(pending.single.characterId, 'char-42');
        expect(pending.single.tenantKey, kTestTenantKey);
        expect(
          pending.single.clientScannedAt.toUtc().toIso8601String(),
          scannedAt,
        );
      },
    );

    test('submitScan returns online outcome without enqueueing', () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenAnswer(
        (_) async => _FakeHttpsCallableResult({
          'outcome': 'credited',
          'scanId': 'scan-9',
        }),
      );

      final queue = NfcHuntOfflineQueueService(prefs: prefs, auth: auth);
      final submit = await makeSvc().submitScan(
        huntId: 'hunt-forest',
        characterId: 'char-42',
        tagUid: 'tag-oak-01',
        offlineQueue: queue,
      );

      expect(submit.savedOffline, isFalse);
      expect(submit.result?.outcome, NfcHuntScanOutcome.credited);
      expect(submit.result?.scanId, 'scan-9');
      expect(await queue.loadPending(), isEmpty);
    });
  });

  group('NfcHuntScanService.drainOfflineQueue', () {
    late MockFirebaseFunctions functions;
    late MockHttpsCallable mockCallable;

    NfcHuntScanService makeSvc() => NfcHuntScanService(
          functions: functions,
          tenant: kTestGameTenant,
        );

    setUp(() {
      functions = MockFirebaseFunctions();
      mockCallable = MockHttpsCallable();
      when(() => functions.httpsCallable('recordNfcHuntScan'))
          .thenReturn(mockCallable);
    });

    test('drain success removes item and sends queuedOffline + clientScannedAt',
        () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenAnswer(
        (_) async => _FakeHttpsCallableResult({
          'outcome': 'credited',
          'scanId': 'scan-sync-1',
        }),
      );

      final queue = NfcHuntOfflineQueueService(prefs: prefs, auth: auth);
      await queue.enqueue(samplePending());

      final summary = await makeSvc().drainOfflineQueue(queue);

      expect(summary.syncedCount, 1);
      expect(summary.failedCount, 0);
      expect(await queue.loadPending(), isEmpty);

      final verified = verify(
        () => mockCallable.call<Map<String, dynamic>>(captureAny()),
      );
      verified.called(1);
      final body = verified.captured.single as Map<String, dynamic>;
      expect(body['queuedOffline'], isTrue);
      expect(body['clientScannedAt'], scannedAt);
      expect(body['tagUid'], 'tag-oak-01');
      expect(body['characterId'], 'char-42');
      expect(body['huntId'], 'hunt-forest');
    });

    test('failed sync leaves item in queue', () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'unavailable',
          message: 'still offline',
        ),
      );

      final queue = NfcHuntOfflineQueueService(prefs: prefs, auth: auth);
      await queue.enqueue(samplePending());

      final summary = await makeSvc().drainOfflineQueue(queue);

      expect(summary.syncedCount, 0);
      expect(summary.failedCount, 1);
      final pending = await queue.loadPending();
      expect(pending, hasLength(1));
      expect(pending.single.localId, 'local-1');
    });

    test('drain is FIFO and stops retaining later items after a failure',
        () async {
      var calls = 0;
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenAnswer(
        (_) async {
          calls++;
          if (calls == 1) {
            return _FakeHttpsCallableResult({
              'outcome': 'already_scanned',
            });
          }
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'blip',
          );
        },
      );

      final queue = NfcHuntOfflineQueueService(prefs: prefs, auth: auth);
      await queue.enqueue(samplePending(localId: 'first', tagUid: 'tag-1'));
      await queue.enqueue(samplePending(localId: 'second', tagUid: 'tag-2'));
      await queue.enqueue(samplePending(localId: 'third', tagUid: 'tag-3'));

      final summary = await makeSvc().drainOfflineQueue(queue);

      expect(summary.syncedCount, 1);
      expect(summary.failedCount, 1);
      final pending = await queue.loadPending();
      expect(pending.map((e) => e.localId).toList(), ['second', 'third']);
    });
  });
}
