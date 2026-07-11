import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/services/totp_service.dart';

void main() {
  group('Offline medic intervention (per-event TOTP secret, H3)', () {
    test('generated code verifies in the same window with explicit seed', () {
      // Valid Base32 secret (per-event; must not be the global forge seed).
      const eventSecret = 'JBSWY3DPEHPK3PXP';
      final totp = TotpService(seed: eventSecret);
      final code = totp.generateCode();
      expect(code, hasLength(6));
      expect(RegExp(r'^\d{6}$').hasMatch(code), isTrue);
      expect(totp.verify(code), isTrue);
    });

    test('wrong code is rejected for per-event seed', () {
      final totp = TotpService(seed: 'JBSWY3DPEHPK3PXP');
      expect(totp.verify('000000'), isFalse);
    });

    test('default TotpService does not verify codes from global forge seed', () {
      const forgeSeed = 'ROLEKEEPEROFFLINE';
      final defaultTotp = TotpService();
      final forgeTotp = TotpService(seed: forgeSeed);
      final forgedCode = forgeTotp.generateCode();
      expect(defaultTotp.verify(forgedCode), isFalse);
    });

    test('TotpService without cached seed cannot generate offline codes', () {
      final totp = TotpService();
      expect(totp.canGenerateOfflineCode, isFalse);
      expect(totp.verify('123456'), isFalse);
      expect(
        () => totp.generateCode(),
        throwsA(isA<StateError>()),
      );
    });

    test('per-event seeds are isolated from each other', () {
      const secretA = 'JBSWY3DPEHPK3PXP';
      const secretB = 'GEZDGNBVGY3TQOJQ';
      final totpA = TotpService(seed: secretA);
      final totpB = TotpService(seed: secretB);
      final codeA = totpA.generateCode();
      expect(totpA.verify(codeA), isTrue);
      expect(totpB.verify(codeA), isFalse);
    });
  });
}
