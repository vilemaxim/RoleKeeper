import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/models/larp_manager_sync_settings.dart';

void main() {
  test('defaults: scheduled sync off', () {
    expect(LarpManagerSyncSettings.defaults.scheduledSyncEnabled, false);
    expect(LarpManagerSyncSettings.defaults.minIntervalMinutes, 15);
  });

  test('fromMap parses enabled and clamps interval', () {
    final s = LarpManagerSyncSettings.fromMap({
      'scheduledSyncEnabled': true,
      'minIntervalMinutes': 99999,
    });
    expect(s.scheduledSyncEnabled, true);
    expect(s.minIntervalMinutes, 24 * 60);
  });
}
