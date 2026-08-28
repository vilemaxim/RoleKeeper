import 'package:flutter/material.dart';

import '../models/game_role.dart';
import '../models/nfc_hunt.dart';
import '../models/nfc_hunt_scan.dart';
import '../models/nfc_hunt_tag.dart';
import '../utils/geo_distance.dart';
import '../services/nfc_hunt_service.dart';

/// Loads read-only hunt report data for staff/organizers.
abstract class NfcHuntReportsDataSource {
  Future<List<NfcHuntTag>> loadTags(String huntId);
  Future<List<NfcHuntScan>> loadScans(String huntId);
  Future<List<NfcHuntScan>> loadReviewScans(String huntId);
}

/// Firestore-backed report data via [NfcHuntService].
class NfcHuntServiceReportsDataSource implements NfcHuntReportsDataSource {
  NfcHuntServiceReportsDataSource(this._service);

  final NfcHuntService _service;

  @override
  Future<List<NfcHuntTag>> loadTags(String huntId) => _service.listTags(huntId);

  @override
  Future<List<NfcHuntScan>> loadScans(String huntId) => _service.listScans(huntId);

  @override
  Future<List<NfcHuntScan>> loadReviewScans(String huntId) =>
      _service.listReviewScans(huntId);
}

/// Read-only staff/organizer views of hunt tags, scans, review queue, and
/// GPS mismatches (ADR 007).
class NfcHuntReportsScreen extends StatefulWidget {
  const NfcHuntReportsScreen({
    super.key,
    required this.gameRole,
    required this.hunt,
    NfcHuntReportsDataSource? dataSource,
    NfcHuntService? huntService,
  })  : _dataSource = dataSource,
        _huntService = huntService;

  final GameRole gameRole;
  final NfcHunt hunt;
  final NfcHuntReportsDataSource? _dataSource;
  final NfcHuntService? _huntService;

  @override
  State<NfcHuntReportsScreen> createState() => _NfcHuntReportsScreenState();
}

class _NfcHuntReportsScreenState extends State<NfcHuntReportsScreen>
    with SingleTickerProviderStateMixin {
  late final NfcHuntReportsDataSource _dataSource =
      widget._dataSource ??
      NfcHuntServiceReportsDataSource(
        widget._huntService ?? NfcHuntService(),
      );

  late final TabController _tabs;
  bool _loading = true;
  List<NfcHuntTag> _tags = const [];
  List<NfcHuntScan> _scans = const [];
  List<NfcHuntScan> _reviewScans = const [];
  List<_ScanMismatchRow> _mismatches = const [];

  bool get _canViewReports => widget.gameRole.canConfigureStaffIntegrations;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    if (_canViewReports) {
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final tags = await _dataSource.loadTags(widget.hunt.id);
      final scans = await _dataSource.loadScans(widget.hunt.id);
      final reviewScans = await _dataSource.loadReviewScans(widget.hunt.id);
      if (!mounted) return;
      setState(() {
        _tags = tags;
        _scans = scans;
        _reviewScans = reviewScans;
        _mismatches = _computeMismatches(tags, scans);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<_ScanMismatchRow> _computeMismatches(
    List<NfcHuntTag> tags,
    List<NfcHuntScan> scans,
  ) {
    final tagByUid = {for (final t in tags) t.tagUid: t};
    final rows = <_ScanMismatchRow>[];

    for (final scan in scans) {
      final tag = tagByUid[scan.tagUid];
      if (tag == null) continue;
      final meters = fixedTagScanMismatchMeters(
        tagPlacement: tag.placement,
        tagLocation: tag.location,
        scanLocation: scan.location,
      );
      if (meters == null) continue;
      if (!isFixedTagScanMismatch(
        tagPlacement: tag.placement,
        tagLocation: tag.location,
        scanLocation: scan.location,
      )) {
        continue;
      }
      rows.add(_ScanMismatchRow(scan: scan, tag: tag, distanceMeters: meters));
    }

    rows.sort(
      (a, b) => b.distanceMeters.compareTo(a.distanceMeters),
    );
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    if (!_canViewReports) {
      return Scaffold(
        appBar: AppBar(title: Text('${widget.hunt.name} reports')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Hunt reports are available to staff and organizers only.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.hunt.name} reports'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Tags'),
            Tab(text: 'Scans'),
            Tab(text: 'Review queue'),
            Tab(text: 'Location mismatches'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _TagsTab(tags: _tags),
                _ScansTab(scans: _scans),
                _ReviewTab(reviewScans: _reviewScans),
                _MismatchTab(mismatches: _mismatches),
              ],
            ),
    );
  }
}

class _ScanMismatchRow {
  const _ScanMismatchRow({
    required this.scan,
    required this.tag,
    required this.distanceMeters,
  });

  final NfcHuntScan scan;
  final NfcHuntTag tag;
  final double distanceMeters;
}

class _TagsTab extends StatelessWidget {
  const _TagsTab({required this.tags});

  final List<NfcHuntTag> tags;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return const Center(child: Text('No registered tags.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: tags.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final tag = tags[index];
        final placement =
            tag.placement == NfcHuntPlacement.fixed ? 'fixed' : 'floating';
        final coords = tag.location == null
            ? '—'
            : '${tag.location!.latitude.toStringAsFixed(5)}, '
                '${tag.location!.longitude.toStringAsFixed(5)}';
        return ListTile(
          title: Text(tag.label?.isNotEmpty == true ? tag.label! : tag.tagUid),
          subtitle: Text(
            'UID: ${tag.tagUid}\n'
            'Placement: $placement\n'
            'Registered by: ${tag.registeredByUid}\n'
            'Location: $coords',
          ),
          isThreeLine: true,
        );
      },
    );
  }
}

class _ScansTab extends StatelessWidget {
  const _ScansTab({required this.scans});

  final List<NfcHuntScan> scans;

  @override
  Widget build(BuildContext context) {
    if (scans.isEmpty) {
      return const Center(child: Text('No credited scans yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: scans.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final scan = scans[index];
        final loc = scan.location;
        final locText = loc == null
            ? '—'
            : '${loc.latitude.toStringAsFixed(5)}, '
                '${loc.longitude.toStringAsFixed(5)}';
        return ListTile(
          title: Text(scan.characterId),
          subtitle: Text(
            'Tag: ${scan.tagUid}\n'
            'Scanned: ${scan.scannedAt}\n'
            'Location: $locText',
          ),
          isThreeLine: true,
        );
      },
    );
  }
}

class _ReviewTab extends StatelessWidget {
  const _ReviewTab({required this.reviewScans});

  final List<NfcHuntScan> reviewScans;

  @override
  Widget build(BuildContext context) {
    if (reviewScans.isEmpty) {
      return const Center(child: Text('Review queue is empty.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: reviewScans.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final scan = reviewScans[index];
        final loc = scan.location;
        final locText = loc == null
            ? '—'
            : '${loc.latitude.toStringAsFixed(5)}, '
                '${loc.longitude.toStringAsFixed(5)}';
        return ListTile(
          title: Text(scan.tagUid),
          subtitle: Text(
            'Reason: ${scan.reason ?? 'unknown'}\n'
            'Character: ${scan.characterId}\n'
            'Scanned: ${scan.scannedAt}\n'
            'Location: $locText',
          ),
          isThreeLine: true,
        );
      },
    );
  }
}

class _MismatchTab extends StatelessWidget {
  const _MismatchTab({required this.mismatches});

  final List<_ScanMismatchRow> mismatches;

  @override
  Widget build(BuildContext context) {
    if (mismatches.isEmpty) {
      return const Center(child: Text('No location mismatches.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: mismatches.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final row = mismatches[index];
        final distance = row.distanceMeters.round();
        return ListTile(
          title: Text(row.scan.characterId),
          subtitle: Text(
            'Tag: ${row.scan.tagUid}\n'
            'Distance: ${distance}m',
          ),
          isThreeLine: true,
        );
      },
    );
  }
}
