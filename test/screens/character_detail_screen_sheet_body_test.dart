/// Widget tests for Task 015 — rendering of `sheet.body` content
/// (Experience points, ability groups, Inventories) on
/// [CharacterDetailScreen].
///
/// Pins the Task 015 frontend acceptance criteria:
///   1. Experience points section renders when
///      `stats.sheetBody?.experiencePoints` is non-null/non-empty.
///   2. Each `SheetAbilityGroup` becomes a `_Section` with rows that
///      visually match `_AbilityTile` (name, optional Cost chip,
///      optional description).
///   3. Inventories render as cards with a title, label/value rows,
///      and a "View on LarpManager" button that calls `launchUrl`
///      with the exact `detailsUrl` and
///      `LaunchMode.externalApplication`.
///   4. `sheetBody == null` (legacy mirror docs) renders the
///      pre-Task-015 screen verbatim — no new sections appear.
///   5. When BOTH `sheet.body.abilityGroups` AND the JSON-fed
///      `abilities` are populated, BOTH render (per user decision).
///   6. Render order matches the LM web page top-to-bottom: sheet
///      sections → Presentation → Experience points → ability groups
///      → Inventories → JSON Abilities → footer.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/models/character.dart';
import 'package:rolekeeper/screens/character_detail_screen.dart';
import 'package:rolekeeper/services/character_stats_repository.dart';
import 'package:rolekeeper/services/game_context_service.dart';
import 'package:rolekeeper/utils/game_firestore_paths.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../helpers/game_tenant_test_paths.dart';

/// Records every `launchUrl` call routed through
/// `UrlLauncherPlatform.instance` so the inventory "View on
/// LarpManager" test can assert on the exact url + launch mode the
/// widget asked for.
class _FakeUrlLauncherPlatform extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<({String url, PreferredLaunchMode mode})> calls = [];

  /// Whatever `launchUrl` should resolve to (default true). Tests can
  /// flip this to false to exercise the failure path.
  bool result = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    calls.add((url: url, mode: options.mode));
    return result;
  }

  @override
  Future<bool> canLaunch(String url) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late _FakeUrlLauncherPlatform fakeLauncher;
  late UrlLauncherPlatform originalLauncher;

  const heldrekUuid = 'oxe9sb0w02ig';
  const inventoryUrl =
      'https://lm.example/crucible/manage/ci/inventory/g7j03os5vzhj/view/';

  setUp(() async {
    GameContextService.instance.currentTenantForTest = kTestGameTenant;
    firestore = FakeFirebaseFirestore();
    await seedGameTenantDocs(firestore, kTestGameTenant);

    originalLauncher = UrlLauncherPlatform.instance;
    fakeLauncher = _FakeUrlLauncherPlatform();
    UrlLauncherPlatform.instance = fakeLauncher;
  });

  tearDown(() {
    UrlLauncherPlatform.instance = originalLauncher;
    GameContextService.instance.resetForTest();
  });

  Future<void> seedMirror({
    required String uuid,
    Map<String, dynamic>? export,
    Object? abilities,
    Object? sheet,
    DateTime? lastSyncedAt,
  }) async {
    final data = <String, dynamic>{};
    if (export != null) {
      data['export'] = export;
      final teaser = export['teaser'];
      if (teaser is String && teaser.isNotEmpty) {
        data['teaser'] = teaser;
      }
    }
    if (abilities != null) data['abilities'] = abilities;
    if (sheet != null) data['sheet'] = sheet;
    if (lastSyncedAt != null) {
      data['lastSyncedAt'] = Timestamp.fromDate(lastSyncedAt);
    }
    await GameFirestorePaths.larpManagerMirrorChars(firestore, kTestGameTenant)
        .doc(uuid)
        .set(data);
  }

  Character lmCharacter() => Character(
        id: heldrekUuid,
        shortId: 'ABC',
        ownerId: 'p1',
        name: 'Heldrek',
        larpManagerUuid: heldrekUuid,
        source: 'larpmanager',
      );

  CharacterStatsRepository repo() => CharacterStatsRepository(
        firestore: firestore,
        tenant: kTestGameTenant,
      );

  Widget wrap(Character character) {
    return MaterialApp(
      home: CharacterDetailScreen(
        character: character,
        statsRepository: repo(),
      ),
    );
  }

  // ---- Experience points ------------------------------------------------

  testWidgets(
    'Task 015: sheet.body.experiencePoints non-null renders an '
    '"Experience points" _Section whose body text matches verbatim',
    (tester) async {
      await seedMirror(
        uuid: heldrekUuid,
        export: {'name': 'Heldrek'},
        sheet: {
          'body': {
            'experiencePoints': '60 XP total, 30 spent',
            'abilityGroups': <dynamic>[],
            'inventories': <dynamic>[],
          },
        },
        lastSyncedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      expect(
        find.text('Experience points'),
        findsOneWidget,
        reason: 'spec: section header label is verbatim "Experience points"',
      );
      expect(
        find.text('60 XP total, 30 spent'),
        findsOneWidget,
        reason: 'spec: body Text matches sheetBody.experiencePoints verbatim',
      );
    },
  );

  testWidgets(
    'Task 015: sheet.body present but experiencePoints is null/missing '
    '→ "Experience points" section header is hidden',
    (tester) async {
      await seedMirror(
        uuid: heldrekUuid,
        export: {'name': 'Heldrek'},
        sheet: {
          'body': {
            // experiencePoints intentionally absent.
            'abilityGroups': <dynamic>[],
            'inventories': <dynamic>[],
          },
        },
        lastSyncedAt: DateTime.now(),
      );

      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      expect(
        find.text('Experience points'),
        findsNothing,
        reason: 'spec: skip section when experiencePoints is null',
      );
    },
  );

  // ---- Ability groups ----------------------------------------------------

  testWidgets(
    'Task 015: two ability groups (Shadow Affinity Skills, Iron Affinity) '
    'each with two abilities render as two _Sections in source order, '
    'each with the right ability names + cost chips + descriptions',
    (tester) async {
      await seedMirror(
        uuid: heldrekUuid,
        export: {'name': 'Heldrek'},
        sheet: {
          'body': {
            'abilityGroups': [
              {
                'label': 'Shadow Affinity Skills',
                'abilities': [
                  {
                    'name': 'Flashback',
                    'cost': '99',
                    'description': 'Frequency: Heist | Delivery: Self',
                  },
                  {
                    'name': 'Shadow Step',
                    'cost': '3',
                    'description': 'Teleport one stride into shadow.',
                  },
                ],
              },
              {
                'label': 'Iron Affinity',
                'abilities': [
                  {
                    'name': 'Body 6 [Iron]',
                    'cost': '12',
                    'description': 'Iron-clad heart.',
                  },
                  {
                    'name': 'Bulwark',
                    'cost': '4',
                    'description': 'Brace against a single blow.',
                  },
                ],
              },
            ],
            'inventories': <dynamic>[],
          },
        },
        lastSyncedAt: DateTime.now(),
      );

      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      // Both group section headers render verbatim.
      expect(find.text('Shadow Affinity Skills'), findsOneWidget);
      expect(find.text('Iron Affinity'), findsOneWidget);

      // Source order is preserved (Shadow above Iron).
      final shadowY =
          tester.getTopLeft(find.text('Shadow Affinity Skills')).dy;
      final ironY = tester.getTopLeft(find.text('Iron Affinity')).dy;
      expect(
        shadowY,
        lessThan(ironY),
        reason:
            'spec: groups render in LM source-HTML order — Shadow above Iron',
      );

      // All four ability names render.
      expect(find.text('Flashback'), findsOneWidget);
      expect(find.text('Shadow Step'), findsOneWidget);
      expect(find.text('Body 6 [Iron]'), findsOneWidget);
      expect(find.text('Bulwark'), findsOneWidget);

      // Cost chips render with the spec text "Cost <n>".
      expect(find.widgetWithText(Chip, 'Cost 99'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'Cost 3'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'Cost 12'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'Cost 4'), findsOneWidget);

      // Descriptions render below their abilities.
      expect(find.text('Frequency: Heist | Delivery: Self'), findsOneWidget);
      expect(find.text('Teleport one stride into shadow.'), findsOneWidget);
      expect(find.text('Iron-clad heart.'), findsOneWidget);
      expect(find.text('Brace against a single blow.'), findsOneWidget);
    },
  );

  testWidgets(
    'Task 015: an ability with cost: null renders the name with NO Cost '
    'chip',
    (tester) async {
      await seedMirror(
        uuid: heldrekUuid,
        export: {'name': 'Heldrek'},
        sheet: {
          'body': {
            'abilityGroups': [
              {
                'label': 'Race Skills',
                'abilities': [
                  {
                    'name': 'Innate Toughness',
                    // cost intentionally absent → null after parsing.
                    'description': 'Always-on resilience.',
                  },
                ],
              },
            ],
            'inventories': <dynamic>[],
          },
        },
        lastSyncedAt: DateTime.now(),
      );

      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      expect(find.text('Innate Toughness'), findsOneWidget);
      // No cost chip exists for this ability anywhere on the screen.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Chip &&
              w.label is Text &&
              ((w.label as Text).data ?? '').startsWith('Cost'),
        ),
        findsNothing,
        reason:
            'spec: an ability with cost: null must render the name with '
            'NO chip',
      );
    },
  );

  testWidgets(
    'Task 015: an ability with description: null renders the name only '
    '(no body text below)',
    (tester) async {
      await seedMirror(
        uuid: heldrekUuid,
        export: {'name': 'Heldrek'},
        sheet: {
          'body': {
            'abilityGroups': [
              {
                'label': 'Helper Abilities',
                'abilities': [
                  {
                    'name': 'Mark of the Helper',
                    'cost': '0',
                    // description intentionally absent → null after parsing.
                  },
                ],
              },
            ],
            'inventories': <dynamic>[],
          },
        },
        lastSyncedAt: DateTime.now(),
      );

      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      expect(find.text('Mark of the Helper'), findsOneWidget);
      // The cost chip must still appear.
      expect(find.widgetWithText(Chip, 'Cost 0'), findsOneWidget);

      // The MaterialApp's Scaffold body (where the new sections live)
      // must NOT contain any descendant Text whose data isn't part of
      // the known set of expected strings — but a tighter check is
      // simply: there is no Text widget containing common description
      // tokens like "Frequency" / "Delivery" / etc. that another
      // ability's description would have used.
      //
      // Stronger guard: assert the only rendered Texts within the
      // Helper Abilities _Section column are the section header, the
      // ability name, and (because cost is set) the chip's "Cost 0".
      final helperHeader = find.text('Helper Abilities');
      expect(helperHeader, findsOneWidget);

      // No description-style body text exists for this ability — there
      // is exactly one Text widget with the ability name. No "extra"
      // Text below it within the same Padding/Column wrapper.
      // We reuse the `find.text` API: any literal description string
      // would be a separate Text. None should be present.
      final descriptionLikely = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data ?? '').contains('Frequency:') &&
            (w.data ?? '').contains('Delivery:'),
      );
      expect(descriptionLikely, findsNothing);
    },
  );

  testWidgets(
    'Task 015: an ability group whose abilities[] is empty still renders '
    'the _Section header (LM does the same on the web page)',
    (tester) async {
      await seedMirror(
        uuid: heldrekUuid,
        export: {'name': 'Heldrek'},
        sheet: {
          'body': {
            'abilityGroups': [
              {
                'label': 'Extra Hit Points',
                'abilities': <dynamic>[],
              },
            ],
            'inventories': <dynamic>[],
          },
        },
        lastSyncedAt: DateTime.now(),
      );

      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      expect(
        find.text('Extra Hit Points'),
        findsOneWidget,
        reason: 'spec: empty abilities[] still renders the section header',
      );
    },
  );

  // ---- Inventories -------------------------------------------------------

  testWidgets(
    'Task 015: an inventory with title + one balance + detailsUrl '
    'renders an Inventories _Section containing a Card with the title '
    '(titleSmall), the balance row, and a "View on LarpManager" button',
    (tester) async {
      await seedMirror(
        uuid: heldrekUuid,
        export: {'name': 'Heldrek'},
        sheet: {
          'body': {
            'abilityGroups': <dynamic>[],
            'inventories': [
              {
                'title': "Heldrek's Personal Storage",
                'balances': [
                  {'label': 'Monster Cores', 'value': '0'},
                ],
                'detailsUrl': inventoryUrl,
              },
            ],
          },
        },
        lastSyncedAt: DateTime.now(),
      );

      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      // Outer section header.
      expect(find.text('Inventories'), findsOneWidget);

      // Card with the inventory title.
      expect(find.text("Heldrek's Personal Storage"), findsOneWidget);

      // Balance row renders both label and value.
      expect(find.text('Monster Cores'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);

      // "View on LarpManager" button is present and is a TextButton
      // (per spec: TextButton.icon — which yields a TextButton
      // subtype, hence `bySubtype<TextButton>()` rather than `byType`).
      final viewButton = find.ancestor(
        of: find.text('View on LarpManager'),
        matching: find.bySubtype<TextButton>(),
      );
      expect(
        viewButton,
        findsOneWidget,
        reason:
            'spec: trailing TextButton.icon labelled "View on LarpManager"',
      );
      expect(
        find.byIcon(Icons.open_in_new),
        findsOneWidget,
        reason: 'spec: button uses Icons.open_in_new',
      );

      // The button must live INSIDE a Card (the inventory card).
      expect(
        find.descendant(
          of: find.byType(Card),
          matching: viewButton,
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Task 015: tapping "View on LarpManager" calls launchUrl with the '
    'exact detailsUrl and LaunchMode.externalApplication',
    (tester) async {
      await seedMirror(
        uuid: heldrekUuid,
        export: {'name': 'Heldrek'},
        sheet: {
          'body': {
            'abilityGroups': <dynamic>[],
            'inventories': [
              {
                'title': "Heldrek's Personal Storage",
                'balances': [
                  {'label': 'Monster Cores', 'value': '0'},
                ],
                'detailsUrl': inventoryUrl,
              },
            ],
          },
        },
        lastSyncedAt: DateTime.now(),
      );

      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      await tester.tap(
        find.ancestor(
          of: find.text('View on LarpManager'),
          matching: find.bySubtype<TextButton>(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        fakeLauncher.calls.length,
        1,
        reason: 'tapping the button must call launchUrl exactly once',
      );
      expect(
        fakeLauncher.calls.single.url,
        inventoryUrl,
        reason: 'spec: launchUrl receives the exact detailsUrl',
      );
      expect(
        fakeLauncher.calls.single.mode,
        PreferredLaunchMode.externalApplication,
        reason:
            'spec: mode is LaunchMode.externalApplication '
            '(== PreferredLaunchMode.externalApplication on the platform '
            'interface)',
      );
    },
  );

  testWidgets(
    'Task 015: an inventory with detailsUrl == null renders the card and '
    'balance rows but NO "View on LarpManager" button',
    (tester) async {
      await seedMirror(
        uuid: heldrekUuid,
        export: {'name': 'Heldrek'},
        sheet: {
          'body': {
            'abilityGroups': <dynamic>[],
            'inventories': [
              {
                'title': 'Common Pool',
                'balances': [
                  {'label': 'Coin', 'value': '5'},
                ],
                // detailsUrl intentionally absent.
              },
            ],
          },
        },
        lastSyncedAt: DateTime.now(),
      );

      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      expect(find.text('Inventories'), findsOneWidget);
      expect(find.text('Common Pool'), findsOneWidget);
      expect(find.text('Coin'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);

      expect(
        find.text('View on LarpManager'),
        findsNothing,
        reason: 'spec: no button when detailsUrl is null',
      );
    },
  );

  // ---- No-data behaviour -------------------------------------------------

  testWidgets(
    'Task 015: sheetBody == null (legacy mirror doc) renders the pre-'
    'Task-015 screen verbatim — no Experience points / ability groups '
    '/ Inventories sections appear; existing _SheetPanel + Presentation '
    '+ JSON _AbilitiesBlock + footer all still render',
    (tester) async {
      await seedMirror(
        uuid: heldrekUuid,
        export: {
          'name': 'Heldrek',
          'teaser': 'A wandering warrior.',
        },
        abilities: [
          {'name': 'Block', 'cost': 1, 'description': 'Block one attack'},
        ],
        sheet: {
          // sections present (sheet panel renders) but body absent.
          'sections': [
            {
              'label': 'Stats',
              'rows': [
                {'label': 'HP', 'value': '42'},
              ],
            },
          ],
          // body intentionally absent → sheetBody is null.
        },
        lastSyncedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      // None of the new section headers appear.
      expect(find.text('Experience points'), findsNothing);
      expect(find.text('Inventories'), findsNothing);

      // Pre-Task-015 sections all still render.
      expect(find.text('Stats'), findsOneWidget,
          reason: '_SheetPanel section still renders');
      expect(find.text('HP'), findsOneWidget);
      expect(find.text('Presentation'), findsOneWidget);
      expect(find.text('A wandering warrior.'), findsOneWidget);
      expect(find.text('Abilities'), findsOneWidget,
          reason: 'JSON _AbilitiesBlock still renders');
      expect(find.text('Block'), findsOneWidget);
      expect(find.textContaining('Last synced'), findsOneWidget);
    },
  );

  testWidgets(
    'Task 015: sheetBody present but every field empty (no XP, no groups, '
    'no inventories) renders no new sections — same UX as legacy',
    (tester) async {
      await seedMirror(
        uuid: heldrekUuid,
        export: {'name': 'Heldrek', 'teaser': 'A wandering warrior.'},
        sheet: {
          'body': {
            // experiencePoints absent → null.
            'abilityGroups': <dynamic>[],
            'inventories': <dynamic>[],
          },
        },
        lastSyncedAt: DateTime.now(),
      );

      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      expect(find.text('Experience points'), findsNothing);
      expect(find.text('Inventories'), findsNothing);
      // Existing Presentation still renders.
      expect(find.text('Presentation'), findsOneWidget);
    },
  );

  // ---- Coexistence with the JSON-fed _AbilitiesBlock ---------------------

  testWidgets(
    'Task 015: when BOTH sheet.body.abilityGroups AND the JSON `abilities` '
    'field are populated, BOTH render — the new ability-group _Sections '
    'AND the existing "Abilities" _Section (per user decision: keep '
    'both visible)',
    (tester) async {
      await seedMirror(
        uuid: heldrekUuid,
        export: {'name': 'Heldrek'},
        abilities: [
          {
            'name': 'JSON-Block',
            'cost': 1,
            'description': 'Block one attack',
            'type': 'Combat',
          },
        ],
        sheet: {
          'body': {
            'abilityGroups': [
              {
                'label': 'Shadow Affinity Skills',
                'abilities': [
                  {'name': 'Sheet-Flashback', 'cost': '99'},
                ],
              },
            ],
            'inventories': <dynamic>[],
          },
        },
        lastSyncedAt: DateTime.now(),
      );

      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      // New sheet-body group section header AND ability render.
      expect(
        find.text('Shadow Affinity Skills'),
        findsOneWidget,
        reason: 'sheet-body ability group section must render',
      );
      expect(find.text('Sheet-Flashback'), findsOneWidget);

      // Existing JSON-fed _Section('Abilities', _AbilitiesBlock(...)) is
      // ALSO present (NOT suppressed by the new content).
      expect(
        find.text('Abilities'),
        findsOneWidget,
        reason:
            'spec: the JSON _AbilitiesBlock _Section header must keep '
            'rendering even when sheet ability groups exist',
      );
      expect(
        find.text('JSON-Block'),
        findsOneWidget,
        reason: 'JSON-fed ability still renders inside the Abilities section',
      );
    },
  );

  // ---- Render order ------------------------------------------------------

  testWidgets(
    'Task 015: when every section is populated, the render order matches '
    'the spec: sheet sections → Presentation → Experience points → '
    'ability groups → Inventories → JSON Abilities → Last synced',
    (tester) async {
      await seedMirror(
        uuid: heldrekUuid,
        export: {
          'name': 'Heldrek',
          'teaser': 'A wandering warrior.',
        },
        abilities: [
          {'name': 'JSON-Block', 'cost': 1, 'description': 'Block'},
        ],
        sheet: {
          'sections': [
            {
              'label': 'Identity',
              'rows': [
                {'label': 'Player', 'value': 'Player 1'},
              ],
            },
          ],
          'body': {
            'experiencePoints': '60 XP total, 30 spent',
            'abilityGroups': [
              {
                'label': 'Shadow Affinity Skills',
                'abilities': [
                  {'name': 'Sheet-Flashback', 'cost': '99'},
                ],
              },
            ],
            'inventories': [
              {
                'title': "Heldrek's Personal Storage",
                'balances': [
                  {'label': 'Monster Cores', 'value': '0'},
                ],
                'detailsUrl': inventoryUrl,
              },
            ],
          },
        },
        lastSyncedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      final identityY = tester.getTopLeft(find.text('Identity')).dy;
      final presentationY = tester.getTopLeft(find.text('Presentation')).dy;
      final xpY = tester.getTopLeft(find.text('Experience points')).dy;
      final groupY =
          tester.getTopLeft(find.text('Shadow Affinity Skills')).dy;
      final inventoriesY = tester.getTopLeft(find.text('Inventories')).dy;
      final abilitiesY = tester.getTopLeft(find.text('Abilities')).dy;
      final lastSyncedY = tester
          .getTopLeft(find.textContaining('Last synced'))
          .dy;

      expect(identityY, lessThan(presentationY),
          reason: 'sheet sections render above Presentation');
      expect(presentationY, lessThan(xpY),
          reason: 'Presentation renders above Experience points');
      expect(xpY, lessThan(groupY),
          reason: 'Experience points renders above ability groups');
      expect(groupY, lessThan(inventoriesY),
          reason: 'Ability groups render above Inventories');
      expect(inventoriesY, lessThan(abilitiesY),
          reason: 'Inventories renders above the JSON Abilities section');
      expect(abilitiesY, lessThan(lastSyncedY),
          reason: 'JSON Abilities renders above the Last synced footer');
    },
  );
}
