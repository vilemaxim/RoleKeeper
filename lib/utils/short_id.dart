import 'dart:math';

/// Alphanumeric chars for short IDs (0-9, A-Z). Excludes I, O to reduce confusion.
const _chars = '0123456789ABCDEFGHJKMNPQRSTUVWXYZ';

final _rng = Random();

/// Generates a random 3-character alphanumeric ID.
String generateShortId() {
  return List.generate(3, (_) => _chars[_rng.nextInt(_chars.length)]).join();
}

/// Reserved short ID for playtesting.
const String playtestShortId = '000';
