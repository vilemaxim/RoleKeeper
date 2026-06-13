import 'package:cloud_firestore/cloud_firestore.dart';

/// Section of stats sourced from a LarpManager mirror doc
/// (`larpManagerMirrorChars/{characterUuid}`).
///
/// See `docs/tasks/ready/007-coder.md` and
/// `functions/src/larpmanager/types.ts` (LarpManagerCharacterExport).
class CharacterStats {
  const CharacterStats({
    required this.name,
    this.number,
    this.teaser,
    this.presentation,
    this.customFields = const <CustomField>[],
    this.abilities = const <Ability>[],
    this.sheetSections = const <SheetSection>[],
    this.lastSyncedAt,
  });

  /// Display name (`export.name`).
  final String name;

  /// LM character number (`export.number`), shown as a badge in Presentation.
  final int? number;

  /// Short one-line tagline (`export.teaser`).
  final String? teaser;

  /// Optional long-body sheet text (`export.presentation` when present).
  final String? presentation;

  /// Anything in `export` that isn't part of the typed projection, ordered
  /// alphabetically by [CustomField.key].
  final List<CustomField> customFields;

  /// Abilities pulled from the `abilities` mirror field. Flat list — the
  /// screen groups by [Ability.type] at render time when grouping is
  /// available, otherwise renders the list as-is.
  final List<Ability> abilities;

  /// Scraped per-character LM HTML sheet, captured by Task 008's
  /// `parseCharacterSheetHtml` and persisted under the mirror doc's
  /// `sheet.sections` field by Task 009's sync wiring. Each section is
  /// rendered in source-HTML order at the top of the detail screen
  /// (Task 010). Empty by default for characters whose mirror doc
  /// pre-dates Task 009 or whose sync ran with `fetchDetails: false`.
  final List<SheetSection> sheetSections;

  /// Server timestamp from the last `runLarpManagerSync` write.
  final DateTime? lastSyncedAt;

  /// Keys in `LarpManagerCharacterExport` (functions/src/larpmanager/types.ts)
  /// that this model surfaces through typed fields (name/number/teaser) or
  /// deliberately ignores (owner identity). They MUST NOT appear in
  /// [customFields].
  ///
  /// `presentation` is also excluded so it doesn't render twice (once in the
  /// Presentation block, once as a custom field).
  static const _typedProjectionKeys = <String>{
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
    'presentation',
  };

  factory CharacterStats.fromMirrorDoc(DocumentSnapshot doc) {
    final raw = doc.data();
    final data = raw is Map<String, dynamic> ? raw : <String, dynamic>{};

    final exportRaw = data['export'];
    final export = exportRaw is Map ? exportRaw : const <dynamic, dynamic>{};

    final name = _asString(export['name']) ?? '';
    final number = _asInt(export['number']);
    // Task 011: teaser is read from the TOP-LEVEL mirror doc field —
    // that's the plain-text projection `runLarpManagerSync` writes
    // after `htmlToPlainText`. Reading from `export.teaser` would
    // surface LM's raw HTML verbatim and defeat the write-side
    // strip. Legacy mirror docs that pre-date Task 011 simply
    // render with no teaser until the next sync repopulates the
    // top-level field.
    final teaser = _asNonEmptyString(data['teaser']);
    final presentation = _asNonEmptyString(export['presentation']);

    final customFields = <CustomField>[];
    for (final entry in export.entries) {
      final key = entry.key;
      if (key is! String) continue;
      if (_typedProjectionKeys.contains(key)) continue;
      final value = _asScalarString(entry.value);
      if (value == null) continue;
      customFields.add(CustomField(
        key: key,
        label: _humanize(key),
        value: value,
      ));
    }
    customFields.sort((a, b) => a.key.compareTo(b.key));

    final abilities = _parseAbilities(data['abilities']);

    final sheetSections = _parseSheetSections(data['sheet']);

    final lastSyncedAt = _asDateTime(data['lastSyncedAt']);

    return CharacterStats(
      name: name,
      number: number,
      teaser: teaser,
      presentation: presentation,
      customFields: List.unmodifiable(customFields),
      abilities: List.unmodifiable(abilities),
      sheetSections: List.unmodifiable(sheetSections),
      lastSyncedAt: lastSyncedAt,
    );
  }

  /// Parses the `sheet` payload written by Task 009's `runLarpManagerSync`
  /// from Task 008's `parseCharacterSheetHtml`. Tolerant by design: any
  /// malformed shape (missing keys, non-list sections, scalar payload,
  /// null) returns `const []` instead of throwing. Rows whose `value`
  /// isn't a non-empty string are dropped; sections whose `rows` end up
  /// empty after that filter are dropped too.
  static List<SheetSection> _parseSheetSections(Object? raw) {
    if (raw is! Map) return const <SheetSection>[];
    final sectionsRaw = raw['sections'];
    if (sectionsRaw is! List) return const <SheetSection>[];
    final out = <SheetSection>[];
    for (final entry in sectionsRaw) {
      if (entry is! Map) continue;
      final rowsRaw = entry['rows'];
      if (rowsRaw is! List) continue;
      final rows = <SheetRow>[];
      for (final r in rowsRaw) {
        if (r is! Map) continue;
        final label = _asString(r['label']) ?? '';
        final value = r['value'];
        if (value is! String || value.isEmpty) continue;
        rows.add(SheetRow(label: label, value: value));
      }
      if (rows.isEmpty) continue;
      final label = _asString(entry['label']) ?? '';
      out.add(SheetSection(label: label, rows: List.unmodifiable(rows)));
    }
    return out;
  }

  static List<Ability> _parseAbilities(Object? raw) {
    if (raw == null) return const <Ability>[];
    if (raw is List) {
      return raw.whereType<Map>().map(_abilityFromMap).toList(growable: false);
    }
    if (raw is Map) {
      // Map shape: { categoryName: [ability, ability, ...], ... }
      final out = <Ability>[];
      for (final entry in raw.entries) {
        final category = entry.key is String ? entry.key as String : null;
        final list = entry.value;
        if (list is! List) continue;
        for (final item in list.whereType<Map>()) {
          out.add(_abilityFromMap(item, defaultType: category));
        }
      }
      return out;
    }
    // Malformed (string, number, bool, etc.) — tolerate per spec.
    return const <Ability>[];
  }

  static Ability _abilityFromMap(Map item, {String? defaultType}) {
    final name = _asString(item['name']) ?? '';
    final cost = _asScalarString(item['cost']);
    final description = _asNonEmptyString(item['description']);
    final typeRaw = item['type'] ?? item['category'];
    final type = _asNonEmptyString(typeRaw) ?? defaultType;
    return Ability(
      name: name,
      cost: cost,
      description: description,
      type: type,
    );
  }

  static String? _asString(Object? v) => v is String ? v : null;

  static String? _asNonEmptyString(Object? v) {
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  /// Accepts a non-empty string or a number; returns its string form. Drops
  /// everything else (null, empty string, list, map, bool, etc.).
  static String? _asScalarString(Object? v) {
    if (v is String) return v.isEmpty ? null : v;
    if (v is num) return v.toString();
    return null;
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static DateTime? _asDateTime(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static String _humanize(String key) {
    return key
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}

/// One free-form export key from LarpManager, ready to render as a row.
class CustomField {
  const CustomField({
    required this.key,
    required this.label,
    required this.value,
  });

  /// Raw `export.{key}`, e.g. `combat_style`.
  final String key;

  /// Humanized label, e.g. `Combat Style`.
  final String label;

  /// Stringified value (number → "5", string → as-is).
  final String value;
}

/// One label/value cell from a scraped LM character-sheet section.
/// Mirrors the TypeScript `CharacterSheetRow` shape in
/// `functions/src/larpmanager/characterSheet.ts` so the rendered detail
/// screen reads the structured payload Task 009's sync wrote verbatim.
class SheetRow {
  const SheetRow({required this.label, required this.value});

  /// Verbatim row label from the parser (no humanization).
  final String label;

  /// Verbatim, non-empty stringified value from the parser.
  final String value;
}

/// One scraped section as LM renders it on the character sheet HTML
/// page (Task 008 parser → Task 009 sync → Task 010 UI). Order is
/// preserved end-to-end so the detail screen matches the LM page.
class SheetSection {
  const SheetSection({required this.label, required this.rows});

  /// Verbatim section heading (empty string for the anonymous
  /// top-of-sheet stats block that LM renders before the first
  /// `<h2>`).
  final String label;

  /// Rows in the exact LM source-HTML order.
  final List<SheetRow> rows;
}

/// One ability from `larpManagerMirrorChars/{uuid}.abilities`.
class Ability {
  const Ability({
    required this.name,
    this.cost,
    this.description,
    this.type,
  });

  final String name;

  /// Stringified cost (LM may surface either int or string).
  final String? cost;

  final String? description;

  /// Category / school / type, used for grouping at render time. May be
  /// supplied per-ability (`type` or `category`) or inherited from the
  /// enclosing map key when LM groups abilities by category.
  final String? type;
}
