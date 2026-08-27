import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/models/activity_event.dart';
import 'package:rolekeeper/services/game_context_service.dart';
import 'package:rolekeeper/services/nfc_hunt_scan_service.dart';

class MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class MockHttpsCallable extends Mock implements HttpsCallable {}

class _FakeHttpsCallableResult<T> implements HttpsCallableResult<T> {
  _FakeHttpsCallableResult(this.data);
  @override
  final T data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockFirebaseFunctions functions;
  late MockHttpsCallable mockCallable;

  NfcHuntScanService makeSvc() => NfcHuntScanService(
        functions: functions,
        tenant: kTestGameTenant,
      );

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    functions = MockFirebaseFunctions();
    mockCallable = MockHttpsCallable();
    GameContextService.instance.currentTenantForTest = kTestGameTenant;
  });

  tearDown(GameContextService.instance.resetForTest);

  group('NfcHuntScanService.recordScan callable', () {
    test('builds correct body with characterId, tagUid, and location', () async {
      when(() => functions.httpsCallable('recordNfcHuntScan'))
          .thenReturn(mockCallable);
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenAnswer(
        (_) async => _FakeHttpsCallableResult({
          'outcome': 'credited',
          'scanId': 'scan-1',
        }),
      );

      const location = ActivityEventLocation(
        latitude: 45.5,
        longitude: -122.6,
        accuracy: 8,
      );

      final result = await makeSvc().recordScan(
        huntId: 'hunt-forest',
        characterId: 'char-42',
        tagUid: 'tag-oak-01',
        location: location,
      );

      expect(result.outcome, NfcHuntScanOutcome.credited);
      expect(result.scanId, 'scan-1');
      verify(() => functions.httpsCallable('recordNfcHuntScan')).called(1);

      final verified = verify(
        () => mockCallable.call<Map<String, dynamic>>(captureAny()),
      );
      verified.called(1);
      final body = verified.captured.single as Map<String, dynamic>;
      expect(body['gameId'], kTestTenantKey);
      expect(body['huntId'], 'hunt-forest');
      expect(body['characterId'], 'char-42');
      expect(body['tagUid'], 'tag-oak-01');
      expect(body['location'], isA<Map>());
      expect((body['location'] as Map)['latitude'], 45.5);
      expect((body['location'] as Map)['longitude'], -122.6);
      expect(body.containsKey('queuedOffline'), isFalse);
    });

    test('omits location when null', () async {
      when(() => functions.httpsCallable('recordNfcHuntScan'))
          .thenReturn(mockCallable);
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenAnswer(
        (_) async => _FakeHttpsCallableResult({'outcome': 'credited'}),
      );

      await makeSvc().recordScan(
        huntId: 'hunt-forest',
        characterId: 'char-42',
        tagUid: 'tag-oak-01',
      );

      final verified = verify(
        () => mockCallable.call<Map<String, dynamic>>(captureAny()),
      );
      verified.called(1);
      final body = verified.captured.single as Map<String, dynamic>;
      expect(body.containsKey('location'), isFalse);
    });

    test('maps already_scanned outcome', () async {
      when(() => functions.httpsCallable('recordNfcHuntScan'))
          .thenReturn(mockCallable);
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenAnswer(
        (_) async =>
            _FakeHttpsCallableResult({'outcome': 'already_scanned'}),
      );

      final result = await makeSvc().recordScan(
        huntId: 'hunt-forest',
        characterId: 'char-42',
        tagUid: 'tag-oak-01',
      );

      expect(result.outcome, NfcHuntScanOutcome.alreadyScanned);
      expect(result.scanId, isNull);
    });

    test('maps unknown_tag outcome', () async {
      when(() => functions.httpsCallable('recordNfcHuntScan'))
          .thenReturn(mockCallable);
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenAnswer(
        (_) async => _FakeHttpsCallableResult({'outcome': 'unknown_tag'}),
      );

      final result = await makeSvc().recordScan(
        huntId: 'hunt-forest',
        characterId: 'char-42',
        tagUid: 'tag-bogus',
      );

      expect(result.outcome, NfcHuntScanOutcome.unknownTag);
    });
  });
}
