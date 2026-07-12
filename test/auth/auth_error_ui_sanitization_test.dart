// Task 008 L1 — Auth error UI must use reportAppError (no raw snapshot.error).
//
// Source-level guards so the contract is enforced even before widget harness
// injection lands. `flutter test` runs with the project root as cwd.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/utils/error_reporting.dart';

void main() {
  group('Task 008 L1 — auth gate error sanitization', () {
    late final String authGateSrc;
    late final String signedInGateSrc;

    setUpAll(() {
      authGateSrc = File('lib/auth_gate.dart').readAsStringSync();
      signedInGateSrc =
          File('lib/widgets/signed_in_gate.dart').readAsStringSync();
    });

    test('auth_gate.dart uses reportAppError for stream errors', () {
      expect(
        authGateSrc.contains('reportAppError'),
        isTrue,
        reason:
            'AuthGate must map snapshot.error through reportAppError so the '
            'UI never shows raw exception strings (finding L1).',
      );
      expect(
        authGateSrc.contains(r'${snapshot.error}'),
        isFalse,
        reason:
            'Raw snapshot.error interpolation leaks Firebase/auth internals '
            'into the UI.',
      );
      expect(
        authGateSrc.contains('Auth error:'),
        isFalse,
        reason:
            'Hard-coded "Auth error:" prefix with raw exception must be '
            'replaced by reportAppError.userMessage.',
      );
    });

    test('signed_in_gate.dart uses reportAppError for route errors', () {
      expect(
        signedInGateSrc.contains('reportAppError'),
        isTrue,
        reason:
            'SignedInGate must map snapshot.error through reportAppError '
            '(finding L1).',
      );
      expect(
        signedInGateSrc.contains(r'${snapshot.error}'),
        isFalse,
        reason:
            'Raw snapshot.error in "Could not load your profile (...)" '
            'leaks exception detail into the UI.',
      );
    });

    test('unknown auth-style exception yields user-safe message only', () {
      // Mirrors what AuthGate / SignedInGate should show after reportAppError.
      final report = reportAppError(
        'AuthGate.authState',
        Exception('firebase_auth/network-request-failed: secret stack detail'),
      );
      expect(report.userMessage, contains('contact your event administrator'));
      expect(report.userMessage, isNot(contains('network-request-failed')));
      expect(report.userMessage, isNot(contains('secret stack detail')));
      expect(report.userMessage, isNot(contains('Exception:')));
    });
  });
}
