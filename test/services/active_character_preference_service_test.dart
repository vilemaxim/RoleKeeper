import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/services/active_character_preference_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ActiveCharacterPreferenceService', () {
    late SharedPreferences prefs;
    late MockFirebaseAuth auth;

    const tenantA = 'lm.example.com::run-a';
    const tenantB = 'lm.example.com::run-b';

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'user-a'),
      );
    });

    test('persists and restores active character id per tenantKey', () async {
      final svc = ActiveCharacterPreferenceService(prefs: prefs, auth: auth);

      expect(await svc.getActiveCharacterId(tenantA), isNull);

      await svc.setActiveCharacterId(tenantA, 'char-1');
      expect(await svc.getActiveCharacterId(tenantA), 'char-1');
      expect(await svc.getActiveCharacterId(tenantB), isNull);

      await svc.setActiveCharacterId(tenantB, 'char-2');
      expect(await svc.getActiveCharacterId(tenantA), 'char-1');
      expect(await svc.getActiveCharacterId(tenantB), 'char-2');
    });

    test('survives SharedPreferences restart (new service instance)', () async {
      final svc = ActiveCharacterPreferenceService(prefs: prefs, auth: auth);
      await svc.setActiveCharacterId(tenantA, 'char-restart');

      final restored = ActiveCharacterPreferenceService(
        prefs: await SharedPreferences.getInstance(),
        auth: auth,
      );
      expect(await restored.getActiveCharacterId(tenantA), 'char-restart');
    });

    test('clearActiveCharacterId removes selection for that tenant only',
        () async {
      final svc = ActiveCharacterPreferenceService(prefs: prefs, auth: auth);
      await svc.setActiveCharacterId(tenantA, 'char-1');
      await svc.setActiveCharacterId(tenantB, 'char-2');
      await svc.clearActiveCharacterId(tenantA);

      expect(await svc.getActiveCharacterId(tenantA), isNull);
      expect(await svc.getActiveCharacterId(tenantB), 'char-2');
    });

    test('storage key is scoped by uid and tenantKey', () {
      expect(
        ActiveCharacterPreferenceService.storageKeyFor(
          uid: 'user-a',
          tenantKey: tenantA,
        ),
        contains('user-a'),
      );
      expect(
        ActiveCharacterPreferenceService.storageKeyFor(
          uid: 'user-a',
          tenantKey: tenantA,
        ),
        contains(tenantA),
      );
      expect(
        ActiveCharacterPreferenceService.storageKeyFor(
          uid: 'user-a',
          tenantKey: tenantA,
        ),
        isNot(
          ActiveCharacterPreferenceService.storageKeyFor(
            uid: 'user-b',
            tenantKey: tenantA,
          ),
        ),
      );
    });

    group('reconcileOwnedCharacters', () {
      test('0 characters clears active character', () async {
        final svc = ActiveCharacterPreferenceService(prefs: prefs, auth: auth);
        await svc.setActiveCharacterId(tenantA, 'stale');

        final active = await svc.reconcileOwnedCharacters(tenantA, const []);
        expect(active, isNull);
        expect(await svc.getActiveCharacterId(tenantA), isNull);
      });

      test('1 character auto-selects that character', () async {
        final svc = ActiveCharacterPreferenceService(prefs: prefs, auth: auth);

        final active =
            await svc.reconcileOwnedCharacters(tenantA, const ['only-char']);
        expect(active, 'only-char');
        expect(await svc.getActiveCharacterId(tenantA), 'only-char');
      });

      test('2+ characters keeps persisted id when still owned', () async {
        final svc = ActiveCharacterPreferenceService(prefs: prefs, auth: auth);
        await svc.setActiveCharacterId(tenantA, 'char-b');

        final active = await svc.reconcileOwnedCharacters(
          tenantA,
          const ['char-a', 'char-b', 'char-c'],
        );
        expect(active, 'char-b');
        expect(await svc.getActiveCharacterId(tenantA), 'char-b');
      });

      test('2+ characters falls back to first when persisted missing', () async {
        final svc = ActiveCharacterPreferenceService(prefs: prefs, auth: auth);
        await svc.setActiveCharacterId(tenantA, 'gone');

        final active = await svc.reconcileOwnedCharacters(
          tenantA,
          const ['char-a', 'char-b'],
        );
        expect(active, 'char-a');
        expect(await svc.getActiveCharacterId(tenantA), 'char-a');
      });
    });
  });

  group('ActiveCharacterSelection', () {
    test('showSwitcher only when 2+ characters', () {
      expect(ActiveCharacterSelection.showSwitcher(0), isFalse);
      expect(ActiveCharacterSelection.showSwitcher(1), isFalse);
      expect(ActiveCharacterSelection.showSwitcher(2), isTrue);
      expect(ActiveCharacterSelection.showSwitcher(5), isTrue);
    });

    test('resolve follows 0 / 1 / 2+ rules', () {
      expect(
        ActiveCharacterSelection.resolve(
          ownedCharacterIds: const [],
          persistedId: 'x',
        ),
        isNull,
      );
      expect(
        ActiveCharacterSelection.resolve(
          ownedCharacterIds: const ['solo'],
          persistedId: null,
        ),
        'solo',
      );
      expect(
        ActiveCharacterSelection.resolve(
          ownedCharacterIds: const ['a', 'b'],
          persistedId: 'b',
        ),
        'b',
      );
      expect(
        ActiveCharacterSelection.resolve(
          ownedCharacterIds: const ['a', 'b'],
          persistedId: 'missing',
        ),
        'a',
      );
    });
  });
}
