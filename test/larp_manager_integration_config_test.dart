import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/models/larp_manager_integration_config.dart';

void main() {
  test('fromMap empty', () {
    final c = LarpManagerIntegrationConfig.fromMap(null);
    expect(c.baseUrl, '');
    expect(c.credentialsConfigured, false);
  });

  test('fromMap parses flags', () {
    final c = LarpManagerIntegrationConfig.fromMap({
      'baseUrl': 'https://lm.example',
      'eventSlug': 'run-1',
      'loginPath': '/accounts/login/',
      'fetchDetails': true,
      'credentialsConfigured': true,
    });
    expect(c.baseUrl, 'https://lm.example');
    expect(c.eventSlug, 'run-1');
    expect(c.loginPath, '/accounts/login/');
    expect(c.fetchDetails, true);
    expect(c.credentialsConfigured, true);
  });
}
