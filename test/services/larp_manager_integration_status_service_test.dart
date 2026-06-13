import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/models/larp_manager_integration_config.dart';
import 'package:rolekeeper/models/larp_manager_registration_check_result.dart';
import 'package:rolekeeper/services/game_context_service.dart';
import 'package:rolekeeper/services/larp_manager_integration_repository.dart';
import 'package:rolekeeper/services/larp_manager_integration_status_service.dart';
import 'package:rolekeeper/services/larp_manager_registration_service.dart';
import 'package:rolekeeper/services/larp_registry_repository.dart';
import 'package:rolekeeper/services/lm_integration_readiness_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tenantKey = 'lm.example.com::run-a';

  tearDown(GameContextService.instance.resetForTest);

  group('LmManagerIntegrationStatusService.isInfrastructureFailure', () {
    test('internal is infrastructure', () {
      expect(
        LarpManagerIntegrationStatusService.isInfrastructureFailure(
          FirebaseFunctionsException(code: 'internal', message: 'INTERNAL'),
        ),
        isTrue,
      );
    });

    test('secret manager permission denied is infrastructure', () {
      expect(
        LarpManagerIntegrationStatusService.isInfrastructureFailure(
          FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'Secret Manager access denied',
          ),
        ),
        isTrue,
      );
    });
  });

  group('LarpManagerIntegrationStatusService.evaluate', () {
    late SharedPreferences prefs;
    late MockFirebaseAuth auth;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'user-a'));
      GameContextService.instance.currentGameIdForTest = tenantKey;
    });

    test('returns cached ready without calling verify', () async {
      final cache = LmIntegrationReadinessCache(prefs: prefs, auth: auth);
      await cache.markReady(tenantKey);

      var verifyCalls = 0;
      final service = LarpManagerIntegrationStatusService(
        integrationRepo: _FakeIntegrationRepo(configured: true),
        registrationService: _FakeRegistrationService(
          auth: auth,
          onVerify: () async {
            verifyCalls++;
            return const LarpManagerRegistrationCheckResult(registered: true);
          },
        ),
        readinessCache: cache,
      );

      final evaluation = await service.evaluate();
      expect(evaluation.isReady, isTrue);
      expect(evaluation.fromCache, isTrue);
      expect(verifyCalls, 0);
    });

    test('marks cache on successful verify and clears on failure', () async {
      final cache = LmIntegrationReadinessCache(prefs: prefs, auth: auth);
      final service = LarpManagerIntegrationStatusService(
        integrationRepo: _FakeIntegrationRepo(configured: true),
        registrationService: _FakeRegistrationService(
          auth: auth,
          onVerify: () async =>
              throw FirebaseFunctionsException(code: 'internal', message: 'nope'),
        ),
        readinessCache: cache,
      );

      final failed = await service.evaluate(useCache: false);
      expect(failed.isReady, isFalse);
      expect(await cache.isReady(tenantKey), isFalse);

      final okService = LarpManagerIntegrationStatusService(
        integrationRepo: _FakeIntegrationRepo(configured: true),
        registrationService: _FakeRegistrationService(
          auth: auth,
          onVerify: () async => const LarpManagerRegistrationCheckResult(
            registered: true,
            hasCharacter: true,
          ),
        ),
        readinessCache: cache,
      );

      final ok = await okService.evaluate(useCache: false);
      expect(ok.isReady, isTrue);
      expect(await cache.isReady(tenantKey), isTrue);
    });
  });
}

class _FakeIntegrationRepo extends LarpManagerIntegrationRepository {
  _FakeIntegrationRepo({required this.configured})
      : super(firestore: FakeFirebaseFirestore());

  final bool configured;

  @override
  Future<bool> credentialsConfigured() async => configured;

  @override
  Future<LarpManagerIntegrationConfig> get() async =>
      LarpManagerIntegrationConfig(
        baseUrl: 'https://lm.example.com',
        eventSlug: 'run-a',
        loginPath: '/login/',
        credentialsConfigured: configured,
      );
}

class _FakeRegistrationService extends LarpManagerRegistrationService {
  _FakeRegistrationService({
    required FirebaseAuth auth,
    required this.onVerify,
  }) : super(
          firestore: FakeFirebaseFirestore(),
          auth: auth,
          registry: LarpRegistryRepository(
            firestore: FakeFirebaseFirestore(),
            auth: auth,
          ),
        );

  final Future<LarpManagerRegistrationCheckResult> Function() onVerify;

  @override
  Future<LarpManagerRegistrationCheckResult> verifyRegistrationForCurrentGame({
    bool forceRefresh = false,
  }) =>
      onVerify();
}
