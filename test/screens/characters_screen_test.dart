import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/models/game_role.dart';
import 'package:rolekeeper/models/larp_manager_registration_check_result.dart';
import 'package:rolekeeper/screens/characters_screen.dart';
import 'package:rolekeeper/services/characters_repository.dart';
import 'package:rolekeeper/services/game_context_service.dart';
import 'package:rolekeeper/services/game_membership_service.dart';
import 'package:rolekeeper/services/larp_manager_registration_service.dart';
import 'package:rolekeeper/services/larp_registry_repository.dart';
import 'package:rolekeeper/utils/game_firestore_paths.dart';

import '../helpers/game_tenant_test_paths.dart';

/// Test double for [LarpManagerRegistrationService] that returns a canned
/// [LarpManagerRegistrationCheckResult] and records `forceRefresh` flags.
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
  final List<bool> forceRefreshCalls = <bool>[];

  @override
  Future<LarpManagerRegistrationCheckResult> verifyRegistrationForCurrentGame({
    bool forceRefresh = false,
  }) {
    forceRefreshCalls.add(forceRefresh);
    return onVerify();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late MockUser user;

  setUp(() async {
    GameContextService.instance.currentTenantForTest = kTestGameTenant;
    user = MockUser(uid: 'player-1', email: 'p@example.com');
    auth = MockFirebaseAuth(signedIn: true, mockUser: user);
    firestore = FakeFirebaseFirestore();
    await seedGameTenantDocs(firestore, kTestGameTenant);
    // Make the test user a member so getRoleInGame() returns a stable role.
    await GameFirestorePaths.member(firestore, kTestGameTenant, user.uid).set({
      'role': GameRole.player.wireName,
      'tenantKey': kTestGameTenant.tenantKey,
    });
  });

  tearDown(GameContextService.instance.resetForTest);

  Future<void> seedCharacter({
    required String name,
    required String ownerId,
  }) async {
    await GameFirestorePaths.characters(firestore, kTestGameTenant).add({
      'name': name,
      'ownerId': ownerId,
      'shortId': 'ABC',
      'isArchived': false,
      'updatedAt': DateTime.now(),
      'createdAt': DateTime.now(),
    });
  }

  Widget wrap({required LarpManagerRegistrationService registrationService}) {
    return MaterialApp(
      home: CharactersScreenBody(
        registrationService: registrationService,
        charactersRepository: CharactersRepository(
          firestore: firestore,
          auth: auth,
          tenant: kTestGameTenant,
        ),
        membershipService: GameMembershipService(
          firestore: firestore,
          auth: auth,
        ),
        auth: auth,
      ),
    );
  }

  group('CharactersScreen LM sync degraded banner', () {
    testWidgets(
      'hasCharacter=true + organizerSyncError shows banner AND list AND no red _syncError text',
      (tester) async {
        await seedCharacter(name: 'Aria', ownerId: user.uid);

        final svc = _FakeRegistrationService(
          auth: auth,
          onVerify: () async => const LarpManagerRegistrationCheckResult(
            registered: true,
            hasCharacter: true,
            organizerSyncError:
                "Couldn't refresh organizer permissions from LarpManager.",
          ),
        );

        await tester.pumpWidget(wrap(registrationService: svc));
        await tester.pumpAndSettle();

        // Character is listed (data is fine).
        expect(find.text('Aria'), findsOneWidget,
            reason: 'character list should render when hasCharacter is true');

        // Banner with organizer-specific copy is visible.
        expect(
          find.textContaining(
            'Couldn\'t refresh organizer permissions from LarpManager',
          ),
          findsOneWidget,
          reason: 'organizer sync banner copy should be visible',
        );
        expect(
          find.textContaining('LM Integration'),
          findsOneWidget,
          reason: 'organizer banner should reference LM Integration',
        );

        // When hasCharacter is true the empty-state body must NOT render at
        // all — the banner is the only error surface. The empty-state body
        // is the only place that renders the red `_syncError` text in the
        // existing implementation, so its absence is what we assert here.
        expect(
          find.text('No character yet'),
          findsNothing,
          reason:
              'empty-state body (which carries the red _syncError text) must not render when characters exist',
        );
      },
    );

    testWidgets(
      'hasCharacter=false + organizerSyncError suppresses generic "Create a character" copy',
      (tester) async {
        final svc = _FakeRegistrationService(
          auth: auth,
          onVerify: () async => const LarpManagerRegistrationCheckResult(
            registered: false,
            hasCharacter: false,
            organizerSyncError:
                "Couldn't refresh organizer permissions from LarpManager.",
          ),
        );

        await tester.pumpWidget(wrap(registrationService: svc));
        await tester.pumpAndSettle();

        // Banner is visible.
        expect(
          find.textContaining(
            'Couldn\'t refresh organizer permissions from LarpManager',
          ),
          findsOneWidget,
        );

        // The generic empty-state body that tells players to create a
        // character must NOT be shown — we don't actually know what state
        // they're in because the sync degraded.
        expect(
          find.textContaining(
            'Create a character on LarpManager for this event',
          ),
          findsNothing,
          reason:
              'generic empty-state copy must not appear when sync errored',
        );
      },
    );

    testWidgets(
      'all *SyncError fields null → no banner, existing behavior unchanged',
      (tester) async {
        await seedCharacter(name: 'Borin', ownerId: user.uid);

        final svc = _FakeRegistrationService(
          auth: auth,
          onVerify: () async => const LarpManagerRegistrationCheckResult(
            registered: true,
            hasCharacter: true,
          ),
        );

        await tester.pumpWidget(wrap(registrationService: svc));
        await tester.pumpAndSettle();

        // No banner text should appear when nothing failed.
        expect(
          find.textContaining('Couldn\'t refresh organizer permissions'),
          findsNothing,
        );
        expect(
          find.textContaining('Couldn\'t refresh event registrations'),
          findsNothing,
        );
        expect(
          find.textContaining('Couldn\'t sync characters'),
          findsNothing,
        );

        // Character still renders.
        expect(find.text('Borin'), findsOneWidget);
      },
    );

    testWidgets(
      'registrationSyncError shows registration-specific banner copy',
      (tester) async {
        final svc = _FakeRegistrationService(
          auth: auth,
          onVerify: () async => const LarpManagerRegistrationCheckResult(
            registered: false,
            hasCharacter: false,
            registrationSyncError:
                "Couldn't refresh event registrations from LarpManager.",
          ),
        );

        await tester.pumpWidget(wrap(registrationService: svc));
        await tester.pumpAndSettle();

        expect(
          find.textContaining(
            'Couldn\'t refresh event registrations from LarpManager',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'characterSyncError shows character-specific banner copy',
      (tester) async {
        await seedCharacter(name: 'Cara', ownerId: user.uid);

        final svc = _FakeRegistrationService(
          auth: auth,
          onVerify: () async => const LarpManagerRegistrationCheckResult(
            registered: true,
            hasCharacter: true,
            characterSyncError:
                "Couldn't sync characters from LarpManager. Showing last-known data.",
          ),
        );

        await tester.pumpWidget(wrap(registrationService: svc));
        await tester.pumpAndSettle();

        expect(
          find.textContaining(
            'Couldn\'t sync characters from LarpManager',
          ),
          findsOneWidget,
        );
        // Last-known data still renders.
        expect(find.text('Cara'), findsOneWidget);
      },
    );

    testWidgets(
      'Retry sync action calls verifyRegistrationForCurrentGame(forceRefresh: true)',
      (tester) async {
        final svc = _FakeRegistrationService(
          auth: auth,
          onVerify: () async => const LarpManagerRegistrationCheckResult(
            registered: false,
            hasCharacter: false,
            organizerSyncError:
                "Couldn't refresh organizer permissions from LarpManager.",
          ),
        );

        await tester.pumpWidget(wrap(registrationService: svc));
        await tester.pumpAndSettle();

        // The banner has a "Retry sync" action. Don't pin to a specific
        // button widget type — MaterialBanner.actions can be TextButton or
        // any other button; just locate the label and tap it.
        final retry = find.text('Retry sync');
        expect(retry, findsOneWidget,
            reason: 'banner should expose a Retry sync action');

        svc.forceRefreshCalls.clear();
        await tester.tap(retry);
        await tester.pumpAndSettle();

        expect(
          svc.forceRefreshCalls,
          contains(true),
          reason:
              'Retry sync must call verifyRegistrationForCurrentGame(forceRefresh: true)',
        );
      },
    );
  });

  group('LarpManagerRegistrationCheckResult.fromCallable', () {
    test('parses organizerSyncError, registrationSyncError, characterSyncError',
        () {
      final result = LarpManagerRegistrationCheckResult.fromCallable(
        <String, dynamic>{
          'registered': true,
          'hasCharacter': true,
          'organizerSyncError': 'org sync failed',
          'registrationSyncError': 'reg sync failed',
          'characterSyncError': 'char sync failed',
        },
      );

      expect(result.organizerSyncError, 'org sync failed');
      expect(result.registrationSyncError, 'reg sync failed');
      expect(result.characterSyncError, 'char sync failed');
    });

    test('defaults all *SyncError fields to null when absent', () {
      final result = LarpManagerRegistrationCheckResult.fromCallable(
        <String, dynamic>{
          'registered': false,
          'hasCharacter': false,
        },
      );

      expect(result.organizerSyncError, isNull);
      expect(result.registrationSyncError, isNull);
      expect(result.characterSyncError, isNull);
    });
  });
}
