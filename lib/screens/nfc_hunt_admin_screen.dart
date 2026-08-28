import 'package:flutter/material.dart';

import '../models/game_role.dart';
import '../models/nfc_hunt.dart';
import '../services/game_context_service.dart';
import '../services/nfc_hunt_service.dart';
import '../utils/error_reporting.dart';
import 'nfc_hunt_tag_register_screen.dart';
import 'nfc_hunt_reports_screen.dart';

/// Organizer hunt management + placer/organizer entry to tag registration.
class NfcHuntAdminScreen extends StatefulWidget {
  const NfcHuntAdminScreen({
    super.key,
    required this.gameRole,
    required this.currentUid,
    this.huntService,
    this.members = const [],
  });

  final GameRole gameRole;
  final String currentUid;
  final NfcHuntService? huntService;

  /// Event members for placer picker: maps with `uid` and optional
  /// `displayName` / `email`.
  final List<Map<String, String>> members;

  @override
  State<NfcHuntAdminScreen> createState() => _NfcHuntAdminScreenState();
}

class _NfcHuntAdminScreenState extends State<NfcHuntAdminScreen> {
  late final NfcHuntService _service =
      widget.huntService ?? NfcHuntService();

  List<NfcHunt> _hunts = const [];
  final Map<String, int> _tagCounts = {};
  bool _loading = true;
  bool _creating = false;

  final _nameController = TextEditingController();
  final _countController = TextEditingController(text: '1');

  bool get _isOrganizer => widget.gameRole.canConfigureDeathRules;

  bool _canRegisterTags(NfcHunt hunt) =>
      _isOrganizer || hunt.placerUids.contains(widget.currentUid);

  void _showError(String contextLabel, Object e, StackTrace st) {
    if (!mounted) return;
    final report = reportAppError(contextLabel, e, st);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(report.userMessage)),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _countController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final hunts = await _service.listHunts();
      final counts = <String, int>{};
      for (final h in hunts) {
        final tags = await _service.listTags(h.id);
        counts[h.id] = tags.length;
      }
      if (!mounted) return;
      setState(() {
        _hunts = hunts;
        _tagCounts
          ..clear()
          ..addAll(counts);
        _loading = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('NfcHuntAdminScreen.load', e, st);
    }
  }

  Future<void> _createHunt() async {
    final name = _nameController.text.trim();
    final count = int.tryParse(_countController.text.trim()) ?? 0;
    if (name.isEmpty || count < 0) return;
    setState(() => _creating = true);
    try {
      await _service.createHunt(name: name, expectedTagCount: count);
      _nameController.clear();
      _countController.text = '1';
      await _load();
    } catch (e, st) {
      _showError('NfcHuntAdminScreen.createHunt', e, st);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _toggleEnabled(NfcHunt hunt, bool enabled) async {
    try {
      await _service.setEnabled(hunt.id, enabled);
      await _load();
    } catch (e, st) {
      _showError('NfcHuntAdminScreen.setEnabled', e, st);
    }
  }

  Future<void> _editPlacers(NfcHunt hunt) async {
    final selected = Set<String>.from(hunt.placerUids);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Placers'),
              content: SizedBox(
                width: 360,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final m in widget.members)
                      CheckboxListTile(
                        value: selected.contains(m['uid']),
                        title: Text(
                          m['displayName']?.isNotEmpty == true
                              ? m['displayName']!
                              : (m['email'] ?? m['uid'] ?? ''),
                        ),
                        subtitle: Text(m['uid'] ?? ''),
                        onChanged: (v) {
                          setDialogState(() {
                            final uid = m['uid'];
                            if (uid == null) return;
                            if (v == true) {
                              selected.add(uid);
                            } else {
                              selected.remove(uid);
                            }
                          });
                        },
                      ),
                    if (widget.members.isEmpty)
                      const Text('No members available to assign.'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, selected),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null) return;
    try {
      await _service.setPlacerUids(hunt.id, result.toList());
      await _load();
    } catch (e, st) {
      _showError('NfcHuntAdminScreen.setPlacerUids', e, st);
    }
  }

  void _openRegister(NfcHunt hunt) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NfcHuntTagRegisterScreen(
          hunt: hunt,
          gameRole: widget.gameRole,
          currentUid: widget.currentUid,
          huntService: _service,
          expectedTenantKey:
              GameContextService.instance.currentTenant?.tenantKey,
        ),
      ),
    );
  }

  void _openReports(NfcHunt hunt) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NfcHuntReportsScreen(
          gameRole: widget.gameRole,
          hunt: hunt,
          huntService: _service,
        ),
      ),
    );
  }

  bool get _canViewReports => widget.gameRole.canConfigureStaffIntegrations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scavenger hunts')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Scavenger hunts', style: theme.textTheme.titleLarge),
                const SizedBox(height: 16),
                if (_isOrganizer) ...[
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Hunt name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _countController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Expected tag count',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed: _creating ? null : _createHunt,
                      child: Text(_creating ? 'Creating…' : 'Create hunt'),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                if (_hunts.isEmpty)
                  const Text('No hunts yet.')
                else
                  for (final hunt in _hunts) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(hunt.name, style: theme.textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(
                              '${_tagCounts[hunt.id] ?? 0} / ${hunt.expectedTagCount}',
                            ),
                            if (_isOrganizer) ...[
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Enabled'),
                                value: hunt.enabled,
                                onChanged: (v) => _toggleEnabled(hunt, v),
                              ),
                              TextButton(
                                onPressed: () => _editPlacers(hunt),
                                child: const Text('Edit Placers'),
                              ),
                            ],
                            if (_canRegisterTags(hunt))
                              TextButton(
                                onPressed: () => _openRegister(hunt),
                                child: const Text('Register tags'),
                              ),
                            if (_canViewReports)
                              TextButton(
                                onPressed: () => _openReports(hunt),
                                child: const Text('View reports'),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
    );
  }
}
