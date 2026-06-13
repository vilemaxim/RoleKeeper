import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/screens/larp_manager_integration_screen.dart';
import 'package:rolekeeper/services/game_context_service.dart';
import 'package:rolekeeper/services/larp_manager_integration_repository.dart';
import 'package:rolekeeper/utils/game_firestore_paths.dart';

import '../helpers/game_tenant_test_paths.dart';

/// Widget test for [LarpManagerIntegrationScreen] — pins Task 012
/// (`docs/adr/0001-remove-fetchdetails-toggle.md`).
///
/// The integration screen previously rendered a `SwitchListTile` titled
/// "Fetch inventory & abilities JSON" inside its Advanced options
/// expander, gated by `_fetchDetails` state. Task 012 removes the
/// toggle entirely — admin sync is always full. This test pins that
/// the SwitchListTile is no longer present anywhere in the rendered
/// tree, even after expanding the Advanced options.
///
/// To drive the screen without booting Firebase, the screen accepts an
/// injected [LarpManagerIntegrationRepository]. We seed a fake
/// Firestore with a fully-populated integration config so `_load()`
/// completes without falling back to [LarpManagerRegistrationService]
/// (which would try to hit the real Firestore otherwise).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GameContextService.instance.currentTenantForTest = kTestGameTenant;
  });

  tearDown(GameContextService.instance.resetForTest);

  /// Set a tall test viewport so every child of the screen's vertical
  /// ListView is laid out and reachable by [Finder]s without needing
  /// to scroll. The Advanced options ExpansionTile lives below the
  /// LarpManager setup card and would otherwise be off-screen in the
  /// default 800x600 test surface.
  Future<void> useTallViewport(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  /// Seed a valid `larpManagerIntegration/config` doc into [firestore]
  /// at [kTestGameTenant]'s path. [extra] is merged in to inject
  /// legacy/test-specific fields (e.g. a stale `fetchDetails: true`).
  Future<LarpManagerIntegrationRepository> seedIntegrationConfig(
    FakeFirebaseFirestore firestore, {
    Map<String, dynamic> extra = const {},
  }) async {
    await seedGameTenantDocs(firestore, kTestGameTenant);
    await GameFirestorePaths.larpManagerIntegrationConfig(
      firestore,
      kTestGameTenant,
    ).set({
      'baseUrl': 'https://lm.example.com',
      'eventSlug': 'crucible',
      'loginPath': '/login/',
      'credentialsConfigured': true,
      ...extra,
    });
    return LarpManagerIntegrationRepository(
      firestore: firestore,
      tenant: kTestGameTenant,
    );
  }

  /// Pump the screen with the given [repository] and let `_load()` settle.
  Future<void> pumpIntegrationScreen(
    WidgetTester tester,
    LarpManagerIntegrationRepository repository,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LarpManagerIntegrationScreen(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Task 012: no "Fetch inventory & abilities JSON" SwitchListTile is '
    'rendered, even after expanding Advanced options',
    (tester) async {
      await useTallViewport(tester);
      // Note: NO `fetchDetails` key written. Task 012's saved-payload
      // shape no longer carries the field; this seed represents a
      // freshly-saved post-Task-012 config doc.
      final repo = await seedIntegrationConfig(FakeFirebaseFirestore());
      await pumpIntegrationScreen(tester, repo);

      // Advanced options is an ExpansionTile; expand it so any child
      // SwitchListTile would be in the rendered tree.
      final advancedTile = find.text('Advanced options');
      expect(
        advancedTile,
        findsOneWidget,
        reason: 'Advanced options expander must still render after Task 012',
      );
      await tester.tap(advancedTile);
      await tester.pumpAndSettle();

      expect(
        find.text('Fetch inventory & abilities JSON'),
        findsNothing,
        reason:
            'Task 012 removes the fetchDetails toggle — the SwitchListTile '
            'titled "Fetch inventory & abilities JSON" must no longer be '
            'rendered anywhere in the integration screen.',
      );
      // Defensive: the underlying widget type must also not appear.
      // (Future tweaks might rename the label; the widget removal is
      // the requirement.)
      expect(
        find.byType(SwitchListTile),
        findsNothing,
        reason:
            'After Task 012 the integration screen has no SwitchListTile at '
            'all — the only toggle on the screen was the fetchDetails one.',
      );
    },
  );

  testWidgets(
    'Task 012: loader tolerates a legacy fetchDetails:true value in the '
    'stored Firestore doc — screen still renders without crashing',
    (tester) async {
      await useTallViewport(tester);
      // Legacy `fetchDetails: true` tolerated per ADR 0001 — should
      // NOT crash the loader or summon the removed SwitchListTile
      // back into being.
      final repo = await seedIntegrationConfig(
        FakeFirebaseFirestore(),
        extra: {'fetchDetails': true},
      );
      await pumpIntegrationScreen(tester, repo);

      // No load errors surface as a snackbar/banner — the feedback
      // banner widget is gated by `_feedbackMessage != null` and only
      // appears on errors; we assert the error copy is absent.
      expect(
        find.textContaining('Could not load settings'),
        findsNothing,
        reason:
            'A legacy fetchDetails field in storage must not produce a load '
            'error.',
      );

      // Tap Advanced — still no SwitchListTile.
      await tester.tap(find.text('Advanced options'));
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNothing);
    },
  );
}
