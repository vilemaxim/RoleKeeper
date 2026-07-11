import 'package:otp/otp.dart';

/// TOTP verification for offline death intervention using a per-event secret.
class TotpService {
  TotpService({String? seed}) : _seed = seed;

  final String? _seed;

  /// Whether a per-event secret was supplied (cached after online fetch).
  bool get canGenerateOfflineCode =>
      _seed != null && _seed.isNotEmpty;

  /// Generate current 6-digit code (for medic's app to display).
  String generateCode() {
    final seed = _seed;
    if (seed == null || seed.isEmpty) {
      throw StateError('No cached event TOTP secret');
    }
    return OTP.generateTOTPCodeString(
      seed,
      DateTime.now().millisecondsSinceEpoch,
      length: 6,
      isGoogle: true,
    );
  }

  /// Verify that [code] matches current or recent window.
  bool verify(String code) {
    final seed = _seed;
    if (seed == null || seed.isEmpty) return false;
    if (code.length != 6) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    const windowMs = 30 * 1000;
    for (var offset = -1; offset <= 1; offset++) {
      final ts = now + offset * windowMs;
      if (OTP.generateTOTPCodeString(seed, ts, length: 6, isGoogle: true) ==
          code) {
        return true;
      }
    }
    return false;
  }
}
