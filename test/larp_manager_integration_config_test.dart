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
      'credentialsConfigured': true,
    });
    expect(c.baseUrl, 'https://lm.example');
    expect(c.eventSlug, 'run-1');
    expect(c.loginPath, '/accounts/login/');
    expect(c.credentialsConfigured, true);
  });

  // Task 012 (docs/adr/0001-remove-fetchdetails-toggle.md): the
  // LarpManagerIntegrationConfig model no longer carries a
  // `fetchDetails` field. The loader still TOLERATES a legacy
  // `fetchDetails: bool` in stored Firestore docs without throwing,
  // but the parsed model has no such getter.
  group('Task 012: fetchDetails removed from LarpManagerIntegrationConfig', () {
    test(
      'const constructor accepts only baseUrl, eventSlug, loginPath, '
      'credentialsConfigured — no fetchDetails parameter',
      () {
        const c = LarpManagerIntegrationConfig(
          baseUrl: 'https://lm.example',
          eventSlug: 'run-1',
          loginPath: '/login/',
          credentialsConfigured: true,
        );
        expect(c.baseUrl, 'https://lm.example');
        expect(c.eventSlug, 'run-1');
        expect(c.loginPath, '/login/');
        expect(c.credentialsConfigured, true);
      },
    );

    test(
      'fromMap silently ignores a legacy fetchDetails:true field in the '
      'stored map (loader tolerance — no Firestore migration was run)',
      () {
        final c = LarpManagerIntegrationConfig.fromMap({
          'baseUrl': 'https://lm.example',
          'eventSlug': 'run-1',
          'loginPath': '/login/',
          // Legacy field that some Firestore docs still carry from
          // before Task 012. Loader must read past it without throwing.
          'fetchDetails': true,
          'credentialsConfigured': true,
        });
        expect(c.baseUrl, 'https://lm.example');
        expect(c.eventSlug, 'run-1');
        expect(c.loginPath, '/login/');
        expect(c.credentialsConfigured, true);
      },
    );
  });
}
