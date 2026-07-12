// Task 007 — Firebase App Check client bootstrap guards.
//
// Source-level tests for Flutter App Check initialization per ADR 005.
// Implementation phase adds firebase_app_check dependency and main.dart setup.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Task 007 — pubspec declares firebase_app_check', () {
    late final String pubspec;

    setUpAll(() {
      pubspec = File('pubspec.yaml').readAsStringSync();
    });

    test('includes firebase_app_check dependency aligned with other Firebase packages', () {
      expect(
        pubspec.contains('firebase_app_check:'),
        isTrue,
        reason:
            'Add firebase_app_check to pubspec.yaml (match firebase_core major version).',
      );
    });
  });

  group('Task 007 — lib/main.dart activates App Check after Firebase init', () {
    late final String mainSrc;

    setUpAll(() {
      mainSrc = File('lib/main.dart').readAsStringSync();
    });

    test('imports firebase_app_check', () {
      expect(
        mainSrc.contains("import 'package:firebase_app_check/firebase_app_check.dart';"),
        isTrue,
        reason: 'main.dart must import firebase_app_check.',
      );
    });

    test('calls FirebaseAppCheck.instance.activate after Firebase.initializeApp', () {
      final initIndex = mainSrc.indexOf('Firebase.initializeApp');
      expect(initIndex, greaterThan(-1), reason: 'main.dart must initialize Firebase.');

      final activateIndex = mainSrc.indexOf('FirebaseAppCheck.instance.activate');
      expect(
        activateIndex,
        greaterThan(initIndex),
        reason:
            'Activate App Check after Firebase.initializeApp so tokens attach to '
            'Firestore and callable requests.',
      );
    });

    test('uses debug providers in debug mode', () {
      expect(
        mainSrc.contains('AndroidProvider.debug'),
        isTrue,
        reason: 'Debug builds must use AndroidProvider.debug for local dev tokens.',
      );
      expect(
        mainSrc.contains('AppleProvider.debug'),
        isTrue,
        reason: 'Debug builds must use AppleProvider.debug for local dev tokens.',
      );
    });

    test('uses release attestation providers outside debug mode', () {
      expect(
        mainSrc.contains('AndroidProvider.playIntegrity'),
        isTrue,
        reason: 'Release Android builds must use Play Integrity.',
      );
      expect(
        mainSrc.contains('AppleProvider.appAttest'),
        isTrue,
        reason: 'Release iOS builds must use App Attest.',
      );
    });

    test('configures web reCAPTCHA Enterprise provider', () {
      expect(
        mainSrc.contains('ReCaptchaEnterpriseProvider'),
        isTrue,
        reason: 'Web builds need ReCaptchaEnterpriseProvider per ADR 005.',
      );
    });
  });

  group('Task 007 — FIREBASE_SETUP.md documents App Check debug workflow', () {
    late final String setupDoc;

    setUpAll(() {
      setupDoc = File('FIREBASE_SETUP.md').readAsStringSync();
    });

    test('documents App Check setup section', () {
      expect(
        setupDoc.toLowerCase().contains('app check'),
        isTrue,
        reason: 'FIREBASE_SETUP.md must document App Check registration and debug tokens.',
      );
    });

    test('documents debug token registration for local development', () {
      expect(
        setupDoc.toLowerCase().contains('debug token'),
        isTrue,
        reason:
            'Local dev and CI need documented debug token registration in Firebase Console.',
      );
    });

    test('documents emulator or CI bypass expectations', () {
      final mentionsEmulator =
          setupDoc.toLowerCase().contains('emulator') ||
          setupDoc.toLowerCase().contains('ci');
      expect(
        mentionsEmulator,
        isTrue,
        reason:
            'Document that emulators/CI can use App Check debug provider without '
            'breaking scripts/test.sh.',
      );
    });
  });
}
