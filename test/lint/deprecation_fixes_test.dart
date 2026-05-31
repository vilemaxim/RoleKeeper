// Source-level guards for Task 001 (Flutter deprecation/lint cleanup).
//
// Each test asserts a property of the source tree that flutter_lints
// verifies via `flutter analyze`, but expressed as a unit test so the
// fix is enforced even if someone re-introduces the suppression in
// `analysis_options.yaml`.
//
// These tests intentionally read project files via relative paths;
// `flutter test` runs with the project root as the working directory.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Task 001 — analysis_options.yaml does not silence the fixes', () {
    late final String analysisOptions;

    setUpAll(() {
      analysisOptions = File('analysis_options.yaml').readAsStringSync();
    });

    test('does not suppress deprecated_member_use', () {
      expect(
        analysisOptions.contains('deprecated_member_use: ignore'),
        isFalse,
        reason:
            'Suppression hides the RadioGroup/onChanged deprecations the task '
            'must fix. Remove the line from analyzer.errors.',
      );
    });

    test('does not suppress deprecated_member_use_from_same_package', () {
      expect(
        analysisOptions.contains('deprecated_member_use_from_same_package: ignore'),
        isFalse,
        reason:
            'Suppression hides the setActiveGameId deprecation the task must '
            'fix. Remove the line from analyzer.errors.',
      );
    });

    test('does not suppress unnecessary_underscores', () {
      expect(
        analysisOptions.contains('unnecessary_underscores: ignore'),
        isFalse,
        reason:
            'Suppression hides the multi-underscore wildcard warnings. '
            'Remove the line from analyzer.errors.',
      );
    });
  });

  group('Task 001 — death_count_confirm_screen.dart RadioGroup migration', () {
    late final String src;

    setUpAll(() {
      src = File('lib/screens/death_count_confirm_screen.dart').readAsStringSync();
    });

    test('uses RadioGroup ancestor instead of per-tile groupValue/onChanged', () {
      expect(
        src.contains('RadioGroup'),
        isTrue,
        reason:
            'death_count_confirm_screen.dart must wrap its RadioListTiles in '
            'a RadioGroup<Character> per the post-3.32 Material API.',
      );
    });

    test('RadioListTile no longer passes groupValue', () {
      // Match `RadioListTile<...>(` and any args up to the closing `)`,
      // then assert no `groupValue:` keyword appears inside that span.
      final radioTilePattern = RegExp(
        r'RadioListTile<[^>]*>\([^)]*groupValue:',
        dotAll: true,
      );
      expect(
        radioTilePattern.hasMatch(src),
        isFalse,
        reason:
            'After RadioGroup migration, RadioListTile must not declare '
            'groupValue: directly.',
      );
    });

    test('RadioListTile no longer passes onChanged', () {
      final radioTilePattern = RegExp(
        r'RadioListTile<[^>]*>\([^)]*onChanged:',
        dotAll: true,
      );
      expect(
        radioTilePattern.hasMatch(src),
        isFalse,
        reason:
            'After RadioGroup migration, RadioListTile must not declare '
            'onChanged: directly.',
      );
    });
  });

  group('Task 001 — larp_picker_screen.dart uses setActiveTenantKey', () {
    late final String src;

    setUpAll(() {
      src = File('lib/screens/larp_picker_screen.dart').readAsStringSync();
    });

    test('does not call deprecated setActiveGameId', () {
      expect(
        src.contains('setActiveGameId('),
        isFalse,
        reason:
            'Replace the deprecated setActiveGameId call with '
            'setActiveTenantKey on UserProfileService.',
      );
    });

    test('calls setActiveTenantKey', () {
      expect(
        src.contains('setActiveTenantKey('),
        isTrue,
        reason:
            'larp_picker_screen.dart must invoke the renamed '
            'setActiveTenantKey method.',
      );
    });
  });

  group('Task 001 — sign_in_screen.dart wildcard parameters', () {
    late final String src;

    setUpAll(() {
      src = File('lib/screens/sign_in_screen.dart').readAsStringSync();
    });

    test('does not use multi-underscore wildcard tuples', () {
      expect(
        src.contains('(_, __, ___)'),
        isFalse,
        reason:
            'Per unnecessary_underscores, ignored positional parameters '
            'should each be a single underscore (Dart 3.7+ wildcards).',
      );
    });
  });
}
