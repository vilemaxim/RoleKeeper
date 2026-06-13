import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/models/character_stats.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CharacterStats.fromMirrorDoc', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    Future<DocumentSnapshot<Map<String, dynamic>>> seed(
      Map<String, dynamic> data,
    ) async {
      final ref = firestore.collection('mirror').doc('x');
      await ref.set(data);
      return ref.get();
    }

    test('exposes presentation block (name, number, teaser)', () async {
      // Task 011: teaser is read from the top-level mirror doc field
      // (the plain-text projection sync writes). The matching raw HTML
      // also lives inside export.teaser for any future consumer, but
      // CharacterStats.fromMirrorDoc surfaces only the cleaned value.
      final doc = await seed({
        'teaser': 'A wandering warrior.',
        'export': {
          'name': 'Heldrek',
          'number': 42,
          'teaser': '<p>A wandering warrior.</p>',
        },
      });

      final stats = CharacterStats.fromMirrorDoc(doc);

      expect(stats.name, 'Heldrek');
      expect(stats.number, 42);
      expect(stats.teaser, 'A wandering warrior.');
    });

    test('exposes presentation long-body field when present in export',
        () async {
      final doc = await seed({
        'export': {
          'name': 'Heldrek',
          'presentation':
              'A long-form sheet description of the character history.',
        },
      });

      final stats = CharacterStats.fromMirrorDoc(doc);

      expect(
        stats.presentation,
        'A long-form sheet description of the character history.',
      );
    });

    test('filters typed-projection keys out of custom fields', () async {
      final doc = await seed({
        'export': {
          'number': 42,
          'name': 'Heldrek',
          'uuid': 'oxe9sb0w02ig',
          'teaser': 'A wandering warrior.',
          'owner': 'Some Owner',
          'owner_uuid': 'aaaabbbbcccc',
          'player_email': 'p@example.com',
          'player': 'Player Name',
          'user_email': 'u@example.com',
          'email': 'e@example.com',
          'combat_style': 'Sword and shield',
          'background': 'Northern barbarian',
        },
      });

      final stats = CharacterStats.fromMirrorDoc(doc);

      // Typed projection keys must NOT appear as custom fields.
      final keys = stats.customFields.map((f) => f.key).toSet();
      for (final typed in const [
        'number',
        'name',
        'uuid',
        'teaser',
        'owner',
        'owner_uuid',
        'player_email',
        'player',
        'user_email',
        'email',
      ]) {
        expect(
          keys.contains(typed),
          isFalse,
          reason: 'typed projection key "$typed" must not be a custom field',
        );
      }

      // Only the two genuine custom keys remain.
      expect(stats.customFields.map((f) => f.key).toList(),
          ['background', 'combat_style'],
          reason: 'custom fields sorted alphabetically by key');
    });

    test('humanizes snake_case keys to Title Case for the field label',
        () async {
      final doc = await seed({
        'export': {
          'name': 'Heldrek',
          'combat_style': 'Sword and shield',
          'home_region': 'Northern wastes',
        },
      });

      final stats = CharacterStats.fromMirrorDoc(doc);

      final byKey = {for (final f in stats.customFields) f.key: f};
      expect(byKey['combat_style']?.label, 'Combat Style');
      expect(byKey['combat_style']?.value, 'Sword and shield');
      expect(byKey['home_region']?.label, 'Home Region');
      expect(byKey['home_region']?.value, 'Northern wastes');
    });

    test('drops empty/null/non-scalar custom field values', () async {
      final doc = await seed({
        'export': {
          'name': 'Heldrek',
          'background': '',
          'notes': null,
          'level': 5,
          'class_name': 'Wizard',
          'inventory': <String>['rope', 'lantern'],
          'extras': <String, dynamic>{'k': 'v'},
        },
      });

      final stats = CharacterStats.fromMirrorDoc(doc);

      final keys = stats.customFields.map((f) => f.key).toList();
      expect(keys, ['class_name', 'level']);
    });

    test('parses abilities list with mixed shapes (name/cost/desc/type)',
        () async {
      final doc = await seed({
        'export': {'name': 'Heldrek'},
        'abilities': [
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
          {
            'name': 'Stealth',
          },
        ],
      });

      final stats = CharacterStats.fromMirrorDoc(doc);

      expect(stats.abilities, hasLength(3));

      final block = stats.abilities[0];
      expect(block.name, 'Block');
      expect(block.cost, '1');
      expect(block.description, 'Block one attack');
      expect(block.type, 'Combat');

      final mend = stats.abilities[1];
      expect(mend.name, 'Mend');
      expect(mend.cost, isNull);
      expect(mend.description, 'Heal 1 hp');
      expect(mend.type, isNull);

      final stealth = stats.abilities[2];
      expect(stealth.name, 'Stealth');
      expect(stealth.cost, isNull);
      expect(stealth.description, isNull);
      expect(stealth.type, isNull);
    });

    test('returns empty abilities list when abilities payload is malformed',
        () async {
      final doc = await seed({
        'export': {'name': 'Heldrek'},
        'abilities': 'not-a-list-or-map',
      });

      final stats = CharacterStats.fromMirrorDoc(doc);

      expect(stats.abilities, isEmpty);
    });

    test('returns empty abilities list when abilities is null or absent',
        () async {
      final doc = await seed({
        'export': {'name': 'Heldrek'},
      });

      final stats = CharacterStats.fromMirrorDoc(doc);

      expect(stats.abilities, isEmpty);
    });

    test('exposes lastSyncedAt as a DateTime when present', () async {
      final ts = DateTime.utc(2025, 11, 8, 12, 0, 0);
      final doc = await seed({
        'export': {'name': 'Heldrek'},
        'lastSyncedAt': Timestamp.fromDate(ts),
      });

      final stats = CharacterStats.fromMirrorDoc(doc);

      // Timestamp.toDate() returns a local-zone DateTime that represents the
      // same instant as the stored UTC value. Compare instants, not flags.
      expect(stats.lastSyncedAt, isNotNull);
      expect(stats.lastSyncedAt!.isAtSameMomentAs(ts), isTrue);
    });

    test('exposes lastSyncedAt as null when absent', () async {
      final doc = await seed({
        'export': {'name': 'Heldrek'},
      });

      final stats = CharacterStats.fromMirrorDoc(doc);

      expect(stats.lastSyncedAt, isNull);
    });

    // --- Task 010: sheet payload parsing -------------------------------

    test(
      'parses sheet.sections into sheetSections preserving section AND row '
      'order, with labels and values verbatim (no humanization, no sort)',
      () async {
        final doc = await seed({
          'export': {'name': 'Heldrek'},
          // Three sections in deliberately non-alphabetical order — the
          // detail screen renders LM source-HTML order, not alphabetical.
          'sheet': {
            'sections': [
              {
                'label': 'Identity',
                'rows': [
                  {'label': 'Player', 'value': 'Player 1'},
                  {'label': 'Status', 'value': 'Proposed'},
                  {'label': 'Race', 'value': 'Human (Fire Affinity)'},
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
        });

        final stats = CharacterStats.fromMirrorDoc(doc);

        expect(stats.sheetSections, hasLength(3));
        expect(
          stats.sheetSections.map((s) => s.label).toList(),
          ['Identity', 'Stats', 'Affinities'],
          reason: 'sections must preserve LM source-HTML order, NOT sort',
        );
        expect(
          stats.sheetSections[0].rows.map((r) => [r.label, r.value]).toList(),
          [
            ['Player', 'Player 1'],
            ['Status', 'Proposed'],
            ['Race', 'Human (Fire Affinity)'],
          ],
          reason: 'rows must preserve LM source-HTML order verbatim',
        );
        expect(
          stats.sheetSections[1].rows.map((r) => [r.label, r.value]).toList(),
          [
            ['Hit Points/Essence', '42'],
            ['Iron DR', '2'],
          ],
        );
        expect(
          stats.sheetSections[2].rows.map((r) => [r.label, r.value]).toList(),
          [
            ['Total Fire Affinity', '12'],
            ['Effective Body Affinity', '6'],
          ],
        );
      },
    );

    test(
      'drops sheet rows whose value is empty or not a string, and drops '
      'sections whose rows end up empty after filtering',
      () async {
        final doc = await seed({
          'export': {'name': 'Heldrek'},
          'sheet': {
            'sections': [
              {
                'label': 'Mixed',
                'rows': [
                  // Kept.
                  {'label': 'Player', 'value': 'Player 1'},
                  // Empty value — drop.
                  {'label': 'Background', 'value': ''},
                  // Non-string value — drop (per spec).
                  {'label': 'Numeric', 'value': 42},
                  // Null value — drop.
                  {'label': 'Notes', 'value': null},
                  // Kept.
                  {'label': 'Race', 'value': 'Human'},
                ],
              },
              {
                // All rows are non-string → section ends up empty → drop.
                'label': 'AllNonString',
                'rows': [
                  {'label': 'A', 'value': 7},
                  {'label': 'B', 'value': true},
                ],
              },
              {
                // Empty rows array → drop.
                'label': 'EmptyRows',
                'rows': <dynamic>[],
              },
            ],
          },
        });

        final stats = CharacterStats.fromMirrorDoc(doc);

        expect(
          stats.sheetSections.map((s) => s.label).toList(),
          ['Mixed'],
          reason: 'AllNonString and EmptyRows sections must be dropped',
        );
        expect(
          stats.sheetSections[0].rows.map((r) => [r.label, r.value]).toList(),
          [
            ['Player', 'Player 1'],
            ['Race', 'Human'],
          ],
          reason: 'empty/non-string rows are filtered; surviving rows keep order',
        );
      },
    );

    test(
      'tolerates a malformed sheet payload (missing rows key, non-list '
      'sections, scalar sheet) and returns sheetSections: [] rather than '
      'throwing',
      () async {
        final docMissingRows = await seed({
          'export': {'name': 'A'},
          'sheet': {
            'sections': [
              {'label': 'NoRowsKey'},
            ],
          },
        });
        expect(
          CharacterStats.fromMirrorDoc(docMissingRows).sheetSections,
          isEmpty,
          reason: 'a section without a rows key contributes no SheetSection',
        );

        final docNonListSections = await seed({
          'export': {'name': 'B'},
          'sheet': {'sections': 'not-a-list'},
        });
        expect(
          CharacterStats.fromMirrorDoc(docNonListSections).sheetSections,
          isEmpty,
          reason: 'non-list sections payload must not throw',
        );

        final docScalarSheet = await seed({
          'export': {'name': 'C'},
          'sheet': 'this is not a map',
        });
        expect(
          CharacterStats.fromMirrorDoc(docScalarSheet).sheetSections,
          isEmpty,
          reason: 'scalar sheet payload must not throw',
        );

        final docNullSheet = await seed({
          'export': {'name': 'D'},
          'sheet': null,
        });
        expect(
          CharacterStats.fromMirrorDoc(docNullSheet).sheetSections,
          isEmpty,
        );
      },
    );

    test(
      'sheetSections defaults to const [] when no sheet key is present on '
      'the mirror doc (regression guard for pre-Task-009 characters)',
      () async {
        final doc = await seed({
          'export': {'name': 'Heldrek'},
        });

        final stats = CharacterStats.fromMirrorDoc(doc);

        expect(stats.sheetSections, isEmpty);
      },
    );

    // --- Task 011: teaser is read from top-level, not export.teaser ---

    test(
      'Task 011: reads teaser from the TOP-LEVEL mirror doc field — the '
      'plain-text projection written by sync — regardless of what '
      'export.teaser contains',
      () async {
        final doc = await seed({
          'teaser': 'Fire Mage',
          'export': {
            'name': 'Heldrek',
            // The verbatim raw HTML lives under export.teaser, but the
            // model MUST NOT surface this on stats.teaser — that would
            // defeat the write-side strip.
            'teaser': '<p>Fire Mage</p>',
          },
        });

        final stats = CharacterStats.fromMirrorDoc(doc);

        expect(
          stats.teaser,
          'Fire Mage',
          reason: 'teaser must come from data["teaser"] (plain text), '
              'not from export.teaser (raw HTML)',
        );
      },
    );

    test(
      'Task 011: returns teaser == null when the top-level teaser field '
      'is missing (sync omitted it because the strip yielded undefined)',
      () async {
        final doc = await seed({
          'export': {
            'name': 'Heldrek',
            // No top-level teaser, no export.teaser either.
          },
        });

        final stats = CharacterStats.fromMirrorDoc(doc);

        expect(stats.teaser, isNull);
      },
    );

    test(
      'Task 011: returns teaser == null when the top-level teaser field '
      'is the empty string (defensive — sync should never write this but '
      'pre-Task-011 docs and Firestore client edits could)',
      () async {
        final doc = await seed({
          'teaser': '',
          'export': {'name': 'Heldrek'},
        });

        final stats = CharacterStats.fromMirrorDoc(doc);

        expect(stats.teaser, isNull);
      },
    );

    test(
      'Task 011: a legacy mirror doc with raw HTML in export.teaser but '
      'no top-level teaser yields stats.teaser == null (no rendering of '
      'raw HTML) AND "teaser" still does NOT leak into customFields',
      () async {
        final doc = await seed({
          // No top-level teaser key — simulates a doc written before
          // Task 011 by the old sync code path that wrote teaser only
          // inside export.
          'export': {
            'name': 'Heldrek',
            'teaser': '<p>Fire Mage</p>',
          },
        });

        final stats = CharacterStats.fromMirrorDoc(doc);

        expect(
          stats.teaser,
          isNull,
          reason: 'no top-level teaser → stats.teaser must be null, NOT the '
              'legacy raw HTML from export.teaser',
        );

        final keys = stats.customFields.map((f) => f.key).toSet();
        expect(
          keys.contains('teaser'),
          isFalse,
          reason: 'teaser must stay in the typed-projection exclusion set '
              'so the raw HTML never appears as a Custom Fields row either',
        );
      },
    );
  });
}
