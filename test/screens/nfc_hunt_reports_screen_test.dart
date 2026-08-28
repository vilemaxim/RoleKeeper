import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/models/activity_event.dart';
import 'package:rolekeeper/models/game_role.dart';
import 'package:rolekeeper/models/nfc_hunt.dart';
import 'package:rolekeeper/models/nfc_hunt_scan.dart';
import 'package:rolekeeper/models/nfc_hunt_tag.dart';
import 'package:rolekeeper/screens/nfc_hunt_reports_screen.dart';

/// In-memory fake for hunt report data (no Firebase).
class _FakeNfcHuntReportsDataSource implements NfcHuntReportsDataSource {
  _FakeNfcHuntReportsDataSource({
    this.tags = const [],
    this.scans = const [],
    this.reviewScans = const [],
  });

  final List<NfcHuntTag> tags;
  final List<NfcHuntScan> scans;
  final List<NfcHuntScan> reviewScans;

  @override
  Future<List<NfcHuntTag>> loadTags(String huntId) async => tags;

  @override
  Future<List<NfcHuntScan>> loadScans(String huntId) async => scans;

  @override
  Future<List<NfcHuntScan>> loadReviewScans(String huntId) async =>
      reviewScans;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const hunt = NfcHunt(
    id: 'hunt-forest',
    enabled: true,
    name: 'Forest Trail',
    expectedTagCount: 5,
    placerUids: [],
  );

  Widget wrapReports({
    required GameRole gameRole,
    NfcHuntReportsDataSource? dataSource,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: NfcHuntReportsScreen(
          gameRole: gameRole,
          hunt: hunt,
          dataSource: dataSource,
        ),
      ),
    );
  }

  group('NfcHuntReportsScreen access gate', () {
    testWidgets('staff sees report sections', (tester) async {
      final dataSource = _FakeNfcHuntReportsDataSource(
        tags: [
          NfcHuntTag(
            tagUid: 'tag-oak',
            placement: NfcHuntPlacement.fixed,
            registeredByUid: 'organizer-1',
            registeredAt: DateTime(2026, 1, 1),
            label: 'Oak grove',
          ),
        ],
        scans: [
          NfcHuntScan(
            id: 'scan-1',
            characterId: 'char-1',
            ownerUid: 'player-1',
            tagUid: 'tag-oak',
            scannedAt: DateTime(2026, 1, 2),
            queuedOffline: false,
            tenantKey: 'rk-test.local::default',
            huntId: hunt.id,
          ),
        ],
        reviewScans: [
          NfcHuntScan(
            id: 'review-1',
            characterId: 'char-2',
            ownerUid: 'player-2',
            tagUid: 'tag-unknown',
            scannedAt: DateTime(2026, 1, 3),
            queuedOffline: false,
            tenantKey: 'rk-test.local::default',
            huntId: hunt.id,
            reason: 'unknown_tag',
          ),
        ],
      );

      await tester.pumpWidget(
        wrapReports(
          gameRole: GameRole.staff,
          dataSource: dataSource,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tags'), findsOneWidget);
      expect(find.text('Scans'), findsOneWidget);
      expect(find.text('Review queue'), findsOneWidget);
      expect(find.text('Location mismatches'), findsOneWidget);
      expect(find.text('Oak grove'), findsOneWidget);
    });

    testWidgets('organizer sees report sections', (tester) async {
      await tester.pumpWidget(
        wrapReports(
          gameRole: GameRole.owner,
          dataSource: _FakeNfcHuntReportsDataSource(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tags'), findsOneWidget);
      expect(find.text('Scans'), findsOneWidget);
    });

    testWidgets('plain player is denied access', (tester) async {
      await tester.pumpWidget(
        wrapReports(
          gameRole: GameRole.player,
          dataSource: _FakeNfcHuntReportsDataSource(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tags'), findsNothing);
      expect(find.text('Scans'), findsNothing);
      expect(
        find.textContaining('staff'),
        findsOneWidget,
        reason: 'Player must see access-denied copy referencing staff role.',
      );
    });
  });

  group('NfcHuntReportsScreen location mismatches', () {
    testWidgets('lists flagged scan with distance in meters', (tester) async {
      const tagLocation = ActivityEventLocation(
        latitude: 45.5231,
        longitude: -122.6765,
      );
      const scanLocation = ActivityEventLocation(
        latitude: 45.5316,
        longitude: -122.6668,
      );

      final dataSource = _FakeNfcHuntReportsDataSource(
        tags: [
          NfcHuntTag(
            tagUid: 'tag-fixed',
            placement: NfcHuntPlacement.fixed,
            registeredByUid: 'organizer-1',
            registeredAt: DateTime(2026, 1, 1),
            label: 'Fixed marker',
            location: tagLocation,
          ),
        ],
        scans: [
          NfcHuntScan(
            id: 'scan-far',
            characterId: 'char-far',
            ownerUid: 'player-far',
            tagUid: 'tag-fixed',
            scannedAt: DateTime(2026, 1, 2, 14, 30),
            queuedOffline: false,
            tenantKey: 'rk-test.local::default',
            huntId: hunt.id,
            location: scanLocation,
          ),
        ],
      );

      await tester.pumpWidget(
        wrapReports(
          gameRole: GameRole.staff,
          dataSource: dataSource,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Location mismatches'));
      await tester.pumpAndSettle();

      expect(find.textContaining('char-far'), findsOneWidget);
      expect(find.textContaining('tag-fixed'), findsOneWidget);
      expect(find.textContaining('m'), findsWidgets);
      // Distance should be well over 50 m for these coordinates.
      expect(find.textContaining(RegExp(r'\d{3,}')), findsWidgets);
    });
  });
}
