import 'package:flutter/material.dart';

import '../models/death_rules.dart';
import '../models/event_session.dart';
import '../services/event_session_repository.dart';
import '../services/rules_repository.dart';
import '../utils/error_reporting.dart';
import '../utils/relative_time.dart';

/// Screen for configuring rules. Currently shows Death rules form.
class RulesScreen extends StatefulWidget {
  const RulesScreen({
    super.key,
    this.eventSessionRepository,
  });

  final EventSessionRepository? eventSessionRepository;

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  late final EventSessionRepository _eventSessionRepo =
      widget.eventSessionRepository ?? EventSessionRepository();
  final _repo = RulesRepository();
  DeathRules _rules = DeathRules.defaultRules;
  EventSession _eventSession = EventSession.defaultSession;
  bool _loading = true;
  bool _saving = false;
  bool _sessionBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final deathRulesFuture = _repo.getDeathRules();
    final eventSessionFuture = _eventSessionRepo.get();
    final deathRules = await deathRulesFuture;
    final eventSession = await eventSessionFuture;
    setState(() {
      _rules = deathRules;
      _eventSession = eventSession;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _repo.saveDeathRules(_rules);
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rules'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _rules.enabled ? _save : null,
              child: const Text('Save'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _buildEventSessionSection(),
                const SizedBox(height: 32),
                _buildDeathSection(),
              ],
            ),
    );
  }

  Widget _buildEventSessionSection() {
    final session = _eventSession;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Event session', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          session.isLive ? 'Live' : 'Not live',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: session.isLive ? Colors.green : null,
              ),
        ),
        if (session.liveStartedAt != null) ...[
          const SizedBox(height: 8),
          Text(
            'Started ${relativeTime(session.liveStartedAt!)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        if (session.liveEndedAt != null) ...[
          const SizedBox(height: 4),
          Text(
            'Ended ${relativeTime(session.liveEndedAt!)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 16),
        if (_sessionBusy)
          const Center(child: CircularProgressIndicator())
        else if (session.isLive)
          FilledButton.tonal(
            onPressed: () => _confirmEndEvent(context),
            child: const Text('End event'),
          )
        else
          FilledButton(
            onPressed: () => _confirmStartEvent(context),
            child: const Text('Start event'),
          ),
      ],
    );
  }

  Future<void> _confirmStartEvent(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start event?'),
        content: const Text(
          'Players with location opt-in will begin pinging while the event is live.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Start event'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runSessionAction(_eventSessionRepo.startEvent);
  }

  Future<void> _confirmEndEvent(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End event?'),
        content: const Text(
          'Location pinging will stop until the event is started again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End event'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runSessionAction(_eventSessionRepo.endEvent);
  }

  Future<void> _runSessionAction(Future<void> Function() action) async {
    setState(() => _sessionBusy = true);
    try {
      await action();
      final session = await _eventSessionRepo.get();
      if (!mounted) return;
      setState(() {
        _eventSession = session;
        _sessionBusy = false;
      });
    } catch (e, st) {
      final report = reportAppError('RulesScreen.eventSession', e, st);
      if (!mounted) return;
      setState(() => _sessionBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(report.userMessage)),
      );
    }
  }

  Widget _buildDeathSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElevatedButton(
          onPressed: () => _showDeathForm(context),
          child: const Text('Death'),
        ),
      ],
    );
  }

  void _showDeathForm(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _DeathForm(
        rules: _rules,
        onSaved: (r) {
          setState(() => _rules = r);
          _save();
          Navigator.pop(ctx);
        },
      ),
    );
  }
}

class _DeathForm extends StatefulWidget {
  const _DeathForm({required this.rules, required this.onSaved});

  final DeathRules rules;
  final void Function(DeathRules) onSaved;

  @override
  State<_DeathForm> createState() => _DeathFormState();
}

class _DeathFormState extends State<_DeathForm> {
  late bool _enabled;
  late int _deathCountMinutes;
  late int _deathCountSeconds;
  late List<DeathStage> _stages;
  late bool _interventionEnabled;
  late int _interventionMinutes;
  late int _interventionSeconds;
  late String _interventionRoleName;
  late TextEditingController _afterDeathTimerCtrl;

  @override
  void initState() {
    super.initState();
    _enabled = widget.rules.enabled;
    final totalDeathSeconds = widget.rules.countSeconds;
    _deathCountMinutes = totalDeathSeconds ~/ 60;
    _deathCountSeconds = totalDeathSeconds % 60;
    _stages = List.from(widget.rules.stages);
    _interventionEnabled = widget.rules.interventionEnabled;
    final totalInterventionSeconds = widget.rules.interventionCountSeconds;
    _interventionMinutes = totalInterventionSeconds ~/ 60;
    _interventionSeconds = totalInterventionSeconds % 60;
    _interventionRoleName = widget.rules.interventionRoleName;
    _afterDeathTimerCtrl =
        TextEditingController(text: widget.rules.afterDeathTimerText);
  }

  @override
  void dispose() {
    _afterDeathTimerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Death Rules', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            SwitchListTile(
              title: const Text('Enable'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            if (_enabled) ...[
              const SizedBox(height: 16),
              Text(
                'Count until death',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: _deathCountMinutes.toString(),
                      decoration: const InputDecoration(
                        labelText: 'Minutes',
                        hintText: '5',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => setState(() {
                        _deathCountMinutes =
                            (int.tryParse(v) ?? 0).clamp(0, 999999);
                      }),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      initialValue: _deathCountSeconds.toString(),
                      decoration: const InputDecoration(
                        labelText: 'Seconds',
                        hintText: '0',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => setState(() {
                        _deathCountSeconds =
                            (int.tryParse(v) ?? 0).clamp(0, 59);
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ..._stages.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _StageCard(
                      stage: e.value,
                      onRemove: () =>
                          setState(() => _stages.removeAt(e.key)),
                      onChanged: (s) => setState(() {
                        _stages[e.key] = s;
                      }),
                    ),
                  )),
              TextButton.icon(
                onPressed: () => setState(() {
                  _stages.add(DeathStage(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    label: 'Stage ${_stages.length + 1}',
                    countSeconds: 60,
                    playerDescription: '',
                  ));
                }),
                icon: const Icon(Icons.add),
                label: const Text('Add stage'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _afterDeathTimerCtrl,
                decoration: const InputDecoration(
                  labelText: 'Text to display after the death timer runs out',
                  hintText:
                      'Leave blank for the default message about your character dying.',
                  alignLabelWithHint: true,
                ),
                minLines: 3,
                maxLines: 8,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text(
                    'Death intervention (Can people help dying characters?)'),
                value: _interventionEnabled,
                onChanged: (v) => setState(() => _interventionEnabled = v),
              ),
              if (_interventionEnabled) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextFormField(
                    initialValue: _interventionRoleName,
                    decoration: const InputDecoration(
                      labelText: 'Role that can intervene',
                      hintText: 'e.g. medic, healer',
                    ),
                    onChanged: (v) => setState(() =>
                        _interventionRoleName =
                            v.trim().isNotEmpty ? v.trim() : 'medic'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Intervention count (time to revive)',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: _interventionMinutes.toString(),
                              decoration: const InputDecoration(
                                labelText: 'Minutes',
                                hintText: '1',
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (v) => setState(() {
                                _interventionMinutes =
                                    (int.tryParse(v) ?? 0).clamp(0, 999999);
                              }),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              initialValue: _interventionSeconds.toString(),
                              decoration: const InputDecoration(
                                labelText: 'Seconds',
                                hintText: '0',
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (v) => setState(() {
                                _interventionSeconds =
                                    (int.tryParse(v) ?? 0).clamp(0, 59);
                              }),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => widget.onSaved(_buildRules()),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  DeathRules _buildRules() {
    final interventionTotal =
        _interventionMinutes * 60 + _interventionSeconds;
    return DeathRules(
      enabled: _enabled,
      countSeconds: _deathCountMinutes * 60 + _deathCountSeconds,
      stages: _stages,
      interventionEnabled: _interventionEnabled,
      interventionCountSeconds: interventionTotal > 0 ? interventionTotal : 60,
      interventionRoleName: _interventionRoleName.trim().isNotEmpty
          ? _interventionRoleName.trim()
          : 'medic',
      afterDeathTimerText: _afterDeathTimerCtrl.text,
    );
  }
}

class _StageCard extends StatefulWidget {
  const _StageCard({
    required this.stage,
    required this.onRemove,
    required this.onChanged,
  });

  final DeathStage stage;
  final VoidCallback onRemove;
  final void Function(DeathStage) onChanged;

  @override
  State<_StageCard> createState() => _StageCardState();
}

class _StageCardState extends State<_StageCard> {
  late TextEditingController _labelCtrl;
  late TextEditingController _countCtrl;
  late TextEditingController _descCtrl;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.stage.label);
    _countCtrl = TextEditingController(text: widget.stage.countSeconds.toString());
    _descCtrl = TextEditingController(text: widget.stage.playerDescription);
  }

  @override
  void didUpdateWidget(_StageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stage.id != widget.stage.id) {
      _labelCtrl.text = widget.stage.label;
      _countCtrl.text = widget.stage.countSeconds.toString();
      _descCtrl.text = widget.stage.playerDescription;
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _countCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(labelText: 'Label'),
                    controller: _labelCtrl,
                    onChanged: (v) => widget.onChanged(DeathStage(
                          id: widget.stage.id,
                          label: v,
                          countSeconds: widget.stage.countSeconds,
                          playerDescription: widget.stage.playerDescription,
                        )),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: widget.onRemove,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(labelText: 'Count (seconds)'),
              keyboardType: TextInputType.number,
              controller: _countCtrl,
              onChanged: (v) => widget.onChanged(DeathStage(
                    id: widget.stage.id,
                    label: widget.stage.label,
                    countSeconds: int.tryParse(v) ?? 60,
                    playerDescription: widget.stage.playerDescription,
                  )),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Player-facing description',
              ),
              maxLines: 2,
              controller: _descCtrl,
              onChanged: (v) => widget.onChanged(DeathStage(
                    id: widget.stage.id,
                    label: widget.stage.label,
                    countSeconds: widget.stage.countSeconds,
                    playerDescription: v,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}
