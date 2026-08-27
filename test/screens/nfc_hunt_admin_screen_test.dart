import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/models/game_role.dart';
import 'package:rolekeeper/models/nfc_hunt.dart';
import 'package:rolekeeper/models/nfc_hunt_tag.dart';
import 'package:rolekeeper/screens/nfc_hunt_admin_screen.dart';
import 'package:rolekeeper/screens/nfc_hunt_tag_register_screen.dart';
import 'package:rolekeeper/services/nfc_hunt_service.dart';

/// In-memory fake used by widget tests (no Firestore / callables).
class _FakeNfcHuntService extends Fake implements NfcHuntService {
  _FakeNfcHuntService({List<NfcHunt>? hunts, List<NfcHuntTag>? tags})
      : hunts = List<NfcHunt>.from(hunts ?? const []),
        tags = List<NfcHuntTag>.from(tags ?? const []);

  final List<NfcHunt> hunts;
  final List<NfcHuntTag> tags;
  int createCallCount = 0;
  bool? lastEnabled;
  List<String>? lastPlacerUids;

  @override
  Future<List<NfcHunt>> listHunts() async => List<NfcHunt>.from(hunts);

  @override
  Future<NfcHunt> createHunt({
    required String name,
    required int expectedTagCount,
  }) async {
    createCallCount++;
    final hunt = NfcHunt(
      id: 'hunt-${hunts.length + 1}',
      enabled: false,
      name: name,
      expectedTagCount: expectedTagCount,
      placerUids: const [],
    );
    hunts.add(hunt);
    return hunt;
  }

  @override
  Future<void> setEnabled(String huntId, bool enabled) async {
    lastEnabled = enabled;
    final i = hunts.indexWhere((h) => h.id == huntId);
    if (i >= 0) {
      final h = hunts[i];
      hunts[i] = NfcHunt(
        id: h.id,
        enabled: enabled,
        name: h.name,
        expectedTagCount: h.expectedTagCount,
        placerUids: h.placerUids,
        createdAt: h.createdAt,
        updatedAt: h.updatedAt,
      );
    }
  }

  @override
  Future<void> setPlacerUids(String huntId, List<String> placerUids) async {
    lastPlacerUids = placerUids;
    final i = hunts.indexWhere((h) => h.id == huntId);
    if (i >= 0) {
      final h = hunts[i];
      hunts[i] = NfcHunt(
        id: h.id,
        enabled: h.enabled,
        name: h.name,
        expectedTagCount: h.expectedTagCount,
        placerUids: placerUids,
        createdAt: h.createdAt,
        updatedAt: h.updatedAt,
      );
    }
  }

  @override
  Future<List<NfcHuntTag>> listTags(String huntId) async =>
      List<NfcHuntTag>.from(tags);
}

Widget wrapAdmin({
  required GameRole gameRole,
  required String currentUid,
  required NfcHuntService service,
  List<Map<String, String>> members = const [],
}) {
  return MaterialApp(
    home: NfcHuntAdminScreen(
      gameRole: gameRole,
      currentUid: currentUid,
      huntService: service,
      members: members,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const forestHunt = NfcHunt(
    id: 'hunt-forest',
    enabled: true,
    name: 'Forest Trail',
    expectedTagCount: 5,
    placerUids: ['placer-uid'],
  );

  group('NfcHuntAdminScreen organizer gates', () {
    testWidgets('organizer sees create, enable toggle, and placers UI',
        (tester) async {
      final service = _FakeNfcHuntService(hunts: [forestHunt]);

      await tester.pumpWidget(
        wrapAdmin(
          gameRole: GameRole.owner,
          currentUid: 'org-uid',
          service: service,
          members: const [
            {'uid': 'placer-uid', 'displayName': 'Pat Placer'},
            {'uid': 'player-uid', 'displayName': 'Sam Player'},
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Scavenger hunts'), findsWidgets);
      expect(find.text('Forest Trail'), findsOneWidget);
      expect(find.textContaining('Create'), findsWidgets);
      expect(
        find.widgetWithText(SwitchListTile, 'Enabled'),
        findsOneWidget,
      );
      expect(find.textContaining('Placer'), findsWidgets);
      expect(find.textContaining('1 / 5'), findsNothing); // no tags yet
      expect(find.textContaining('0 / 5'), findsOneWidget);
    });

    testWidgets('superAdmin sees hunt management controls', (tester) async {
      final service = _FakeNfcHuntService(hunts: [forestHunt]);

      await tester.pumpWidget(
        wrapAdmin(
          gameRole: GameRole.superAdmin,
          currentUid: 'admin-uid',
          service: service,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Create'), findsWidgets);
      expect(
        find.widgetWithText(SwitchListTile, 'Enabled'),
        findsOneWidget,
      );
    });

    testWidgets('non-organizer does not see create/toggle/placer management',
        (tester) async {
      final service = _FakeNfcHuntService(hunts: [forestHunt]);

      await tester.pumpWidget(
        wrapAdmin(
          gameRole: GameRole.player,
          currentUid: 'player-uid',
          service: service,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Create'), findsNothing);
      expect(
        find.widgetWithText(SwitchListTile, 'Enabled'),
        findsNothing,
      );
      expect(find.textContaining('Add placer'), findsNothing);
    });

    testWidgets('placer (non-organizer) can open tag registration',
        (tester) async {
      final service = _FakeNfcHuntService(hunts: [forestHunt]);

      await tester.pumpWidget(
        wrapAdmin(
          gameRole: GameRole.player,
          currentUid: 'placer-uid',
          service: service,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Forest Trail'), findsOneWidget);
      final registerFinder = find.textContaining('Register');
      expect(registerFinder, findsWidgets);

      await tester.tap(registerFinder.first);
      await tester.pumpAndSettle();

      expect(find.byType(NfcHuntTagRegisterScreen), findsOneWidget);
    });

    testWidgets('plain player cannot open tag registration', (tester) async {
      final service = _FakeNfcHuntService(hunts: [forestHunt]);

      await tester.pumpWidget(
        wrapAdmin(
          gameRole: GameRole.player,
          currentUid: 'other-player',
          service: service,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Register'), findsNothing);
      expect(find.byType(NfcHuntTagRegisterScreen), findsNothing);
    });

    testWidgets('organizer can open tag registration', (tester) async {
      final service = _FakeNfcHuntService(hunts: [forestHunt]);

      await tester.pumpWidget(
        wrapAdmin(
          gameRole: GameRole.owner,
          currentUid: 'org-uid',
          service: service,
        ),
      );
      await tester.pumpAndSettle();

      final registerFinder = find.textContaining('Register');
      expect(registerFinder, findsWidgets);
      await tester.tap(registerFinder.first);
      await tester.pumpAndSettle();
      expect(find.byType(NfcHuntTagRegisterScreen), findsOneWidget);
    });
  });
}
