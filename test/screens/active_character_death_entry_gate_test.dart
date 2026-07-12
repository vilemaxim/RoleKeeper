// Task 016 — Active character on home + death-timer entry gate.
//
// Source-level guards pin UI contracts before injectable widget harnesses land.
// `flutter test` runs with the project root as cwd.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/models/game_role.dart';

void main() {
  late final String homeSrc;
  late final String rulesAidsSrc;
  late final String deathConfirmSrc;

  setUpAll(() {
    homeSrc = File('lib/screens/home_screen.dart').readAsStringSync();
    rulesAidsSrc =
        File('lib/screens/rules_aids_screen.dart').readAsStringSync();
    deathConfirmSrc =
        File('lib/screens/death_count_confirm_screen.dart').readAsStringSync();
  });

  group('Task 016 — home active character switcher', () {
    test('home shows Playing as control for multi-character switcher', () {
      expect(
        homeSrc.contains('Playing as:'),
        isTrue,
        reason: 'Home must offer "Playing as: {Name} ▾" when 2+ characters.',
      );
    });

    test('home uses ActiveCharacterPreferenceService for persistence', () {
      expect(
        homeSrc.contains('ActiveCharacterPreferenceService') ||
            homeSrc.contains('active_character_preference_service.dart'),
        isTrue,
        reason: 'Home must reconcile/persist active character per tenant.',
      );
    });

    test('switcher visibility helper gates on 2+ characters', () {
      expect(
        homeSrc.contains('showSwitcher') ||
            homeSrc.contains('ActiveCharacterSelection'),
        isTrue,
        reason: 'Home must not show switcher for 0 or 1 character.',
      );
    });
  });

  group('Task 016 — Rules Aids death counter entry gate', () {
    test('Death Counter explains when no active character', () {
      expect(
        rulesAidsSrc.contains('Select or create a character first'),
        isTrue,
        reason:
            'Disabled Death Counter must tell the user they need a character.',
      );
    });

    test('Death Counter path consults active character before navigate', () {
      final consultsActive = rulesAidsSrc.contains('getActiveCharacterId') ||
          rulesAidsSrc.contains('activeCharacterId') ||
          rulesAidsSrc.contains('ActiveCharacterPreferenceService');
      expect(
        consultsActive,
        isTrue,
        reason: 'Rules Aids must gate Death Counter on active character.',
      );
    });

    test('Death Counter tile can be disabled (onTap nullable / enabled)', () {
      // _AidTile already supports enabled: onTap != null; entry must pass null
      // when there is no active character.
      expect(
        rulesAidsSrc.contains('_openDeathCounter'),
        isTrue,
      );
      expect(
        rulesAidsSrc.contains('onTap: null') ||
            rulesAidsSrc.contains('enabled: false') ||
            rulesAidsSrc.contains('Tooltip') ||
            rulesAidsSrc.contains('Select or create a character first'),
        isTrue,
        reason: 'Death Counter must be non-navigating when no character.',
      );
    });
  });

  group('Task 016 — DeathCountConfirmScreen no player character picker', () {
    test('does not present RadioGroup / RadioListTile character picker', () {
      expect(
        deathConfirmSrc.contains('RadioGroup'),
        isFalse,
        reason:
            'Player character selection moved to home; confirm must not list radios.',
      );
      expect(
        deathConfirmSrc.contains('RadioListTile'),
        isFalse,
        reason:
            'Player character selection moved to home; confirm must not list radios.',
      );
    });

    test('playtest gated by canConfigureDeathRules', () {
      expect(
        deathConfirmSrc.contains('canConfigureDeathRules'),
        isTrue,
        reason:
            'Playtest ("Use ID 000") is organizer/admin only '
            '(owner / superAdmin).',
      );
      expect(
        deathConfirmSrc.contains('Use ID 000'),
        isTrue,
        reason: 'Playtest checkbox copy remains for organizers.',
      );
    });

    test('uses active character preference instead of mid-flow selection', () {
      expect(
        deathConfirmSrc.contains('ActiveCharacterPreferenceService') ||
            deathConfirmSrc.contains('getActiveCharacterId'),
        isTrue,
        reason:
            'Confirm screen must start timer for the home-persisted active character.',
      );
    });
  });

  group('Task 016 — playtest role gate contract', () {
    test('canConfigureDeathRules is owner and superAdmin only', () {
      expect(GameRole.owner.canConfigureDeathRules, isTrue);
      expect(GameRole.superAdmin.canConfigureDeathRules, isTrue);
      expect(GameRole.staff.canConfigureDeathRules, isFalse);
      expect(GameRole.player.canConfigureDeathRules, isFalse);
    });
  });
}
