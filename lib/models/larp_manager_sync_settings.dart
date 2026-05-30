/// Controls Cloud Scheduler–driven LarpManager pulls (see FIREBASE_SETUP.md).
/// Manual sync from the app ignores these flags.
class LarpManagerSyncSettings {
  const LarpManagerSyncSettings({
    required this.scheduledSyncEnabled,
    required this.minIntervalMinutes,
    required this.restrictSyncToWindowUtc,
    required this.windowStartHourUtc,
    required this.windowEndHourUtc,
  });

  final bool scheduledSyncEnabled;
  final int minIntervalMinutes;
  final bool restrictSyncToWindowUtc;
  final int windowStartHourUtc;
  final int windowEndHourUtc;

  static const defaults = LarpManagerSyncSettings(
    scheduledSyncEnabled: false,
    minIntervalMinutes: 15,
    restrictSyncToWindowUtc: false,
    windowStartHourUtc: 8,
    windowEndHourUtc: 22,
  );

  factory LarpManagerSyncSettings.fromMap(Map<String, dynamic>? m) {
    if (m == null) return defaults;
    return LarpManagerSyncSettings(
      scheduledSyncEnabled: m['scheduledSyncEnabled'] == true,
      minIntervalMinutes: _clampInt(m['minIntervalMinutes'], 15, 5, 24 * 60),
      restrictSyncToWindowUtc: m['restrictSyncToWindowUtc'] == true,
      windowStartHourUtc: _clampInt(m['windowStartHourUtc'], 8, 0, 23),
      windowEndHourUtc: _clampInt(m['windowEndHourUtc'], 22, 0, 23),
    );
  }

  Map<String, dynamic> toMap() => {
        'scheduledSyncEnabled': scheduledSyncEnabled,
        'minIntervalMinutes': minIntervalMinutes,
        'restrictSyncToWindowUtc': restrictSyncToWindowUtc,
        'windowStartHourUtc': windowStartHourUtc,
        'windowEndHourUtc': windowEndHourUtc,
      };
}

int _clampInt(Object? raw, int fallback, int lo, int hi) {
  final n = int.tryParse(raw?.toString() ?? '');
  if (n == null) return fallback;
  if (n < lo) return lo;
  if (n > hi) return hi;
  return n;
}
