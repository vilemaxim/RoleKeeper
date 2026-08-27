import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/models/activity_event.dart';
import 'package:rolekeeper/models/nfc_hunt.dart';
import 'package:rolekeeper/screens/nfc_hunt_scan_screen.dart';
import 'package:rolekeeper/services/nfc_hunt_scan_service.dart';

/// In-memory fake for player scan callables (no Firebase).
class _FakeNfcHuntScanService extends Fake implements NfcHuntScanService {
  NfcHuntScanResult nextResult = const NfcHuntScanResult(
    outcome: NfcHuntScanOutcome.credited,
    scanId: 'scan-1',
  );
  Map<String, dynamic>? lastArgs;
  Object? error;

  @override
  Future<NfcHuntScanResult> recordScan({
    required String huntId,
    required String characterId,
    required String tagUid,
    ActivityEventLocation? location,
    DateTime? clientScannedAt,
    bool queuedOffline = false,
  }) async {
    if (error != null) throw error!;
    lastArgs = {
      'huntId': huntId,
      'characterId': characterId,
      'tagUid': tagUid,
      'location': location,
      'queuedOffline': queuedOffline,
    };
    return nextResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const forestHunt = NfcHunt(
    id: 'hunt-forest',
    enabled: true,
    name: 'Forest Trail',
    expectedTagCount: 5,
    placerUids: [],
  );

  const disabledHunt = NfcHunt(
    id: 'hunt-ruins',
    enabled: false,
    name: 'Ruins',
    expectedTagCount: 3,
    placerUids: [],
  );

  Widget wrapScan({
    required List<NfcHunt> hunts,
    String? activeCharacterId,
    NfcHuntScanService? scanService,
    Future<String?> Function(BuildContext context)? scanQrCode,
    Future<ActivityEventLocation?> Function()? captureLocation,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: NfcHuntScanScreen(
          hunts: hunts,
          activeCharacterId: activeCharacterId,
          scanService: scanService,
          expectedTenantKey: kTestTenantKey,
          scanQrCode: scanQrCode,
          captureLocation: captureLocation,
        ),
      ),
    );
  }

  Finder scanButton() => find.textContaining('Scan hunt tag');

  group('NfcHuntScanScreen entry visibility', () {
    testWidgets('scan button hidden when no enabled hunts', (tester) async {
      await tester.pumpWidget(
        wrapScan(
          hunts: const [disabledHunt],
          activeCharacterId: 'char-1',
        ),
      );
      await tester.pumpAndSettle();

      expect(scanButton(), findsNothing);
    });

    testWidgets('scan button hidden when hunts list is empty', (tester) async {
      await tester.pumpWidget(
        wrapScan(
          hunts: const [],
          activeCharacterId: 'char-1',
        ),
      );
      await tester.pumpAndSettle();

      expect(scanButton(), findsNothing);
    });

    testWidgets('scan button visible when at least one hunt is enabled',
        (tester) async {
      await tester.pumpWidget(
        wrapScan(
          hunts: const [disabledHunt, forestHunt],
          activeCharacterId: 'char-1',
        ),
      );
      await tester.pumpAndSettle();

      expect(scanButton(), findsOneWidget);
    });

    testWidgets('scan button disabled without active character',
        (tester) async {
      await tester.pumpWidget(
        wrapScan(
          hunts: const [forestHunt],
          activeCharacterId: null,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Select or create a character first'),
        findsOneWidget,
      );

      // Button may still be present but must not start a scan.
      final button = scanButton();
      if (button.evaluate().isNotEmpty) {
        await tester.tap(button);
        await tester.pumpAndSettle();
      }
      // No scan flow SnackBar from a successful scan attempt.
      expect(find.textContaining('already scanned'), findsNothing);
      expect(find.textContaining('credited'), findsNothing);
    });
  });

  group('NfcHuntScanScreen outcome UX', () {
    testWidgets('credited shows success message', (tester) async {
      final service = _FakeNfcHuntScanService()
        ..nextResult = const NfcHuntScanResult(
          outcome: NfcHuntScanOutcome.credited,
          scanId: 'scan-99',
        );

      await tester.pumpWidget(
        wrapScan(
          hunts: const [forestHunt],
          activeCharacterId: 'char-42',
          scanService: service,
          scanQrCode: (_) async =>
              'rolekeeper:scavenger:v1:$kTestTenantKey:hunt-forest:tag-oak',
          captureLocation: () async => const ActivityEventLocation(
            latitude: 45.5,
            longitude: -122.6,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(scanButton());
      await tester.pumpAndSettle();

      expect(service.lastArgs, isNotNull);
      expect(service.lastArgs!['characterId'], 'char-42');
      expect(service.lastArgs!['tagUid'], 'tag-oak');
      expect(service.lastArgs!['huntId'], 'hunt-forest');
      expect(service.lastArgs!['location'], isNotNull);
      expect(find.byType(SnackBar), findsOneWidget);
      // Success copy — credited / tag found / success.
      expect(
        find.textContaining(RegExp(r'credit|success|scanned', caseSensitive: false)),
        findsWidgets,
      );
    });

    testWidgets('already_scanned shows informational message', (tester) async {
      final service = _FakeNfcHuntScanService()
        ..nextResult = const NfcHuntScanResult(
          outcome: NfcHuntScanOutcome.alreadyScanned,
        );

      await tester.pumpWidget(
        wrapScan(
          hunts: const [forestHunt],
          activeCharacterId: 'char-42',
          scanService: service,
          scanQrCode: (_) async =>
              'rolekeeper:scavenger:v1:$kTestTenantKey:hunt-forest:tag-oak',
          captureLocation: () async => null,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(scanButton());
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('You already scanned this tag'), findsOneWidget);
    });

    testWidgets('unknown_tag asks player to take a photo', (tester) async {
      final service = _FakeNfcHuntScanService()
        ..nextResult = const NfcHuntScanResult(
          outcome: NfcHuntScanOutcome.unknownTag,
        );

      await tester.pumpWidget(
        wrapScan(
          hunts: const [forestHunt],
          activeCharacterId: 'char-42',
          scanService: service,
          scanQrCode: (_) async =>
              'rolekeeper:scavenger:v1:$kTestTenantKey:hunt-forest:tag-missing',
          captureLocation: () async => null,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(scanButton());
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.textContaining('take a photo in case plot needs it'),
        findsOneWidget,
      );
    });

    testWidgets('captures location before calling recordScan', (tester) async {
      final service = _FakeNfcHuntScanService();
      var captureCalls = 0;
      const loc = ActivityEventLocation(latitude: 1.25, longitude: 2.5);

      await tester.pumpWidget(
        wrapScan(
          hunts: const [forestHunt],
          activeCharacterId: 'char-42',
          scanService: service,
          scanQrCode: (_) async =>
              'rolekeeper:scavenger:v1:$kTestTenantKey:hunt-forest:tag-gps',
          captureLocation: () async {
            captureCalls++;
            return loc;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(scanButton());
      await tester.pumpAndSettle();

      expect(captureCalls, 1);
      expect(service.lastArgs!['location'], loc);
    });
  });

  group('Home screen hunt scan entry contract', () {
    late final String homeSrc;

    setUpAll(() {
      homeSrc = File('lib/screens/home_screen.dart').readAsStringSync();
    });

    test('home exposes Scan hunt tag entry', () {
      expect(
        homeSrc.contains('Scan hunt tag'),
        isTrue,
        reason: 'Home must offer a "Scan hunt tag" entry when hunts are enabled.',
      );
    });

    test('home watches or streams hunts for enabled gate', () {
      final watches = homeSrc.contains('watchHunts') ||
          homeSrc.contains('enabledHunts') ||
          homeSrc.contains('NfcHuntScan') ||
          homeSrc.contains('nfc_hunt');
      expect(
        watches,
        isTrue,
        reason: 'Home must gate scan entry on enabled hunts (stream/watch).',
      );
    });

    test('home gates scan on active character preference', () {
      // Character gate may live on home or on the scan screen navigated from home.
      final scanScreenSrc =
          File('lib/screens/nfc_hunt_scan_screen.dart').readAsStringSync();
      final gates = homeSrc.contains('Select or create a character first') ||
          scanScreenSrc.contains('Select or create a character first') ||
          scanScreenSrc.contains('activeCharacterId') ||
          scanScreenSrc.contains('ActiveCharacterPreferenceService');
      expect(
        gates,
        isTrue,
        reason: 'Scan flow must reuse active-character gating copy/pattern.',
      );
    });
  });
}
