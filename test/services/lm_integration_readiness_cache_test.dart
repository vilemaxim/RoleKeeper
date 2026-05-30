import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/services/lm_integration_readiness_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LmIntegrationReadinessCache', () {
    late SharedPreferences prefs;
    late MockFirebaseAuth auth;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'user-a'));
    });

    test('markReady and isReady are scoped to uid and tenant', () async {
      final cache = LmIntegrationReadinessCache(prefs: prefs, auth: auth);
      expect(await cache.isReady('lm.example.com::run-a'), isFalse);
      await cache.markReady('lm.example.com::run-a');
      expect(await cache.isReady('lm.example.com::run-a'), isTrue);
      expect(await cache.isReady('lm.example.com::run-b'), isFalse);
    });

    test('clear removes cached readiness', () async {
      final cache = LmIntegrationReadinessCache(prefs: prefs, auth: auth);
      await cache.markReady('lm.example.com::run-a');
      await cache.clear('lm.example.com::run-a');
      expect(await cache.isReady('lm.example.com::run-a'), isFalse);
    });
  });
}
