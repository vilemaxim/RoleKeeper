import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/models/activity_event.dart';
import 'package:rolekeeper/models/nfc_hunt.dart';
import 'package:rolekeeper/models/nfc_hunt_tag.dart';
import 'package:rolekeeper/services/game_context_service.dart';
import 'package:rolekeeper/services/nfc_hunt_service.dart';
import 'package:rolekeeper/utils/game_firestore_paths.dart';

import '../helpers/game_tenant_test_paths.dart';

class MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class MockHttpsCallable extends Mock implements HttpsCallable {}

class _FakeHttpsCallableResult<T> implements HttpsCallableResult<T> {
  _FakeHttpsCallableResult(this.data);
  @override
  final T data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late MockFirebaseFunctions functions;
  late MockHttpsCallable mockCallable;

  NfcHuntService makeSvc() => NfcHuntService(
        firestore: firestore,
        functions: functions,
        tenant: kTestGameTenant,
      );

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    functions = MockFirebaseFunctions();
    mockCallable = MockHttpsCallable();
    GameContextService.instance.currentTenantForTest = kTestGameTenant;
    await seedGameTenantDocs(firestore, kTestGameTenant);
  });

  tearDown(GameContextService.instance.resetForTest);

  group('NfcHuntService hunt CRUD', () {
    test('listHunts returns hunts for current tenant', () async {
      await GameFirestorePaths.nfcHunt(firestore, kTestGameTenant, 'hunt-a')
          .set(
        NfcHunt(
          id: 'hunt-a',
          enabled: true,
          name: 'Forest',
          expectedTagCount: 5,
          placerUids: const ['u1'],
        ).toMap(),
      );
      await GameFirestorePaths.nfcHunt(firestore, kTestGameTenant, 'hunt-b')
          .set(
        const NfcHunt(
          id: 'hunt-b',
          enabled: false,
          name: 'Ruins',
          expectedTagCount: 3,
          placerUids: [],
        ).toMap(),
      );

      final hunts = await makeSvc().listHunts();
      expect(hunts.length, 2);
      expect(hunts.map((h) => h.id), containsAll(['hunt-a', 'hunt-b']));
      final forest = hunts.firstWhere((h) => h.id == 'hunt-a');
      expect(forest.name, 'Forest');
      expect(forest.enabled, isTrue);
      expect(forest.expectedTagCount, 5);
      expect(forest.placerUids, ['u1']);
    });

    test('createHunt writes name and expectedTagCount', () async {
      final created = await makeSvc().createHunt(
        name: 'Night Market',
        expectedTagCount: 8,
      );

      expect(created.name, 'Night Market');
      expect(created.expectedTagCount, 8);
      expect(created.enabled, isFalse);
      expect(created.placerUids, isEmpty);

      final snap = await GameFirestorePaths.nfcHunt(
        firestore,
        kTestGameTenant,
        created.id,
      ).get();
      expect(snap.exists, isTrue);
      expect(snap.data()?['name'], 'Night Market');
      expect(snap.data()?['expectedTagCount'], 8);
    });

    test('setEnabled updates hunt enabled flag', () async {
      await GameFirestorePaths.nfcHunt(firestore, kTestGameTenant, 'hunt-x')
          .set(
        const NfcHunt(
          id: 'hunt-x',
          enabled: false,
          name: 'X',
          expectedTagCount: 1,
          placerUids: [],
        ).toMap(),
      );

      await makeSvc().setEnabled('hunt-x', true);

      final snap = await GameFirestorePaths.nfcHunt(
        firestore,
        kTestGameTenant,
        'hunt-x',
      ).get();
      expect(snap.data()?['enabled'], isTrue);
    });

    test('setPlacerUids updates placer list', () async {
      await GameFirestorePaths.nfcHunt(firestore, kTestGameTenant, 'hunt-x')
          .set(
        const NfcHunt(
          id: 'hunt-x',
          enabled: true,
          name: 'X',
          expectedTagCount: 1,
          placerUids: [],
        ).toMap(),
      );

      await makeSvc().setPlacerUids('hunt-x', ['placer-1', 'placer-2']);

      final snap = await GameFirestorePaths.nfcHunt(
        firestore,
        kTestGameTenant,
        'hunt-x',
      ).get();
      expect(snap.data()?['placerUids'], ['placer-1', 'placer-2']);
    });

    test('listTags returns registered tags for hunt', () async {
      await GameFirestorePaths.nfcHuntTag(
        firestore,
        kTestGameTenant,
        'hunt-a',
        'tag-oak',
      ).set(
        NfcHuntTag(
          tagUid: 'tag-oak',
          placement: NfcHuntPlacement.fixed,
          registeredByUid: 'org-1',
          registeredAt: DateTime.utc(2026, 8, 1),
          label: 'Oak grove',
        ).toMap(),
      );

      final tags = await makeSvc().listTags('hunt-a');
      expect(tags, hasLength(1));
      expect(tags.single.tagUid, 'tag-oak');
      expect(tags.single.label, 'Oak grove');
      expect(tags.single.placement, NfcHuntPlacement.fixed);
    });
  });

  group('NfcHuntService.registerTag callable', () {
    test('calls registerNfcHuntTag with expected body and returns tagUid',
        () async {
      when(() => functions.httpsCallable('registerNfcHuntTag'))
          .thenReturn(mockCallable);
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenAnswer(
        (_) async => _FakeHttpsCallableResult({'tagUid': 'tag-oak-01'}),
      );

      const location = ActivityEventLocation(
        latitude: 45.5,
        longitude: -122.6,
        accuracy: 8,
      );

      final tagUid = await makeSvc().registerTag(
        huntId: 'hunt-forest',
        tagUid: 'tag-oak-01',
        placement: NfcHuntPlacement.fixed,
        label: 'Oak grove',
        location: location,
      );

      expect(tagUid, 'tag-oak-01');
      verify(() => functions.httpsCallable('registerNfcHuntTag')).called(1);

      final verified = verify(
        () => mockCallable.call<Map<String, dynamic>>(captureAny()),
      );
      verified.called(1);
      final body = verified.captured.single as Map<String, dynamic>;
      expect(body['gameId'], kTestTenantKey);
      expect(body['huntId'], 'hunt-forest');
      expect(body['tagUid'], 'tag-oak-01');
      expect(body['placement'], 'fixed');
      expect(body['label'], 'Oak grove');
      expect(body['location'], isA<Map>());
      expect((body['location'] as Map)['latitude'], 45.5);
      expect((body['location'] as Map)['longitude'], -122.6);
    });

    test('omits location for floating placement', () async {
      when(() => functions.httpsCallable('registerNfcHuntTag'))
          .thenReturn(mockCallable);
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenAnswer(
        (_) async => _FakeHttpsCallableResult({'tagUid': 'tag-float'}),
      );

      await makeSvc().registerTag(
        huntId: 'hunt-forest',
        tagUid: 'tag-float',
        placement: NfcHuntPlacement.floating,
      );

      final verified = verify(
        () => mockCallable.call<Map<String, dynamic>>(captureAny()),
      );
      verified.called(1);
      final body = verified.captured.single as Map<String, dynamic>;
      expect(body['placement'], 'floating');
      expect(body.containsKey('location'), isFalse);
    });
  });
}
