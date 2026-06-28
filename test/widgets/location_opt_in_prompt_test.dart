import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/services/game_context_service.dart';
import 'package:rolekeeper/services/member_presence_repository.dart';
import 'package:rolekeeper/widgets/location_opt_in_prompt.dart';

import '../helpers/game_tenant_test_paths.dart';

class _RecordingMemberPresenceRepository extends MemberPresenceRepository {
  _RecordingMemberPresenceRepository({
    required super.firestore,
    required super.auth,
    required super.tenant,
  });

  bool? lastLocationOptIn;

  @override
  Future<void> setLocationOptIn(bool optedIn) async {
    lastLocationOptIn = optedIn;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late MockUser user;
  late _RecordingMemberPresenceRepository presenceRepo;

  setUp(() async {
    GameContextService.instance.currentTenantForTest = kTestGameTenant;
    user = MockUser(uid: 'player-1', email: 'p@example.com');
    firestore = FakeFirebaseFirestore();
    await seedGameTenantDocs(firestore, kTestGameTenant);
    presenceRepo = _RecordingMemberPresenceRepository(
      firestore: firestore,
      auth: MockFirebaseAuth(signedIn: true, mockUser: user),
      tenant: kTestGameTenant,
    );
  });

  tearDown(GameContextService.instance.resetForTest);

  Widget wrap({
    required bool visible,
    VoidCallback? onOptInEnabled,
    VoidCallback? onDismiss,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: LocationOptInPrompt(
          presenceRepository: presenceRepo,
          visible: visible,
          onOptInEnabled: onOptInEnabled ?? () {},
          onDismiss: onDismiss,
        ),
      ),
    );
  }

  group('LocationOptInPrompt', () {
    testWidgets('shows prompt when tracking is active and player has not opted in',
        (tester) async {
      await tester.pumpWidget(wrap(visible: true));
      await tester.pumpAndSettle();

      expect(find.text('Share your location during the event'), findsOneWidget);
      expect(find.text('Enable location sharing'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
    });

    testWidgets('hidden when player already opted in', (tester) async {
      await tester.pumpWidget(wrap(visible: false));
      await tester.pumpAndSettle();

      expect(find.text('Share your location during the event'), findsNothing);
    });

    testWidgets('Enable writes locationOptIn and triggers ping sync callback',
        (tester) async {
      var syncCalled = false;

      await tester.pumpWidget(
        wrap(
          visible: true,
          onOptInEnabled: () => syncCalled = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enable location sharing'));
      await tester.pumpAndSettle();

      expect(presenceRepo.lastLocationOptIn, isTrue);
      expect(syncCalled, isTrue);
    });

    testWidgets('Not now dismisses prompt for the current session', (tester) async {
      var dismissed = false;

      await tester.pumpWidget(
        wrap(
          visible: true,
          onDismiss: () => dismissed = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
      expect(find.text('Share your location during the event'), findsNothing);
    });
  });
}
