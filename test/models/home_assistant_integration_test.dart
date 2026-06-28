import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/models/home_assistant_integration.dart';

void main() {
  group('HomeAssistantIntegrationConfig', () {
    test('fromMap detects configured key from hash', () {
      final config = HomeAssistantIntegrationConfig.fromMap({
        'enabled': true,
        'apiKeyHash': 'abc123',
      });
      expect(config.enabled, isTrue);
      expect(config.apiKeyConfigured, isTrue);
    });

    test('fromMap empty when no document', () {
      expect(HomeAssistantIntegrationConfig.fromMap(null), equals(
        HomeAssistantIntegrationConfig.empty,
      ));
    });

    test('fromMap apiKeyConfigured false when hash missing', () {
      final config = HomeAssistantIntegrationConfig.fromMap({'enabled': true});
      expect(config.apiKeyConfigured, isFalse);
    });
  });
}
