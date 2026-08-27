import 'package:flutter/material.dart';

import '../models/activity_event.dart';
import '../models/game_role.dart';
import '../models/nfc_hunt.dart';
import '../models/nfc_hunt_tag.dart';
import '../services/game_context_service.dart';
import '../services/nfc_hunt_service.dart';
import '../utils/active_events_utils.dart';
import '../utils/error_reporting.dart';
import '../utils/qr_scanner.dart';
import '../utils/scavenger_hunt_qr_parser.dart';

typedef ScanQrCodeFn = Future<String?> Function(BuildContext context);
typedef CaptureLocationFn = Future<ActivityEventLocation?> Function();

/// Organizer/placer incremental tag registration for a hunt.
class NfcHuntTagRegisterScreen extends StatefulWidget {
  const NfcHuntTagRegisterScreen({
    super.key,
    required this.hunt,
    required this.gameRole,
    required this.currentUid,
    this.huntService,
    this.expectedTenantKey,
    this.scanQrCode,
    this.captureLocation,
  });

  final NfcHunt hunt;
  final GameRole gameRole;
  final String currentUid;
  final NfcHuntService? huntService;
  final String? expectedTenantKey;
  final ScanQrCodeFn? scanQrCode;
  final CaptureLocationFn? captureLocation;

  @override
  State<NfcHuntTagRegisterScreen> createState() =>
      _NfcHuntTagRegisterScreenState();
}

class _NfcHuntTagRegisterScreenState extends State<NfcHuntTagRegisterScreen> {
  late final NfcHuntService _service =
      widget.huntService ?? NfcHuntService();

  List<NfcHuntTag> _tags = const [];
  bool _loading = true;
  bool _registering = false;

  String? _scannedTagUid;
  String? _scannedHuntId;
  final _labelController = TextEditingController();
  NfcHuntPlacement _placement = NfcHuntPlacement.floating;

  String get _tenantKey =>
      widget.expectedTenantKey ??
      GameContextService.instance.currentTenant?.tenantKey ??
      '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final tags = await _service.listTags(widget.hunt.id);
      if (!mounted) return;
      setState(() {
        _tags = tags;
        _loading = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      final report = reportAppError('NfcHuntTagRegisterScreen.load', e, st);
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(report.userMessage)),
      );
    }
  }

  Future<void> _scan() async {
    final scan = widget.scanQrCode ??
        (BuildContext ctx) => scanQrCode(
              ctx,
              options: const QrScannerOptions(
                title: 'Scan scavenger tag',
                instructionText: 'Scan the QR code on the physical tag',
              ),
            );

    final raw = await scan(context);
    if (!mounted || raw == null) return;

    final parsed = parseScavengerHuntQr(
      raw,
      expectedTenantKey: _tenantKey.isEmpty ? null : _tenantKey,
    );
    if (parsed == null) {
      final message = raw.contains('rolekeeper:scavenger:') &&
              _tenantKey.isNotEmpty &&
              !raw.contains(_tenantKey)
          ? 'QR code is for a different tenant'
          : 'Invalid scavenger hunt QR code';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }

    if (parsed.huntId != widget.hunt.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR code is for a different hunt')),
      );
      return;
    }

    setState(() {
      _scannedTagUid = parsed.tagUid;
      _scannedHuntId = parsed.huntId;
    });
  }

  Future<void> _register() async {
    final tagUid = _scannedTagUid;
    if (tagUid == null || tagUid.isEmpty) return;

    setState(() => _registering = true);
    try {
      ActivityEventLocation? location;
      if (_placement == NfcHuntPlacement.fixed) {
        final capture =
            widget.captureLocation ?? ActiveEventsUtils.captureLocationForEvent;
        location = await capture();
      }

      await _service.registerTag(
        huntId: _scannedHuntId ?? widget.hunt.id,
        tagUid: tagUid,
        placement: _placement,
        label: _labelController.text.trim().isEmpty
            ? null
            : _labelController.text.trim(),
        location: location,
      );

      if (!mounted) return;
      _labelController.clear();
      setState(() {
        _scannedTagUid = null;
        _scannedHuntId = null;
        _placement = NfcHuntPlacement.floating;
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tag registered')),
      );
    } catch (e, st) {
      if (!mounted) return;
      final report =
          reportAppError('NfcHuntTagRegisterScreen.register', e, st);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(report.userMessage)),
      );
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  String _placementLabel(NfcHuntPlacement p) =>
      p == NfcHuntPlacement.fixed ? 'Fixed' : 'Floating';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = '${_tags.length} / ${widget.hunt.expectedTagCount}';

    return Scaffold(
      appBar: AppBar(title: Text('Register — ${widget.hunt.name}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(progress, style: theme.textTheme.titleMedium),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _registering ? null : _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR'),
                ),
                if (_scannedTagUid != null) ...[
                  const SizedBox(height: 16),
                  Text('Tag: $_scannedTagUid'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _labelController,
                    decoration: const InputDecoration(
                      labelText: 'Label (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Placement', style: theme.textTheme.titleSmall),
                  SegmentedButton<NfcHuntPlacement>(
                    segments: const [
                      ButtonSegment(
                        value: NfcHuntPlacement.floating,
                        label: Text('Floating'),
                      ),
                      ButtonSegment(
                        value: NfcHuntPlacement.fixed,
                        label: Text('Fixed'),
                      ),
                    ],
                    selected: {_placement},
                    onSelectionChanged: (s) {
                      setState(() => _placement = s.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _registering ? null : _register,
                    child: Text(
                      _registering ? 'Registering…' : 'Register tag',
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text('Registered tags', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_tags.isEmpty)
                  const Text('No tags registered yet.')
                else
                  for (final tag in _tags)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        tag.label?.isNotEmpty == true
                            ? tag.label!
                            : tag.tagUid,
                      ),
                      subtitle: Text(
                        '${tag.tagUid} · ${_placementLabel(tag.placement)}',
                      ),
                    ),
              ],
            ),
    );
  }
}
