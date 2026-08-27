import 'package:cloud_firestore/cloud_firestore.dart';

/// Scavenger hunt config at `nfcHunts/{huntId}` (ADR 007).
class NfcHunt {
  const NfcHunt({
    required this.id,
    required this.enabled,
    required this.name,
    required this.expectedTagCount,
    required this.placerUids,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final bool enabled;
  final String name;
  final int expectedTagCount;
  final List<String> placerUids;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'name': name,
        'expectedTagCount': expectedTagCount,
        'placerUids': placerUids,
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      };

  static NfcHunt fromMap(String id, Map<String, dynamic>? m) {
    if (m == null) {
      return NfcHunt(
        id: id,
        enabled: false,
        name: '',
        expectedTagCount: 0,
        placerUids: const [],
      );
    }
    return NfcHunt(
      id: id,
      enabled: m['enabled'] as bool? ?? false,
      name: m['name'] as String? ?? '',
      expectedTagCount: (m['expectedTagCount'] as num?)?.toInt() ?? 0,
      placerUids: _stringList(m['placerUids']),
      createdAt: _parseTimestamp(m['createdAt']),
      updatedAt: _parseTimestamp(m['updatedAt']),
    );
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<String>().toList();
  }

  static DateTime? _parseTimestamp(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }
}
