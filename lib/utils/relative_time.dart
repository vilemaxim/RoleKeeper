/// Returns a coarse "ago" string for [when] relative to [now] (default
/// `DateTime.now()`).
///
/// Boundaries:
/// - `< 1 minute` (or future)         → "just now"
/// - `1 m .. 59 m`                    → "1 minute ago" / "N minutes ago"
/// - `1 h .. 23 h`                    → "1 hour ago"   / "N hours ago"
/// - `>= 1 day`                       → "1 day ago"    / "N days ago"
///
/// Intentionally simple — no localization, no relative-future, no weeks/months.
/// Hand-rolled to avoid adding an `intl`/`timeago` dependency.
String relativeTime(DateTime when, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final delta = reference.difference(when);

  if (delta.inSeconds < 60) return 'just now';
  if (delta.inMinutes < 60) {
    final n = delta.inMinutes;
    return n == 1 ? '1 minute ago' : '$n minutes ago';
  }
  if (delta.inHours < 24) {
    final n = delta.inHours;
    return n == 1 ? '1 hour ago' : '$n hours ago';
  }
  final n = delta.inDays;
  return n == 1 ? '1 day ago' : '$n days ago';
}
