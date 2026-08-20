import 'package:cloud_firestore/cloud_firestore.dart';

import 'activity_event.dart';

/// Tag placement: GPS-anchored (`fixed`) or movable (`floating`).
enum NfcHuntPlacement { fixed, floating }

/// Registered scavenger-hunt tag at `nfcHunts/{huntId}/tags/{tagUid}`.
class NfcHuntTag {
  const NfcHuntTag({
    required this.tagUid,
    required this.placement,
    required this.registeredByUid,
    required this.registeredAt,
    this.label,
    this.location,
  });

  final String tagUid;
  final NfcHuntPlacement placement;
  final String registeredByUid;
  final DateTime registeredAt;
  final String? label;
  final ActivityEventLocation? location;

  Map<String, dynamic> toMap() => {
        'placement': placement == NfcHuntPlacement.fixed ? 'fixed' : 'floating',
        'registeredByUid': registeredByUid,
        'registeredAt': Timestamp.fromDate(registeredAt),
        if (label != null) 'label': label,
        if (placement == NfcHuntPlacement.fixed && location != null)
          'location': location!.toMap(),
      };

  static NfcHuntTag fromMap(String tagUid, Map<String, dynamic>? m) {
    final data = m ?? const <String, dynamic>{};
    return NfcHuntTag(
      tagUid: tagUid,
      placement: data['placement'] == 'fixed'
          ? NfcHuntPlacement.fixed
          : NfcHuntPlacement.floating,
      registeredByUid: data['registeredByUid'] as String? ?? '',
      registeredAt: _parseTimestamp(data['registeredAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      label: data['label'] as String?,
      location: ActivityEventLocation.fromMap(data['location']),
    );
  }

  static DateTime? _parseTimestamp(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }
}
