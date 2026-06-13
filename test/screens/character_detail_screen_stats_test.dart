import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/models/character.dart';
import 'package:rolekeeper/screens/character_detail_screen.dart';
import 'package:rolekeeper/services/character_stats_repository.dart';
import 'package:rolekeeper/services/game_context_service.dart';
import 'package:rolekeeper/utils/game_firestore_paths.dart';
import 'package:rolekeeper/utils/relative_time.dart';

import '../helpers/game_tenant_test_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;

  const heldrekUuid = 'oxe9sb0w02ig';

  setUp(() async {
    GameContextService.instance.currentTenantForTest = kTestGameTenant;
    firestore = FakeFirebaseFirestore();
    await seedGameTenantDocs(firestore, kTestGameTenant);
  });

  tearDown(GameContextService.instance.resetForTest);

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
      // Task 011: runLarpManagerSync writes the plain-text teaser at
      // the TOP LEVEL of the mirror doc (raw HTML stays inside
      // export.teaser). Mirror that here so test seeds match what
      // the sync function actually writes. Tests that want to
      // exercise the legacy "no top-level teaser" path simply omit
      // `teaser` from `export`.
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

  Character lmCharacter({
    String name = 'Heldrek',
    String uuid = heldrekUuid,
  }) {
    return Character(
      id: uuid,
      shortId: 'ABC',
      ownerId: 'p1',
      name: name,
      larpManagerUuid: uuid,
      source: 'larpmanager',
    );
  }

  Character manualCharacter() {
    return const Character(
      id: 'manual-1',
      shortId: 'DEF',
      ownerId: 'p1',
      name: 'Borin',
    );
  }

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

  testWidgets(
    'LM-synced character with teaser, custom keys, and abilities renders all '
    'three sections in Presentation → Custom Fields → Abilities order',
    (tester) async {
      await seedMirror(
        uuid: heldrekUuid,
        export: {
          'number': 42,
          'name': 'Heldrek',
          'uuid': heldrekUuid,
          'teaser': 'A wandering warrior.',
          'combat_style': 'Sword and shield',
          'background': 'Northern barbarian',
        },
        abilities: [
          {
            'name': 'Block',
            'cost': 1,
            'description': 'Block one attack',
            'type': 'Combat',
          },
          {
            'name': 'Mend',
            'description': 'Heal 1 hp',
          },
        ],
        lastSyncedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      expect(find.text('Presentation'), findsOneWidget);
      expect(find.text('Custom Fields'), findsOneWidget);
      expect(find.text('Abilities'), findsOneWidget);

      final presentationY = tester.getTopLeft(find.text('Presentation')).dy;
      final customY = tester.getTopLeft(find.text('Custom Fields')).dy;
      final abilitiesY = tester.getTopLeft(find.text('Abilities')).dy;
      expect(presentationY, lessThan(customY),
          reason: 'Presentation appears above Custom Fields');
      expect(customY, lessThan(abilitiesY),
          reason: 'Custom Fields appears above Abilities');

      expect(find.text('A wandering warrior.'), findsOneWidget);
      expect(find.text('Block'), findsOneWidget);
      expect(find.text('Mend'), findsOneWidget);
    },
  );

  testWidgets(
    'LM-synced character with only name/number/uuid in export hides all 3 '
    'section headers; "Last synced" footer still renders',
    (tester) async {
      final lastSync = DateTime.now().subtract(const Duration(minutes: 5));
      await seedMirror(
        uuid: heldrekUuid,
        export: {
          'number': 42,
          'name': 'Heldrek',
          'uuid': heldrekUuid,
        },
        lastSyncedAt: lastSync,
      );

      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      expect(find.text('Presentation'), findsNothing);
      expect(find.text('Custom Fields'), findsNothing);
      expect(find.text('Abilities'), findsNothing);

      expect(
        find.textContaining('Last synced'),
        findsOneWidget,
        reason: 'footer should always render when a mirror doc is present',
      );
    },
  );

  testWidgets(
    'abilities null or [] hides Abilities section; Presentation/Custom '
    'Fields still render when present',
    (tester) async {
      await seedMirror(
        uuid: heldrekUuid,
        export: {
          'name': 'Heldrek',
          'teaser': 'A wandering warrior.',
          'background': 'Northern barbarian',
        },
        abilities: <dynamic>[],
        lastSyncedAt: DateTime.now(),
      );

      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      expect(find.text('Abilities'), findsNothing);
      expect(find.text('Presentation'), findsOneWidget);
      expect(find.text('Custom Fields'), findsOneWidget);
    },
  );

  testWidgets(
    'manual character renders existing placeholder; no mirror read; no '
    '"Last synced" footer',
    (tester) async {
      await tester.pumpWidget(wrap(manualCharacter()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Add attributes'),
        findsOneWidget,
        reason: 'existing placeholder must still render for manual characters',
      );
      expect(find.textContaining('Last synced'), findsNothing);
      expect(find.textContaining('Synced: pending'), findsNothing);
      expect(find.textContaining('Stats not synced yet'), findsNothing);
    },
  );

  testWidgets(
    'mirror doc absent for an LM-synced character shows "Stats not synced '
    'yet…" message; identity block and archive menu still work',
    (tester) async {
      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Stats not synced yet'),
        findsOneWidget,
      );

      // Identity block (short ID chip) still renders.
      expect(find.textContaining('ID: ABC'), findsOneWidget);

      // Archive menu still present.
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    },
  );

  testWidgets(
    '"Last synced" footer text matches relativeTime(lastSyncedAt) output for '
    'a 5-minutes-ago timestamp (no hard-coded string)',
    (tester) async {
      final lastSync = DateTime.now().subtract(const Duration(minutes: 5));
      await seedMirror(
        uuid: heldrekUuid,
        export: {'name': 'Heldrek'},
        lastSyncedAt: lastSync,
      );

      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      final expectedFragment = relativeTime(lastSync);
      expect(
        find.textContaining(expectedFragment),
        findsOneWidget,
        reason: 'footer should embed relativeTime(lastSyncedAt) output',
      );
    },
  );

  // --- Task 010: scraped sheet panel ------------------------------------
  //
  // The 4 tests below pin Task 010's acceptance criteria. They drive the
  // new top-of-screen panel that renders `larpManagerMirrorChars/{uuid}
  // .sheet.sections` (written by Task 009 from Task 008's parser) ABOVE
  // the existing Presentation section, with sections and rows in LM
  // source-HTML order and labels verbatim. When sheet is present the
  // existing Custom Fields section is suppressed (the scraped sheet is
  // canonical and rendering both would double up every row).

  testWidgets(
    'Task 010: sheet with sections [Identity, Stats, Affinities] renders '
    'all three section headers ABOVE the Presentation section, in the '
    'captured order, with row labels and values verbatim',
    (tester) async {
      await seedMirror(
        uuid: heldrekUuid,
        export: {
          'number': 42,
          'name': 'Heldrek',
          'uuid': heldrekUuid,
          'teaser': 'A wandering warrior.',
        },
        sheet: {
          'sections': [
            {
              'label': 'Identity',
              'rows': [
                {'label': 'Player', 'value': 'Player 1'},
                {'label': 'Status', 'value': 'Proposed'},
              ],
            },
            {
              'label': 'Stats',
              'rows': [
                {'label': 'Hit Points/Essence', 'value': '42'},
                {'label': 'Iron DR', 'value': '2'},
              ],
            },
            {
              'label': 'Affinities',
              'rows': [
                {'label': 'Total Fire Affinity', 'value': '12'},
                {'label': 'Effective Body Affinity', 'value': '6'},
              ],
            },
          ],
        },
        lastSyncedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      expect(find.text('Identity'), findsOneWidget);
      expect(find.text('Stats'), findsOneWidget);
      expect(find.text('Affinities'), findsOneWidget);
      expect(find.text('Presentation'), findsOneWidget);

      final identityY = tester.getTopLeft(find.text('Identity')).dy;
      final statsY = tester.getTopLeft(find.text('Stats')).dy;
      final affinitiesY = tester.getTopLeft(find.text('Affinities')).dy;
      final presentationY = tester.getTopLeft(find.text('Presentation')).dy;

      expect(identityY, lessThan(statsY),
          reason: 'Identity must render above Stats (captured order)');
      expect(statsY, lessThan(affinitiesY),
          reason: 'Stats must render above Affinities (captured order)');
      expect(affinitiesY, lessThan(presentationY),
          reason: 'all sheet sections must render ABOVE Presentation');

      // Row labels (verbatim — no humanization, no re-casing).
      expect(find.text('Player'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Hit Points/Essence'), findsOneWidget,
          reason: 'verbatim label — no rewording to "Hit Points / Essence"');
      expect(find.text('Iron DR'), findsOneWidget);
      expect(find.text('Total Fire Affinity'), findsOneWidget);
      expect(find.text('Effective Body Affinity'), findsOneWidget);

      // Row values render too.
      expect(find.text('Player 1'), findsOneWidget);
      expect(find.text('Proposed'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
    },
  );

  testWidgets(
    'Task 010: with sheet present, Custom Fields section is HIDDEN even '
    'when export carries custom keys; Presentation / Abilities / Last-'
    'synced still render',
    (tester) async {
      await seedMirror(
        uuid: heldrekUuid,
        export: {
          'name': 'Heldrek',
          'teaser': 'A wandering warrior.',
          // These would normally surface as Custom Fields rows.
          'combat_style': 'Sword and shield',
          'background': 'Northern barbarian',
        },
        abilities: [
          {'name': 'Block', 'cost': 1, 'description': 'Block one attack'},
        ],
        sheet: {
          'sections': [
            {
              'label': 'Stats',
              'rows': [
                {'label': 'Player', 'value': 'Player 1'},
              ],
            },
          ],
        },
        lastSyncedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      expect(find.text('Stats'), findsOneWidget,
          reason: 'sheet panel renders');
      expect(
        find.text('Custom Fields'),
        findsNothing,
        reason:
            'sheet is canonical when present; Custom Fields must be hidden '
            'to avoid double-rendering the same rows',
      );
      // The custom-field VALUES must not appear either (they would also
      // be in the Custom Fields rows the panel is replacing).
      expect(find.text('Sword and shield'), findsNothing);
      expect(find.text('Northern barbarian'), findsNothing);

      // Presentation, Abilities, Last-synced still render.
      expect(find.text('Presentation'), findsOneWidget);
      expect(find.text('A wandering warrior.'), findsOneWidget);
      expect(find.text('Abilities'), findsOneWidget);
      expect(find.text('Block'), findsOneWidget);
      expect(find.textContaining('Last synced'), findsOneWidget);
    },
  );

  testWidgets(
    'Task 010 regression guard: with sheet ABSENT (no sheet key on the '
    'mirror doc), the existing Presentation / Custom Fields / Abilities '
    '/ Last-synced order from Task 007 still renders unchanged',
    (tester) async {
      await seedMirror(
        uuid: heldrekUuid,
        export: {
          'name': 'Heldrek',
          'teaser': 'A wandering warrior.',
          'combat_style': 'Sword and shield',
          'background': 'Northern barbarian',
        },
        abilities: [
          {'name': 'Block', 'cost': 1, 'description': 'Block one attack'},
        ],
        // sheet intentionally omitted.
        lastSyncedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      // Custom Fields IS shown (sheet is the suppressor and sheet is
      // absent — this is the pre-Task-009 fallback path).
      expect(find.text('Presentation'), findsOneWidget);
      expect(find.text('Custom Fields'), findsOneWidget);
      expect(find.text('Abilities'), findsOneWidget);
      expect(find.text('Sword and shield'), findsOneWidget);
      expect(find.text('Northern barbarian'), findsOneWidget);
      expect(find.textContaining('Last synced'), findsOneWidget);

      // Verify ordering matches Task 007: Presentation → Custom Fields
      // → Abilities.
      final presentationY = tester.getTopLeft(find.text('Presentation')).dy;
      final customY = tester.getTopLeft(find.text('Custom Fields')).dy;
      final abilitiesY = tester.getTopLeft(find.text('Abilities')).dy;
      expect(presentationY, lessThan(customY));
      expect(customY, lessThan(abilitiesY));
    },
  );

  testWidgets(
    'Task 010: sheet present but every section\'s rows are empty / non-'
    'string → _SheetPanel is hidden; Custom Fields falls back to its '
    'normal behaviour and the other sections still render',
    (tester) async {
      await seedMirror(
        uuid: heldrekUuid,
        export: {
          'name': 'Heldrek',
          'teaser': 'A wandering warrior.',
          'combat_style': 'Sword and shield',
        },
        abilities: [
          {'name': 'Block', 'description': 'Block one attack'},
        ],
        sheet: {
          'sections': [
            {'label': 'Empty1', 'rows': <dynamic>[]},
            // All rows non-string → filtered out → section dropped.
            {
              'label': 'Empty2',
              'rows': [
                {'label': 'A', 'value': 7},
                {'label': 'B', 'value': null},
              ],
            },
          ],
        },
        lastSyncedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      await tester.pumpWidget(wrap(lmCharacter()));
      await tester.pumpAndSettle();

      // No sheet-panel section headers should appear.
      expect(find.text('Empty1'), findsNothing);
      expect(find.text('Empty2'), findsNothing);

      // The fallback Custom Fields path renders because sheetSections
      // collapsed to empty — same as the pre-Task-009 case.
      expect(find.text('Custom Fields'), findsOneWidget);
      expect(find.text('Sword and shield'), findsOneWidget);

      // Other existing sections still render.
      expect(find.text('Presentation'), findsOneWidget);
      expect(find.text('Abilities'), findsOneWidget);
      expect(find.textContaining('Last synced'), findsOneWidget);
    },
  );
}
