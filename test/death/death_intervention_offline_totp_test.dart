import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/services/totp_service.dart';

void main() {
  group('Offline medic intervention (TOTP shared secret)', () {
    test('generated code verifies in the same window', () {
      // Same default seed as production app (valid Base32 for package:otp).
      final totp = TotpService();
      final code = totp.generateCode();
      expect(code, hasLength(6));
      expect(RegExp(r'^\d{6}$').hasMatch(code), isTrue);
      expect(totp.verify(code), isTrue);
    });

    test('wrong code is rejected', () {
      final totp = TotpService();
      expect(totp.verify('000000'), isFalse);
    });
  });
}
