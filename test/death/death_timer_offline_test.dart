import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/models/character.dart';
import 'package:rolekeeper/models/death_rules.dart';
import 'package:rolekeeper/services/death_timer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    DeathTimerService.testClock = null;
    DeathTimerService.instance.clear();
  });

  group('DeathTimerService with cached-style death rules (no network)', () {
    late DeathRules rules;
    late Character character;

    setUp(() {
      character = const Character(
        id: 'c1',
        shortId: 'A1B',
        ownerId: 'owner-1',
        name: 'Test Hero',
      );
      rules = DeathRules(
        enabled: true,
        countSeconds: 200,
        stages: const [
          DeathStage(
            id: 's1',
            label: 'Stage one',
            countSeconds: 100,
            playerDescription: 'Holding on',
          ),
        ],
        interventionEnabled: true,
        interventionCountSeconds: 40,
        interventionRoleName: 'combat medic',
        afterDeathTimerText: 'You are out of play. Report to NPC.',
      );
    });

    test('rules expose correct totals and death UI copy (what offline UI uses)', () {
      expect(rules.totalSeconds, 300);
      expect(rules.interventionRoleName, 'combat medic');
      expect(rules.deathExpiredDialogBody, 'You are out of play. Report to NPC.');
      expect(rules.interventionCountSeconds, 40);
    });

    test('remaining death-count seconds match elapsed time (test clock)', () {
      var clock = DateTime.utc(2025, 1, 1, 12, 0, 0);
      DeathTimerService.testClock = () => clock;

      DeathTimerService.instance.setActive(
        ActiveDeathTimer(
          character: character,
          rules: rules,
          activityEventId: 'offline-evt',
          deathCountStartedAt: clock,
        ),
      );

      expect(DeathTimerService.instance.getRemainingSeconds(), 300);
      clock = clock.add(const Duration(seconds: 25));
      expect(DeathTimerService.instance.getRemainingSeconds(), 275);

      clock = DateTime.utc(2025, 1, 1, 12, 0, 0).add(const Duration(seconds: 299));
      expect(DeathTimerService.instance.getRemainingSeconds(), 1);
      clock = clock.add(const Duration(seconds: 1));
      expect(DeathTimerService.instance.getRemainingSeconds(), 0);
      expect(DeathTimerService.instance.tick(), isTrue);
      expect(DeathTimerService.instance.active?.phase, DeathTimerPhase.dead);
    });

    test('online-style medic intervention: phase and intervention countdown', () {
      var clock = DateTime.utc(2025, 3, 10, 10, 0, 0);
      DeathTimerService.testClock = () => clock;

      DeathTimerService.instance.setActive(
        ActiveDeathTimer(
          character: character,
          rules: rules,
          activityEventId: 'evt-online',
          deathCountStartedAt: clock,
        ),
      );

      DeathTimerService.instance.setPhaseIntervention('medic-user-id');
      expect(DeathTimerService.instance.active?.phase, DeathTimerPhase.intervention);
      expect(DeathTimerService.instance.active?.helpingPlayerId, 'medic-user-id');

      expect(DeathTimerService.instance.getRemainingSeconds(), 40);
      clock = clock.add(const Duration(seconds: 15));
      expect(DeathTimerService.instance.getRemainingSeconds(), 25);
    });
  });
}
