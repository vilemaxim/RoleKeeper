import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/utils/larp_manager_registration_url.dart';

void main() {
  group('larpManagerRegistrationPageUrl', () {
    test('builds register path from base and slug', () {
      expect(
        larpManagerRegistrationPageUrl(
          baseUrl: 'https://sovereignscrolls.larpmanager.com',
          eventSlug: 'crucible',
        ),
        'https://sovereignscrolls.larpmanager.com/crucible/register/',
      );
    });

    test('normalizes trailing slash on base', () {
      expect(
        larpManagerRegistrationPageUrl(
          baseUrl: 'https://lm.example/',
          eventSlug: 'my-event-1',
        ),
        'https://lm.example/my-event-1/register/',
      );
    });
  });
}
