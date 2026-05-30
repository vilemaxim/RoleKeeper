import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/utils/larp_manager_instance_parser.dart';

void main() {
  group('parseLarpManagerInstance', () {
    test('parses bare host', () {
      final t = parseLarpManagerInstance('events.example.com');
      expect(t, isNotNull);
      expect(t!.baseUrl, 'https://events.example.com');
      expect(t.eventSlug, '');
      expect(t.instanceId, 'events.example.com');
      expect(t.tenant, isNull);
    });

    test('parses https URL with slug', () {
      final t = parseLarpManagerInstance('https://larpmanager.com/my-run-2025/foo');
      expect(t, isNotNull);
      expect(t!.baseUrl, 'https://larpmanager.com');
      expect(t.eventSlug, 'my-run-2025');
      expect(t.instanceId, 'larpmanager.com');
      expect(t.tenant!.eventSlug, 'my-run-2025');
    });

    test('returns null for garbage', () {
      expect(parseLarpManagerInstance(''), isNull);
      expect(parseLarpManagerInstance('nohost'), isNull);
      expect(parseLarpManagerInstance('ftp://x.com'), isNull);
    });
  });

  group('LarpManagerInstanceTarget.tenant', () {
    test('is stable for same inputs', () {
      const a = LarpManagerInstanceTarget(
        baseUrl: 'https://lm.example',
        eventSlug: 'evt',
      );
      const b = LarpManagerInstanceTarget(
        baseUrl: 'https://lm.example',
        eventSlug: 'evt',
      );
      expect(a.tenant, b.tenant);
      expect(a.tenant!.tenantKey, 'lm.example::evt');
    });

    test('canonical event URL is full page path', () {
      const t = LarpManagerInstanceTarget(
        baseUrl: 'https://sovereignscrolls.larpmanager.com',
        eventSlug: 'crucible',
      );
      expect(
        t.canonicalEventPageUrl,
        'https://sovereignscrolls.larpmanager.com/crucible',
      );
      expect(t.instanceId, 'sovereignscrolls.larpmanager.com');
      expect(t.tenant!.eventSlug, 'crucible');
      expect(
        t.tenant!.tenantKey,
        'sovereignscrolls.larpmanager.com::crucible',
      );
    });

    test('slug casing is normalized in canonical and tenant', () {
      const a = LarpManagerInstanceTarget(
        baseUrl: 'https://sovereignscrolls.larpmanager.com',
        eventSlug: 'ruintest',
      );
      const b = LarpManagerInstanceTarget(
        baseUrl: 'https://sovereignscrolls.larpmanager.com',
        eventSlug: 'RUINtest',
      );
      expect(a.canonicalEventPageUrl, b.canonicalEventPageUrl);
      expect(a.tenant, b.tenant);
    });
  });
}
