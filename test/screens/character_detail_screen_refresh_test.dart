/// Widget tests for the Task 013 "Refresh my character" button that
/// lives in [CharacterDetailScreen]'s AppBar for LM-synced characters.
///
/// We inject a fake [CharacterSyncService] so the screen never touches
/// the real `httpsCallable('syncMyLarpManagerCharacterCallable')`
/// endpoint. The fake records the call and returns whatever the test
/// configures: a `{ok: true}` payload, a `{ok: false, error}` payload,
/// or a thrown [FirebaseFunctionsException].
///
/// These tests pin the four Task 013 frontend acceptance criteria:
///   1. Refresh icon button is PRESENT in the AppBar when
///      `character.larpManagerUuid != null`, and ABSENT when it is null.
///   2. Tapping the button shows a loading indicator and disables the
///      button while in flight (no second concurrent call possible).
///   3. On `{ok: true}` the snackbar reads "Character refreshed".
///   4. On `{ok: false, error: 'LM said no'}` the snackbar reads
///      "Could not refresh: LM said no".
///   5. On a thrown `FirebaseFunctionsException`, the snackbar reads
///      the `reportAppError(...).userMessage` (NOT the raw error
///      `toString()` and NOT a leaked "INTERNAL" / Firebase code).
library;

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/models/character.dart';
import 'package:rolekeeper/models/game_tenant_ref.dart';
import 'package:rolekeeper/screens/character_detail_screen.dart';
import 'package:rolekeeper/services/character_stats_repository.dart';
import 'package:rolekeeper/services/character_sync_service.dart';
import 'package:rolekeeper/services/game_context_service.dart';

import '../helpers/game_tenant_test_paths.dart';

class _FakeCharacterSyncService extends CharacterSyncService {
  _FakeCharacterSyncService({
    required this.onRefresh,
  }) : super();

  final Future<CharacterSyncResult> Function({
    required GameTenantRef tenant,
    required String characterUuid,
  }) onRefresh;

  final List<({GameTenantRef tenant, String characterUuid})> calls = [];

  @override
  Future<CharacterSyncResult> refresh({
    required GameTenantRef tenant,
    required String characterUuid,
  }) {
    calls.add((tenant: tenant, characterUuid: characterUuid));
    return onRefresh(tenant: tenant, characterUuid: characterUuid);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const heldrekUuid = 'oxe9sb0w02ig';

  late FakeFirebaseFirestore firestore;

  setUp(() async {
    GameContextService.instance.currentTenantForTest = kTestGameTenant;
    firestore = FakeFirebaseFirestore();
    await seedGameTenantDocs(firestore, kTestGameTenant);
  });

  tearDown(GameContextService.instance.resetForTest);

  CharacterStatsRepository repo() => CharacterStatsRepository(
        firestore: firestore,
        tenant: kTestGameTenant,
      );

  Character lmCharacter() => Character(
        id: heldrekUuid,
        shortId: 'ABC',
        ownerId: 'p1',
        name: 'Heldrek',
        larpManagerUuid: heldrekUuid,
        source: 'larpmanager',
      );

  Character manualCharacter() => const Character(
        id: 'manual-1',
        shortId: 'DEF',
        ownerId: 'p1',
        name: 'Borin',
      );

  Widget wrap({
    required Character character,
    required CharacterSyncService syncService,
  }) {
    return MaterialApp(
      home: CharacterDetailScreen(
        character: character,
        statsRepository: repo(),
        syncService: syncService,
      ),
    );
  }

  testWidgets(
    'Task 013: refresh icon button is PRESENT in the AppBar for an LM-'
    'synced character (larpManagerUuid != null)',
    (tester) async {
      final svc = _FakeCharacterSyncService(
        onRefresh: ({required tenant, required characterUuid}) async =>
            const CharacterSyncResult(ok: true),
      );

      await tester.pumpWidget(wrap(character: lmCharacter(), syncService: svc));
      await tester.pumpAndSettle();

      final appBar = find.byType(AppBar);
      expect(appBar, findsOneWidget);

      final refreshIconInAppBar = find.descendant(
        of: appBar,
        matching: find.byIcon(Icons.refresh),
      );
      expect(
        refreshIconInAppBar,
        findsOneWidget,
        reason: 'refresh icon must appear in the AppBar for LM-synced characters',
      );

      // Also assert it sits BEFORE the existing PopupMenuButton in the
      // actions list (spec: "Add an IconButton ... BEFORE the existing
      // PopupMenuButton").
      final refreshDx =
          tester.getCenter(refreshIconInAppBar).dx;
      final popupDx = tester
          .getCenter(find.descendant(
            of: appBar,
            matching: find.byType(PopupMenuButton<String>),
          ))
          .dx;
      expect(
        refreshDx,
        lessThan(popupDx),
        reason:
            'the refresh action must sit BEFORE (i.e. to the left of) the '
            'existing archive PopupMenuButton in the AppBar actions',
      );
    },
  );

  testWidgets(
    'Task 013: refresh button is ABSENT in the AppBar for a manual '
    'character (larpManagerUuid == null)',
    (tester) async {
      final svc = _FakeCharacterSyncService(
        onRefresh: ({required tenant, required characterUuid}) async =>
            const CharacterSyncResult(ok: true),
      );

      await tester
          .pumpWidget(wrap(character: manualCharacter(), syncService: svc));
      await tester.pumpAndSettle();

      final appBar = find.byType(AppBar);
      expect(appBar, findsOneWidget);
      expect(
        find.descendant(of: appBar, matching: find.byIcon(Icons.refresh)),
        findsNothing,
        reason:
            'manual characters have nothing to refresh from LarpManager — '
            'the button must NOT appear',
      );
      // The existing archive menu must still render even though refresh
      // is gone (regression guard for the existing AppBar contents).
      expect(
        find.descendant(
          of: appBar,
          matching: find.byType(PopupMenuButton<String>),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Task 013: tapping the refresh button shows a loading indicator and the '
    'button becomes non-interactive while the call is in flight (second '
    'concurrent call cannot be issued from the UI)',
    (tester) async {
      final gate = Completer<CharacterSyncResult>();
      final svc = _FakeCharacterSyncService(
        onRefresh: ({required tenant, required characterUuid}) => gate.future,
      );

      await tester.pumpWidget(wrap(character: lmCharacter(), syncService: svc));
      await tester.pumpAndSettle();

      final appBar = find.byType(AppBar);
      final refreshIcon = find.descendant(
        of: appBar,
        matching: find.byIcon(Icons.refresh),
      );
      expect(refreshIcon, findsOneWidget);

      // Tap to start the refresh. The future is gated open so the
      // "in flight" UI state must be visible until we complete it.
      await tester.tap(refreshIcon);
      await tester.pump();

      // Loading indicator is now rendered inside the AppBar.
      final progress = find.descendant(
        of: appBar,
        matching: find.byType(CircularProgressIndicator),
      );
      expect(
        progress,
        findsOneWidget,
        reason:
            'while in flight, the button must swap its icon for a small '
            'CircularProgressIndicator (spec: "disable the button and swap '
            'the icon for a small CircularProgressIndicator of equivalent '
            'size")',
      );
      // Exactly one in-flight call regardless of how many extra taps
      // get sent at the same widget — the wrapper must be disabled.
      // We simulate a "second tap while in flight" by trying to tap
      // again (best-effort: if the refresh icon is gone, this is a
      // findsNothing case which is also acceptable).
      final maybeRefreshIcon = find.descendant(
        of: appBar,
        matching: find.byIcon(Icons.refresh),
      );
      if (maybeRefreshIcon.evaluate().isNotEmpty) {
        await tester.tap(maybeRefreshIcon);
      }
      await tester.pump();
      expect(
        svc.calls.length,
        1,
        reason:
            'the in-flight UI must not allow a second concurrent refresh '
            'call to be issued',
      );

      // Now resolve the gate; the spinner should disappear and the
      // refresh icon should come back.
      gate.complete(const CharacterSyncResult(ok: true));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: appBar,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
        reason: 'spinner must disappear after the call resolves',
      );
      expect(
        find.descendant(of: appBar, matching: find.byIcon(Icons.refresh)),
        findsOneWidget,
        reason: 'refresh icon must return after the call resolves',
      );
    },
  );

  testWidgets(
    'Task 013: on {ok: true} a snackbar reads "Character refreshed"; the '
    'service was called with the active tenant and character uuid',
    (tester) async {
      final svc = _FakeCharacterSyncService(
        onRefresh: ({required tenant, required characterUuid}) async =>
            const CharacterSyncResult(ok: true),
      );

      await tester.pumpWidget(wrap(character: lmCharacter(), syncService: svc));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.refresh),
      ));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(SnackBar, 'Character refreshed'),
        findsOneWidget,
      );

      expect(svc.calls.length, 1);
      expect(svc.calls.single.characterUuid, heldrekUuid);
      expect(svc.calls.single.tenant, kTestGameTenant);
    },
  );

  testWidgets(
    'Task 013: on {ok: false, error: "LM said no"} a snackbar reads '
    '"Could not refresh: LM said no" verbatim',
    (tester) async {
      final svc = _FakeCharacterSyncService(
        onRefresh: ({required tenant, required characterUuid}) async =>
            const CharacterSyncResult(
          ok: false,
          error: 'LM said no',
        ),
      );

      await tester.pumpWidget(wrap(character: lmCharacter(), syncService: svc));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.refresh),
      ));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(SnackBar, 'Could not refresh: LM said no'),
        findsOneWidget,
        reason:
            'the {ok:false, error} branch must surface the server-side '
            'message verbatim, prefixed with "Could not refresh:"',
      );
    },
  );

  testWidgets(
    'Task 013: on a thrown FirebaseFunctionsException, snackbar shows the '
    'reportAppError-mapped userMessage — NOT the raw error.toString(), and '
    'NOT a leaked "INTERNAL" string',
    (tester) async {
      // `code: failed-precondition` with the well-known "LarpManager is
      // not connected" wording maps to a known userMessage via
      // `reportAppError` (see lib/utils/error_reporting.dart). The
      // widget must NOT show "INTERNAL" or the raw exception toString.
      final svc = _FakeCharacterSyncService(
        onRefresh: ({required tenant, required characterUuid}) async => throw
            FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'LarpManager is not connected for this event yet. Ask '
              'your organizer to complete LM Integration in RoleKeeper.',
        ),
      );

      await tester.pumpWidget(wrap(character: lmCharacter(), syncService: svc));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.refresh),
      ));
      await tester.pumpAndSettle();

      // The known-error mapping for that code+message → the configured
      // user message in error_reporting.dart.
      expect(
        find.textContaining('LarpManager is not connected for this event'),
        findsOneWidget,
        reason:
            'snackbar must show the reportAppError userMessage for this '
            'known FirebaseFunctionsException',
      );
      // Strict negative: never leak the raw runtime type or "INTERNAL".
      expect(
        find.textContaining('FirebaseFunctionsException'),
        findsNothing,
        reason:
            'raw exception toString() must NEVER reach the snackbar (per '
            '.cursor/rules/error-handling.mdc)',
      );
      expect(
        find.textContaining('INTERNAL'),
        findsNothing,
      );
    },
  );
}
