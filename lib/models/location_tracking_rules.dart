/// Location tracking configuration for a LARP event.
class LocationTrackingRules {
  const LocationTrackingRules({
    required this.enabled,
    required this.pingIntervalSeconds,
  });

  final bool enabled;
  final int pingIntervalSeconds;

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'pingIntervalSeconds': pingIntervalSeconds,
      };

  static LocationTrackingRules fromMap(Map<String, dynamic>? m) {
    if (m == null) return LocationTrackingRules.defaultRules;
    final raw = (m['pingIntervalSeconds'] as num?)?.toInt() ?? 60;
    return LocationTrackingRules(
      enabled: m['enabled'] as bool? ?? false,
      pingIntervalSeconds: _clampPingInterval(raw),
    );
  }

  static int _clampPingInterval(int seconds) {
    if (seconds < 30) return 30;
    if (seconds > 300) return 300;
    return seconds;
  }

  static const defaultRules = LocationTrackingRules(
    enabled: false,
    pingIntervalSeconds: 60,
  );
}
