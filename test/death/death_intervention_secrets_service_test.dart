import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/services/death_intervention_secrets_service.dart';
import 'package:rolekeeper/services/game_context_service.dart';
import 'package:rolekeeper/utils/game_firestore_paths.dart';

import '../helpers/game_tenant_test_paths.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(GameContextService.instance.resetForTest);

  group('DeathInterventionSecrets (H3 cache contract)', () {
    test('fromJson round-trips toJson', () {
      const secrets = DeathInterventionSecrets(
        totpSecret: 'JBSWY3DPEHPK3PXP',
        qrSigningSecret: 'abc123deadbeef',
      );
      final restored = DeathInterventionSecrets.fromJson(
        jsonEncode(secrets.toJson()),
      );
      expect(restored?.totpSecret, secrets.totpSecret);
      expect(restored?.qrSigningSecret, secrets.qrSigningSecret);
    });

    test('fromJson rejects incomplete payloads', () {
      expect(DeathInterventionSecrets.fromJson(''), isNull);
      expect(
        DeathInterventionSecrets.fromJson(jsonEncode({'totpSecret': 'only'})),
        isNull,
      );
    });
  });

  group('DeathInterventionSecretsService (H3)', () {
    late MockFlutterSecureStorage secureStorage;
    late FakeFirebaseFirestore firestore;
    late MockFirebaseFunctions functions;

    DeathInterventionSecretsService makeSvc() => DeathInterventionSecretsService(
          secureStorage: secureStorage,
          firestore: firestore,
          functions: functions,
          tenant: kTestGameTenant,
        );

    setUp(() {
      secureStorage = MockFlutterSecureStorage();
      firestore = FakeFirebaseFirestore();
      functions = MockFirebaseFunctions();
      GameContextService.instance.currentTenantForTest = kTestGameTenant;
    });

    test('storage key is scoped per tenant', () {
      expect(
        DeathInterventionSecretsService.storageKeyForTenant('a::b'),
        'death_intervention_secrets_a::b',
      );
    });

    test('getCachedSecrets reads secure storage for current tenant', () async {
      const secrets = DeathInterventionSecrets(
        totpSecret: 'JBSWY3DPEHPK3PXP',
        qrSigningSecret: 'signing-secret-hex',
      );
      when(
        () => secureStorage.read(
          key: DeathInterventionSecretsService.storageKeyForTenant(
            kTestGameTenant.tenantKey,
          ),
        ),
      ).thenAnswer((_) async => jsonEncode(secrets.toJson()));

      final cached = await makeSvc().getCachedSecrets();

      expect(cached?.totpSecret, secrets.totpSecret);
      expect(cached?.qrSigningSecret, secrets.qrSigningSecret);
    });

    test('readSecretsFromFirestore loads eventSession/config fields', () async {
      await seedGameTenantDocs(firestore, kTestGameTenant);
      await GameFirestorePaths.eventSessionConfig(firestore, kTestGameTenant)
          .set({
        'deathTotpSecret': 'JBSWY3DPEHPK3PXP',
        'deathQrSigningSecret': 'qr-signing-secret',
      });

      final secrets = await makeSvc().readSecretsFromFirestore();
      expect(secrets?.totpSecret, 'JBSWY3DPEHPK3PXP');
      expect(secrets?.qrSigningSecret, 'qr-signing-secret');
    });

    test('resolveSecrets caches Firestore secrets when callable skipped', () async {
      await seedGameTenantDocs(firestore, kTestGameTenant);
      await GameFirestorePaths.eventSessionConfig(firestore, kTestGameTenant)
          .set({
        'deathTotpSecret': 'JBSWY3DPEHPK3PXP',
        'deathQrSigningSecret': 'qr-signing-secret',
      });

      when(() => secureStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
      when(
        () => secureStorage.write(key: any(named: 'key'), value: any(named: 'value')),
      ).thenAnswer((_) async {});

      final resolved = await makeSvc().resolveSecrets(tryCallable: false);

      expect(resolved?.totpSecret, 'JBSWY3DPEHPK3PXP');
      verify(
        () => secureStorage.write(
          key: DeathInterventionSecretsService.storageKeyForTenant(
            kTestGameTenant.tenantKey,
          ),
          value: any(named: 'value'),
        ),
      ).called(1);
    });

    test('resolveSecrets returns null when no cache and config missing', () async {
      await seedGameTenantDocs(firestore, kTestGameTenant);

      when(() => secureStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);

      final resolved = await makeSvc().resolveSecrets(tryCallable: false);
      expect(resolved, isNull);
    });

    test('fetchAndCacheSecrets invokes getDeathInterventionSecrets and caches response (H3)',
        () async {
      // Red phase: callable wiring + secure-storage write not yet verified.
      final mockCallable = MockHttpsCallable();
      when(
        () => functions.httpsCallable('getDeathInterventionSecrets'),
      ).thenReturn(mockCallable);
      when(
        () => mockCallable.call<Map<String, dynamic>>(any()),
      ).thenAnswer(
        (_) async => _FakeHttpsCallableResult({
          'totpSecret': 'JBSWY3DPEHPK3PXP',
          'qrSigningSecret': 'qr-signing-secret-hex',
        }),
      );
      when(
        () => secureStorage.write(key: any(named: 'key'), value: any(named: 'value')),
      ).thenAnswer((_) async {});

      final fetched = await makeSvc().fetchAndCacheSecrets();

      expect(fetched?.totpSecret, 'JBSWY3DPEHPK3PXP');
      verify(
        () => functions.httpsCallable('getDeathInterventionSecrets'),
      ).called(1);
      verify(
        () => secureStorage.write(
          key: DeathInterventionSecretsService.storageKeyForTenant(
            kTestGameTenant.tenantKey,
          ),
          value: any(named: 'value'),
        ),
      ).called(1);
      expect(fetched?.qrSigningSecret, 'qr-signing-secret-hex');
    });
  });
}

class MockHttpsCallable extends Mock implements HttpsCallable {}

class _FakeHttpsCallableResult<T> implements HttpsCallableResult<T> {
  _FakeHttpsCallableResult(this.data);
  @override
  final T data;
}
