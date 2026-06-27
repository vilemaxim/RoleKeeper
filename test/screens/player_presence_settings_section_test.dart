import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/models/location_tracking_rules.dart';
import 'package:rolekeeper/models/member_presence.dart';
import 'package:rolekeeper/screens/player_presence_settings_section.dart';
import 'package:rolekeeper/services/location_tracking_rules_repository.dart';
import 'package:rolekeeper/services/member_presence_repository.dart';
import 'package:rolekeeper/services/game_context_service.dart';
import 'package:rolekeeper/utils/game_firestore_paths.dart';

import '../helpers/game_tenant_test_paths.dart';

class _RecordingMemberPresenceRepository extends MemberPresenceRepository {
  _RecordingMemberPresenceRepository({
    required super.firestore,
    required super.auth,
    required super.tenant,
    required this.initial,
  });

  final MemberPresence initial;
  MemberPresence? lastPresenceRead;
  bool? lastLocationOptIn;
  PresenceState? lastPresenceState;

  @override
  Future<MemberPresence> getPresence() async {
    lastPresenceRead = initial;
    return initial;
  }

  @override
  Future<void> setLocationOptIn(bool optedIn) async {
    lastLocationOptIn = optedIn;
  }

  @override
  Future<void> setPresenceState(PresenceState state) async {
    lastPresenceState = state;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late MockUser user;

  setUp(() async {
    GameContextService.instance.currentTenantForTest = kTestGameTenant;
    user = MockUser(uid: 'player-1', email: 'p@example.com');
    firestore = FakeFirebaseFirestore();
    await seedGameTenantDocs(firestore, kTestGameTenant);
  });

  tearDown(GameContextService.instance.resetForTest);

  Future<void> seedLocationRules({required bool enabled}) async {
    await GameFirestorePaths.locationTrackingRules(firestore, kTestGameTenant)
        .set(LocationTrackingRules(
      enabled: enabled,
      pingIntervalSeconds: 60,
    ).toMap());
  }

  Widget wrap({
    required MemberPresenceRepository presenceRepo,
    LocationTrackingRulesRepository? rulesRepo,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PlayerPresenceSettingsSection(
          presenceRepository: presenceRepo,
          locationRulesRepository: rulesRepo ??
              LocationTrackingRulesRepository(
                firestore: firestore,
                tenant: kTestGameTenant,
              ),
        ),
      ),
    );
  }

  group('PlayerPresenceSettingsSection', () {
    testWidgets('hidden when location tracking is disabled for the LARP',
        (tester) async {
      await seedLocationRules(enabled: false);

      final presenceRepo = _RecordingMemberPresenceRepository(
        firestore: firestore,
        auth: MockFirebaseAuth(signedIn: true, mockUser: user),
        tenant: kTestGameTenant,
        initial: MemberPresence.defaultPresence,
      );

      await tester.pumpWidget(wrap(presenceRepo: presenceRepo));
      await tester.pumpAndSettle();

      expect(find.text('Location sharing'), findsNothing);
      expect(find.text('In game'), findsNothing);
    });

    testWidgets('shows toggles and copy when location tracking is enabled',
        (tester) async {
      await seedLocationRules(enabled: true);

      final presenceRepo = _RecordingMemberPresenceRepository(
        firestore: firestore,
        auth: MockFirebaseAuth(signedIn: true, mockUser: user),
        tenant: kTestGameTenant,
        initial: const MemberPresence(
          locationOptIn: false,
          presenceState: PresenceState.inGame,
        ),
      );

      await tester.pumpWidget(wrap(presenceRepo: presenceRepo));
      await tester.pumpAndSettle();

      expect(find.text('Location sharing'), findsOneWidget);
      expect(find.text('In game'), findsOneWidget);
      expect(
        find.textContaining('voluntary'),
        findsOneWidget,
      );
      expect(
        find.textContaining('anti-cheat'),
        findsOneWidget,
      );
      expect(
        find.textContaining('does not stop'),
        findsOneWidget,
      );
      expect(
        find.textContaining('location sharing continues'),
        findsOneWidget,
      );
    });

    testWidgets('loads current values on open', (tester) async {
      await seedLocationRules(enabled: true);

      final presenceRepo = _RecordingMemberPresenceRepository(
        firestore: firestore,
        auth: MockFirebaseAuth(signedIn: true, mockUser: user),
        tenant: kTestGameTenant,
        initial: const MemberPresence(
          locationOptIn: true,
          presenceState: PresenceState.outOfGame,
        ),
      );

      await tester.pumpWidget(wrap(presenceRepo: presenceRepo));
      await tester.pumpAndSettle();

      expect(presenceRepo.lastPresenceRead?.locationOptIn, isTrue);
      expect(presenceRepo.lastPresenceRead?.presenceState,
          PresenceState.outOfGame);

      final locationSwitch = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Location sharing'),
      );
      expect(locationSwitch.value, isTrue);

      final presenceSwitch = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'In game'),
      );
      expect(presenceSwitch.value, isFalse);
    });

    testWidgets('persists location opt-in when toggled', (tester) async {
      await seedLocationRules(enabled: true);

      final presenceRepo = _RecordingMemberPresenceRepository(
        firestore: firestore,
        auth: MockFirebaseAuth(signedIn: true, mockUser: user),
        tenant: kTestGameTenant,
        initial: MemberPresence.defaultPresence,
      );

      await tester.pumpWidget(wrap(presenceRepo: presenceRepo));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SwitchListTile, 'Location sharing'));
      await tester.pumpAndSettle();

      expect(presenceRepo.lastLocationOptIn, isTrue);
    });

    testWidgets('persists presence state when toggled', (tester) async {
      await seedLocationRules(enabled: true);

      final presenceRepo = _RecordingMemberPresenceRepository(
        firestore: firestore,
        auth: MockFirebaseAuth(signedIn: true, mockUser: user),
        tenant: kTestGameTenant,
        initial: const MemberPresence(
          locationOptIn: true,
          presenceState: PresenceState.inGame,
        ),
      );

      await tester.pumpWidget(wrap(presenceRepo: presenceRepo));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SwitchListTile, 'In game'));
      await tester.pumpAndSettle();

      expect(presenceRepo.lastPresenceState, PresenceState.outOfGame);
    });
  });
}
