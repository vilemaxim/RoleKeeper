import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/models/activity_event.dart';
import 'package:rolekeeper/models/game_role.dart';
import 'package:rolekeeper/models/nfc_hunt.dart';
import 'package:rolekeeper/models/nfc_hunt_tag.dart';
import 'package:rolekeeper/screens/nfc_hunt_tag_register_screen.dart';
import 'package:rolekeeper/services/nfc_hunt_service.dart';

class _FakeNfcHuntService extends Fake implements NfcHuntService {
  _FakeNfcHuntService({List<NfcHuntTag>? tags})
      : tags = List<NfcHuntTag>.from(tags ?? const []);

  final List<NfcHuntTag> tags;
  Map<String, dynamic>? lastRegisterArgs;
  Object? registerError;

  @override
  Future<List<NfcHuntTag>> listTags(String huntId) async =>
      List<NfcHuntTag>.from(tags);

  @override
  Future<String> registerTag({
    required String huntId,
    required String tagUid,
    required NfcHuntPlacement placement,
    String? label,
    ActivityEventLocation? location,
  }) async {
    if (registerError != null) throw registerError!;
    lastRegisterArgs = {
      'huntId': huntId,
      'tagUid': tagUid,
      'placement': placement,
      'label': label,
      'location': location,
    };
    tags.add(
      NfcHuntTag(
        tagUid: tagUid,
        placement: placement,
        registeredByUid: 'tester',
        registeredAt: DateTime.utc(2026, 8, 27),
        label: label,
        location: location,
      ),
    );
    return tagUid;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const hunt = NfcHunt(
    id: 'hunt-forest',
    enabled: true,
    name: 'Forest Trail',
    expectedTagCount: 5,
    placerUids: ['placer-uid'],
  );

  Widget wrapRegister({
    required NfcHuntService service,
    GameRole gameRole = GameRole.owner,
    String currentUid = 'org-uid',
    Future<String?> Function(BuildContext context)? scanQrCode,
    Future<ActivityEventLocation?> Function()? captureLocation,
  }) {
    return MaterialApp(
      home: NfcHuntTagRegisterScreen(
        hunt: hunt,
        gameRole: gameRole,
        currentUid: currentUid,
        huntService: service,
        expectedTenantKey: kTestTenantKey,
        scanQrCode: scanQrCode,
        captureLocation: captureLocation,
      ),
    );
  }

  group('NfcHuntTagRegisterScreen', () {
    testWidgets('lists registered tags and shows progress', (tester) async {
      final service = _FakeNfcHuntService(
        tags: [
          NfcHuntTag(
            tagUid: 'tag-oak',
            placement: NfcHuntPlacement.fixed,
            registeredByUid: 'org-uid',
            registeredAt: DateTime.utc(2026, 8, 1),
            label: 'Oak grove',
          ),
        ],
      );

      await tester.pumpWidget(wrapRegister(service: service));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 / 5'), findsOneWidget);
      expect(find.text('Oak grove'), findsOneWidget);
      expect(find.textContaining('tag-oak'), findsOneWidget);
      expect(find.textContaining('Fixed'), findsOneWidget);
    });

    testWidgets('scan + register floating tag calls service without location',
        (tester) async {
      final service = _FakeNfcHuntService();
      var captureCalls = 0;

      await tester.pumpWidget(
        wrapRegister(
          service: service,
          scanQrCode: (_) async =>
              'rolekeeper:scavenger:v1:$kTestTenantKey:hunt-forest:tag-new',
          captureLocation: () async {
            captureCalls++;
            return const ActivityEventLocation(
              latitude: 1,
              longitude: 2,
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Scan'));
      await tester.pumpAndSettle();

      // Default / select Floating.
      final floating = find.text('Floating');
      if (floating.evaluate().isNotEmpty) {
        await tester.tap(floating);
        await tester.pumpAndSettle();
      }

      await tester.enterText(find.byType(TextField).first, 'New label');
      await tester.tap(find.textContaining('Register tag'));
      await tester.pumpAndSettle();

      expect(service.lastRegisterArgs, isNotNull);
      expect(service.lastRegisterArgs!['tagUid'], 'tag-new');
      expect(service.lastRegisterArgs!['placement'], NfcHuntPlacement.floating);
      expect(service.lastRegisterArgs!['label'], 'New label');
      expect(service.lastRegisterArgs!['location'], isNull);
      expect(captureCalls, 0);
    });

    testWidgets('fixed placement captures GPS before register', (tester) async {
      final service = _FakeNfcHuntService();
      const loc = ActivityEventLocation(latitude: 45.5, longitude: -122.6);

      await tester.pumpWidget(
        wrapRegister(
          service: service,
          scanQrCode: (_) async =>
              'rolekeeper:scavenger:v1:$kTestTenantKey:hunt-forest:tag-gps',
          captureLocation: () async => loc,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Scan'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fixed'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Register tag'));
      await tester.pumpAndSettle();

      expect(service.lastRegisterArgs!['placement'], NfcHuntPlacement.fixed);
      expect(service.lastRegisterArgs!['location'], loc);
    });

    testWidgets('rejects wrong-tenant QR with user-facing error', (tester) async {
      final service = _FakeNfcHuntService();

      await tester.pumpWidget(
        wrapRegister(
          service: service,
          scanQrCode: (_) async =>
              'rolekeeper:scavenger:v1:other.instance::evt:hunt-forest:tag-x',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Scan'));
      await tester.pumpAndSettle();

      expect(service.lastRegisterArgs, isNull);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('tenant'), findsWidgets);
    });

    testWidgets('rejects malformed QR with user-facing error', (tester) async {
      final service = _FakeNfcHuntService();

      await tester.pumpWidget(
        wrapRegister(
          service: service,
          scanQrCode: (_) async => 'not-a-valid-qr',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Scan'));
      await tester.pumpAndSettle();

      expect(service.lastRegisterArgs, isNull);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
