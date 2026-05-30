import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Haptics and device vibration helpers.
abstract final class VibrationUtils {
  /// Short in-app haptic (no extra permission on iOS/Android).
  static Future<void> lightHaptic() async {
    await HapticFeedback.lightImpact();
  }

  /// Whether the device reports a vibrator motor (Android); iOS/web/desktop
  /// are treated as supporting haptics elsewhere.
  static Future<bool?> hasVibratorMotor() async {
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows) {
      return null;
    }
    try {
      return await Vibration.hasVibrator();
    } catch (e, st) {
      debugPrint('VibrationUtils.hasVibratorMotor: $e\n$st');
      return null;
    }
  }

  /// Confirms the app can use vibration/haptics for alerts at startup.
  ///
  /// - Web / iOS / desktop: satisfied (haptics or browser APIs as applicable).
  /// - Android: satisfied if a vibrator is reported, or in [kDebugMode] when
  ///   none is reported (common on emulators).
  static Future<bool> isVibrationCapabilitySatisfied() async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    final v = await hasVibratorMotor();
    if (v == true) return true;
    if (kDebugMode) return true;
    return v != false;
  }

  /// Optional warm-up buzz when the user grants or rechecks permissions.
  static Future<void> vibrateShortPulse({
    int durationMs = 120,
  }) async {
    if (kIsWeb) {
      await HapticFeedback.mediumImpact();
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      await HapticFeedback.mediumImpact();
      return;
    }
    try {
      final has = await Vibration.hasVibrator();
      if (has == true) {
        await Vibration.vibrate(duration: durationMs);
        return;
      }
    } catch (e, st) {
      debugPrint('VibrationUtils.vibrateShortPulse: $e\n$st');
    }
    await HapticFeedback.mediumImpact();
  }
}
