import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/character.dart';
import '../models/character_stats.dart';
import '../services/character_stats_repository.dart';
import '../services/character_sync_service.dart';
import '../services/characters_repository.dart';
import '../services/game_context_service.dart';
import '../utils/error_reporting.dart';
import '../utils/relative_time.dart';

/// Character detail view. Renders LM-synced stats sections (Presentation,
/// Custom Fields, Abilities) when the character originated from
/// LarpManager; otherwise keeps the existing manual placeholder.
///
/// Task 013: when [character] is LM-synced (i.e. `larpManagerUuid != null`),
/// the AppBar gains a refresh action that re-pulls just this character's
/// LarpManager data via [CharacterSyncService]. The action sits BEFORE the
/// existing archive PopupMenuButton.
class CharacterDetailScreen extends StatelessWidget {
  const CharacterDetailScreen({
    super.key,
    required this.character,
    CharacterStatsRepository? statsRepository,
    CharacterSyncService? syncService,
  })  : _injectedStatsRepository = statsRepository,
        _injectedSyncService = syncService;

  final Character character;
  final CharacterStatsRepository? _injectedStatsRepository;
  final CharacterSyncService? _injectedSyncService;

  CharacterStatsRepository get _statsRepository =>
      _injectedStatsRepository ?? CharacterStatsRepository();

  bool get _isLarpManagerSynced => character.larpManagerUuid != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(character.name),
        actions: [
          if (_isLarpManagerSynced)
            _RefreshAppBarAction(
              characterUuid: character.larpManagerUuid!,
              syncService: _injectedSyncService,
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'archive') _archive(context);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'archive',
                child: Row(
                  children: [
                    Icon(Icons.archive),
                    SizedBox(width: 12),
                    Text('Archive'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IdentityBlock(character: character),
            if (_isLarpManagerSynced)
              _LarpManagerStatsSection(
                characterUuid: character.larpManagerUuid!,
                repository: _statsRepository,
              )
            else
              const _ManualPlaceholderCard(),
          ],
        ),
      ),
    );
  }

  void _archive(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive character?'),
        content: const Text(
          'This will remove the character from your list. You can restore it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      await CharactersRepository().archive(character.id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

/// AppBar action that triggers a Task 013 player-driven refresh of one
/// LM-synced character. Kept as a tight `StatefulWidget` wrapper so the
/// outer [CharacterDetailScreen] stays a `StatelessWidget`: only the
/// in-flight indicator state lives here, and the mirror-doc
/// `StreamBuilder` in `_LarpManagerStatsSection` repaints the page on
/// its own when the callable lands.
class _RefreshAppBarAction extends StatefulWidget {
  const _RefreshAppBarAction({
    required this.characterUuid,
    required this.syncService,
  });

  final String characterUuid;
  final CharacterSyncService? syncService;

  @override
  State<_RefreshAppBarAction> createState() => _RefreshAppBarActionState();
}

class _RefreshAppBarActionState extends State<_RefreshAppBarAction> {
  bool _inFlight = false;

  CharacterSyncService get _service =>
      widget.syncService ?? CharacterSyncService();

  Future<void> _refresh() async {
    if (_inFlight) return;
    final tenant = GameContextService.instance.currentTenant;
    if (tenant == null) return;
    setState(() => _inFlight = true);

    String snackbarText = '';
    try {
      final result = await _service.refresh(
        tenant: tenant,
        characterUuid: widget.characterUuid,
      );
      if (result.ok) {
        snackbarText = 'Character refreshed';
      } else {
        final err = result.error ?? 'unknown error';
        snackbarText = 'Could not refresh: $err';
      }
    } catch (e, st) {
      final report = reportAppError('CharacterDetailScreen.refresh', e, st);
      snackbarText = report.userMessage;
    } finally {
      if (mounted) {
        setState(() => _inFlight = false);
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(snackbarText)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_inFlight) {
      // IconButton has a default size of 48x48 (kMinInteractiveDimension);
      // the icon inside is 24px. Match those so the swap doesn't reflow
      // the AppBar layout.
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    return IconButton(
      icon: const Icon(Icons.refresh),
      tooltip: 'Refresh from LarpManager',
      onPressed: _refresh,
    );
  }
}

class _IdentityBlock extends StatelessWidget {
  const _IdentityBlock({required this.character});

  final Character character;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Chip(
          label: Text('ID: ${character.shortId}'),
          avatar: const Icon(Icons.badge, size: 18),
        ),
        const SizedBox(height: 16),
        if (character.pronouns != null) ...[
          Text(
            character.pronouns!,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
        ],
        if (character.description != null &&
            character.description!.isNotEmpty) ...[
          Text(
            'Description',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(character.description!),
          const SizedBox(height: 24),
        ],
        if (character.gameSystemName != null) ...[
          Chip(
            label: Text(character.gameSystemName!),
            avatar: const Icon(Icons.sports_esports, size: 18),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}

class _ManualPlaceholderCard extends StatelessWidget {
  const _ManualPlaceholderCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Attributes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Add attributes, abilities, and inventory in a future update.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LarpManagerStatsSection extends StatelessWidget {
  const _LarpManagerStatsSection({
    required this.characterUuid,
    required this.repository,
  });

  final String characterUuid;
  final CharacterStatsRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CharacterStats?>(
      stream: repository.watchStats(characterUuid: characterUuid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final report = reportAppError(
            'CharacterDetailScreen.stats',
            snapshot.error!,
            snapshot.stackTrace,
          );
          return Text("Couldn't load stats: ${report.userMessage}");
        }
        if (!snapshot.hasData && snapshot.connectionState != ConnectionState.active) {
          return const Text('Synced: pending');
        }
        final stats = snapshot.data;
        if (stats == null) {
          return const Text(
            'Stats not synced yet — ask your organizer to run a sync.',
          );
        }
        return _StatsBody(stats: stats);
      },
    );
  }
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.stats});

  final CharacterStats stats;

  @override
  Widget build(BuildContext context) {
    // Presentation section is rendered when the export carries narrative
    // content (teaser or long-body). The bare number badge alone is not
    // enough — name+number+uuid-only exports show no section headers per
    // the task spec.
    final hasPresentation =
        stats.teaser != null || stats.presentation != null;

    // Task 010: when the per-character LM HTML sheet has been scraped
    // (Task 008 parser + Task 009 sync), render its sections at the
    // TOP of the body and suppress the Custom Fields panel below
    // (the scraped sheet is canonical and rendering both would
    // double-up every row). When the sheet is absent or its sections
    // are all filtered to empty, the pre-Task-010 Custom Fields
    // fallback continues to render unchanged.
    final hasSheet = stats.sheetSections.isNotEmpty;

    // Task 015: surface the structured `sheet.body` projection
    // (Experience points / ability groups / Inventories) BETWEEN the
    // Custom Fields fallback and the JSON-fed `_AbilitiesBlock`. The
    // body is also nullable: legacy mirror docs that pre-date Task 014
    // (and any character whose LM HTML had no body block) collapse it
    // to null and we render exactly the pre-Task-015 UI. Per user
    // decision the JSON `_AbilitiesBlock` keeps rendering even when
    // the new ability groups are present — two passes of abilities is
    // the explicit price of validating the sheet parser on real data.
    final body = stats.sheetBody;
    final xp = body?.experiencePoints;
    final groups = body?.abilityGroups ?? const <SheetAbilityGroup>[];
    final inventories = body?.inventories ?? const <SheetInventory>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasSheet) _SheetPanel(sections: stats.sheetSections),
        if (hasPresentation)
          _Section(
            label: 'Presentation',
            child: _PresentationBlock(stats: stats),
          ),
        if (!hasSheet && stats.customFields.isNotEmpty)
          _Section(
            label: 'Custom Fields',
            child: _CustomFieldsBlock(fields: stats.customFields),
          ),
        if (xp != null && xp.isNotEmpty)
          _Section(label: 'Experience points', child: Text(xp)),
        for (final group in groups)
          _Section(
            label: group.label,
            child: _SheetAbilityList(abilities: group.abilities),
          ),
        if (inventories.isNotEmpty)
          _Section(
            label: 'Inventories',
            child: _SheetInventoriesBlock(inventories: inventories),
          ),
        if (stats.abilities.isNotEmpty)
          _Section(
            label: 'Abilities',
            child: _AbilitiesBlock(abilities: stats.abilities),
          ),
        _LastSyncedFooter(lastSyncedAt: stats.lastSyncedAt),
      ],
    );
  }
}

/// Renders the scraped LM character-sheet sections (Task 010) at the
/// top of `_StatsBody`. One `_Section` per [SheetSection] so spacing
/// matches the existing Presentation / Custom Fields / Abilities
/// blocks. Section labels and row labels are verbatim from the parser
/// — no humanization, no re-casing, no sorting — to match the LM web
/// page exactly.
class _SheetPanel extends StatelessWidget {
  const _SheetPanel({required this.sections});

  final List<SheetSection> sections;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in sections)
          _Section(
            label: section.label,
            child: _SheetSectionBody(rows: section.rows),
          ),
      ],
    );
  }
}

class _SheetSectionBody extends StatelessWidget {
  const _SheetSectionBody({required this.rows});

  final List<SheetRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows) _LabelValueRow(label: r.label, value: r.value),
      ],
    );
  }
}

/// Section header + body + trailing gap. Shared by every header'd
/// block in `_StatsBody` (sheet panel sections, Presentation, Custom
/// Fields, Experience points, sheet ability groups, Inventories,
/// Abilities) so spacing is identical between them.
class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        child,
        const SizedBox(height: 24),
      ],
    );
  }
}

class _PresentationBlock extends StatelessWidget {
  const _PresentationBlock({required this.stats});

  final CharacterStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stats.number != null) ...[
          Chip(label: Text('#${stats.number}')),
          const SizedBox(height: 8),
        ],
        if (stats.teaser != null) ...[
          Text(stats.teaser!),
          const SizedBox(height: 8),
        ],
        if (stats.presentation != null) Text(stats.presentation!),
      ],
    );
  }
}

class _CustomFieldsBlock extends StatelessWidget {
  const _CustomFieldsBlock({required this.fields});

  final List<CustomField> fields;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final f in fields)
          _LabelValueRow(label: f.label, value: f.value),
      ],
    );
  }
}

/// Two-column label/value row shared by the Custom Fields block and
/// the Task 010 sheet panel. Keeps the flex ratio + on-surface label
/// colour consistent so the two sections look identical.
class _LabelValueRow extends StatelessWidget {
  const _LabelValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 1,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(flex: 2, child: Text(value)),
        ],
      ),
    );
  }
}

class _AbilitiesBlock extends StatelessWidget {
  const _AbilitiesBlock({required this.abilities});

  final List<Ability> abilities;

  @override
  Widget build(BuildContext context) {
    final groups = _groupByType(abilities);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in groups.entries) ...[
          if (entry.key != null) ...[
            const SizedBox(height: 4),
            Text(
              entry.key!,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
          ],
          for (final a in entry.value) _AbilityTile(ability: a),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  /// Returns the abilities keyed by type. When NO ability has a type, the
  /// single bucket key is null and the abilities render flat.
  Map<String?, List<Ability>> _groupByType(List<Ability> items) {
    final hasAnyType = items.any((a) => a.type != null);
    if (!hasAnyType) {
      return {null: items};
    }
    final out = <String?, List<Ability>>{};
    for (final a in items) {
      out.putIfAbsent(a.type, () => <Ability>[]).add(a);
    }
    return out;
  }
}

class _AbilityTile extends StatelessWidget {
  const _AbilityTile({required this.ability});

  final Ability ability;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                ability.name,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              if (ability.cost != null) ...[
                const SizedBox(width: 8),
                Chip(
                  label: Text('Cost ${ability.cost}'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
          if (ability.description != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                ability.description!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Task 015: ability list inside one `_Section` per
/// [SheetAbilityGroup]. Visual match for [_AbilityTile] — a row with
/// the name and an optional `Cost <n>` chip, plus an optional
/// description underneath. Per the user decision we DON'T mark
/// "Helper Abilities" prereq markers visually; they render verbatim
/// like every other group's rows.
class _SheetAbilityList extends StatelessWidget {
  const _SheetAbilityList({required this.abilities});

  final List<SheetAbility> abilities;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final a in abilities) _SheetAbilityTile(ability: a),
      ],
    );
  }
}

class _SheetAbilityTile extends StatelessWidget {
  const _SheetAbilityTile({required this.ability});

  final SheetAbility ability;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                ability.name,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              if (ability.cost != null) ...[
                const SizedBox(width: 8),
                Chip(
                  label: Text('Cost ${ability.cost}'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
          if (ability.description != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                ability.description!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Task 015: stack of one [Card] per [SheetInventory]. Each card has
/// the inventory title (`titleSmall`), each balance as a
/// [_LabelValueRow] (so the two-column look matches Custom Fields and
/// the sheet panel), and — when `detailsUrl` is non-null — a trailing
/// "View on LarpManager" `TextButton.icon` that opens the URL in the
/// system browser.
class _SheetInventoriesBlock extends StatelessWidget {
  const _SheetInventoriesBlock({required this.inventories});

  final List<SheetInventory> inventories;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final inv in inventories) _SheetInventoryCard(inventory: inv),
      ],
    );
  }
}

class _SheetInventoryCard extends StatelessWidget {
  const _SheetInventoryCard({required this.inventory});

  final SheetInventory inventory;

  Future<void> _open(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    String? errorMessage;
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        errorMessage = 'Could not open inventory link.';
      }
    } catch (e, st) {
      final report =
          reportAppError('CharacterDetailScreen.openInventory', e, st);
      errorMessage = report.userMessage;
    }
    if (errorMessage != null) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = inventory.detailsUrl;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              inventory.title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final b in inventory.balances)
              _LabelValueRow(label: b.label, value: b.value),
            if (url != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _open(context, url),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('View on LarpManager'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LastSyncedFooter extends StatelessWidget {
  const _LastSyncedFooter({required this.lastSyncedAt});

  final DateTime? lastSyncedAt;

  @override
  Widget build(BuildContext context) {
    final text = lastSyncedAt == null
        ? 'Synced: pending'
        : 'Last synced ${relativeTime(lastSyncedAt!)}';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
