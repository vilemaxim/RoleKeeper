import 'package:otp/otp.dart';

/// TOTP verification for offline death intervention.
/// Uses an embedded seed (shared secret) - all medics use same secret when offline.
/// In production, this could be per-event or fetched when online.
class TotpService {
  TotpService({String? seed}) : _seed = seed ?? _defaultSeed;

  static const _defaultSeed =
      'ROLEKEEPEROFFLINE'; // Placeholder - replace with proper secret

  final String _seed;

  /// Generate current 6-digit code (for medic's app to display).
  String generateCode() => OTP.generateTOTPCodeString(
        _seed,
        DateTime.now().millisecondsSinceEpoch,
        length: 6,
        isGoogle: true,
      );

  /// Verify that [code] matches current or recent window.
  bool verify(String code) {
    if (code.length != 6) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    const windowMs = 30 * 1000; // 30 sec window
    for (var offset = -1; offset <= 1; offset++) {
      final ts = now + offset * windowMs;
      if (OTP.generateTOTPCodeString(_seed, ts, length: 6, isGoogle: true) == code) {
        return true;
      }
    }
    return false;
  }
}
