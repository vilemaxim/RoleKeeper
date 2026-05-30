import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import '../helpers/game_tenant_test_paths.dart';
import 'package:rolekeeper/models/character.dart';
import 'package:rolekeeper/models/death_rules.dart';
import 'package:rolekeeper/services/character_status_service.dart';
import 'package:rolekeeper/services/death_timer_service.dart';
import 'package:rolekeeper/widgets/death_timer_global_listener.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    DeathTimerService.testClock = null;
    DeathTimerService.instance.clear();
  });

  group('Death timer across navigation', () {
    testWidgets(
      'death dialog appears on current route when timer dies in background',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();
        final user = MockUser(uid: 'player-1', email: 'p@test.com');
        final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
        final fake = FakeFirebaseFirestore();
        await seedGameTenantDocs(fake, kTestGameTenant);
        final statusSvc = CharacterStatusService(
          firestore: fake,
          auth: auth,
          tenant: kTestGameTenant,
        );

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navKey,
            builder: (context, child) => DeathTimerGlobalListener(
              navigatorKey: navKey,
              statusService: statusSvc,
              child: child ?? const SizedBox.shrink(),
            ),
            home: Scaffold(
              body: TextButton(
                onPressed: () {
                  navKey.currentState!.push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                        key: Key('away'),
                        body: Text('Away page'),
                      ),
                    ),
                  );
                },
                child: const Text('Leave death screen'),
              ),
            ),
          ),
        );

        var clock = DateTime.utc(2025, 6, 1, 12, 0, 0);
        DeathTimerService.testClock = () => clock;

        final character = const Character(
          id: 'c1',
          shortId: 'A1B',
          ownerId: 'player-1',
          name: 'Hero',
        );
        final rules = DeathRules(
          enabled: true,
          countSeconds: 10,
          stages: const [],
          interventionEnabled: false,
          interventionCountSeconds: 60,
          afterDeathTimerText: 'Custom death.',
        );

        DeathTimerService.instance.setActive(
          ActiveDeathTimer(
            character: character,
            rules: rules,
            activityEventId: 'evt-1',
            deathCountStartedAt: clock,
          ),
        );
        await tester.pump();

        await tester.tap(find.text('Leave death screen'));
        await tester.pumpAndSettle();
        expect(find.text('Away page'), findsOneWidget);

        clock = clock.add(const Duration(seconds: 11));
        final transitioned = DeathTimerService.instance.tick();
        expect(transitioned, isTrue);
        expect(DeathTimerService.instance.active?.phase, DeathTimerPhase.dead);
        DeathTimerService.instance.notifyListeners();
        await tester.pump();
        await tester.pump();

        expect(find.text('Death'), findsOneWidget);
        expect(find.textContaining('Custom death'), findsOneWidget);

        // Cancel periodic ticker so the test binding does not report pending timers.
        DeathTimerService.instance.clear();
        await tester.pump();
      },
    );

    test(
      'remaining seconds drop while timer runs without DeathTimerScreen mounted',
      () {
        var clock = DateTime.utc(2025, 6, 2, 8, 0, 0);
        DeathTimerService.testClock = () => clock;
        const character = Character(
          id: 'c2',
          shortId: 'B2C',
          ownerId: 'u',
          name: 'X',
        );
        final rules = DeathRules(
          enabled: true,
          countSeconds: 100,
          stages: const [],
          interventionEnabled: false,
          interventionCountSeconds: 60,
        );
        DeathTimerService.instance.setActive(
          ActiveDeathTimer(
            character: character,
            rules: rules,
            activityEventId: 'e',
            deathCountStartedAt: clock,
          ),
        );
        expect(DeathTimerService.instance.getRemainingSeconds(), 100);
        clock = clock.add(const Duration(seconds: 30));
        expect(DeathTimerService.instance.getRemainingSeconds(), 70);
      },
    );
  });
}
