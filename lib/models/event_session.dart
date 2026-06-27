import 'package:cloud_firestore/cloud_firestore.dart';

/// Live event session state at `eventSession/config`.
class EventSession {
  const EventSession({
    required this.isLive,
    this.liveStartedAt,
    this.liveEndedAt,
    this.scheduledStartAt,
    this.scheduledEndAt,
  });

  final bool isLive;
  final DateTime? liveStartedAt;
  final DateTime? liveEndedAt;
  final DateTime? scheduledStartAt;
  final DateTime? scheduledEndAt;

  static const defaultSession = EventSession(isLive: false);

  static EventSession fromMap(Map<String, dynamic>? m) {
    if (m == null) return defaultSession;
    return EventSession(
      isLive: m['isLive'] as bool? ?? false,
      liveStartedAt: _parseTimestamp(m['liveStartedAt']),
      liveEndedAt: _parseTimestamp(m['liveEndedAt']),
      scheduledStartAt: _parseTimestamp(m['scheduledStartAt']),
      scheduledEndAt: _parseTimestamp(m['scheduledEndAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'isLive': isLive,
        if (liveStartedAt != null)
          'liveStartedAt': Timestamp.fromDate(liveStartedAt!),
        if (liveEndedAt != null)
          'liveEndedAt': Timestamp.fromDate(liveEndedAt!),
        if (scheduledStartAt != null)
          'scheduledStartAt': Timestamp.fromDate(scheduledStartAt!),
        if (scheduledEndAt != null)
          'scheduledEndAt': Timestamp.fromDate(scheduledEndAt!),
      };

  static DateTime? _parseTimestamp(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }
}
