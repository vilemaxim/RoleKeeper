// Task 017 — Eager death secrets prefetch + QR hard-fail + logging.
//
// Source-level guards pin bootstrap/preflight contracts; unit tests cover
// warm-cache offline QR production. `flutter test` runs with project root cwd.

import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/services/death_intervention_secrets_service.dart';
import 'package:rolekeeper/services/game_context_service.dart';
import 'package:rolekeeper/utils/death_qr_parser.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class MockHttpsCallable extends Mock implements HttpsCallable {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late final String homeSrc;
  late final String deathTimerSrc;
  late final String deathConfirmSrc;
  late final String activityEventSrc;
  late final String activeEventsUtilsSrc;
  late final String activityEventsServiceSrc;
  late final String functionsIndexSrc;
  late final String adr003Src;

  setUpAll(() {
    homeSrc = File('lib/screens/home_screen.dart').readAsStringSync();
    deathTimerSrc =
        File('lib/screens/death_timer_screen.dart').readAsStringSync();
    deathConfirmSrc =
        File('lib/screens/death_count_confirm_screen.dart').readAsStringSync();
    activityEventSrc =
        File('lib/models/activity_event.dart').readAsStringSync();
    activeEventsUtilsSrc =
        File('lib/utils/active_events_utils.dart').readAsStringSync();
    activityEventsServiceSrc =
        File('lib/services/activity_events_service.dart').readAsStringSync();
    functionsIndexSrc = File('functions/src/index.ts').readAsStringSync();
    adr003Src =
        File('docs/adr/003-death-intervention-signing.md').readAsStringSync();
  });

  tearDown(GameContextService.instance.resetForTest);

  group('Task 017 — eager secret prefetch on LARP/home bootstrap', () {
    test('home bootstrap prefetches death intervention secrets', () {
      final prefetches = homeSrc.contains('fetchAndCacheSecrets') ||
          (homeSrc.contains('DeathInterventionSecretsService') &&
              (homeSrc.contains('resolveSecrets') ||
                  homeSrc.contains('prefetch')));
      expect(
        prefetches,
        isTrue,
        reason:
            'Home/_bootstrap must call DeathInterventionSecretsService '
            '(fetchAndCacheSecrets or online-preferring resolve) so secrets '
            'are cached before death timer need.',
      );
    });

    test('prefetch failure surfaces via reportAppError', () {
      expect(
        homeSrc.contains('DeathInterventionSecretsService') ||
            homeSrc.contains('fetchAndCacheSecrets'),
        isTrue,
        reason: 'Prefetch wiring must exist on home before error reporting.',
      );
      final reportsPrefetch = homeSrc.contains('deathSecret') ||
          homeSrc.contains('DeathSecret') ||
          homeSrc.contains('deathIntervention') ||
          homeSrc.contains('HomeScreen.death') ||
          homeSrc.contains('prefetchDeath') ||
          homeSrc.contains('fetchAndCacheSecrets');
      expect(
        reportsPrefetch && homeSrc.contains('reportAppError'),
        isTrue,
        reason:
            'Online prefetch failure must call reportAppError so the player '
            'sees a clear SnackBar/banner.',
      );
    });
  });

  group('Task 017 — deathTimerQrUnavailable event type + allow-list', () {
    test('ActiveGameEventType includes deathTimerQrUnavailable', () {
      expect(
        activityEventSrc.contains('deathTimerQrUnavailable'),
        isTrue,
        reason:
            'New master-log type required when medic QR cannot be produced.',
      );
    });

    test('ActiveEventsUtils records deathTimerQrUnavailable', () {
      expect(
        activeEventsUtilsSrc.contains('deathTimerQrUnavailable') ||
            activeEventsUtilsSrc.contains('DeathTimerQrUnavailable'),
        isTrue,
        reason:
            'Master log path must invoke createActiveGameEvent with the new type.',
      );
    });

    test('ActivityEventsService exposes QR-unavailable recording', () {
      expect(
        activityEventsServiceSrc.contains('deathTimerQrUnavailable') ||
            activityEventsServiceSrc.contains('DeathTimerQrUnavailable') ||
            activityEventsServiceSrc.contains('recordDeathTimerQr'),
        isTrue,
        reason:
            'Client service must record QR-unavailable to master + mirrors.',
      );
    });

    test('createActiveGameEvent allow-list includes deathTimerQrUnavailable',
        () {
      expect(
        functionsIndexSrc.contains('deathTimerQrUnavailable'),
        isTrue,
        reason:
            'Cloud Function allow-list must accept the new active event type.',
      );
    });
  });

  group('Task 017 — death timer QR hard-fail on new start', () {
    test('new start hard-fails when signing secret unavailable', () {
      final startPath = '$deathTimerSrc\n$deathConfirmSrc';
      final hasHardFail = startPath.contains('deathTimerQrUnavailable') ||
          startPath.contains('DeathTimerQrUnavailable') ||
          startPath.contains('recordDeathTimerQr') ||
          startPath.contains('qrUnavailable') ||
          startPath.contains('QrUnavailable');
      expect(
        hasHardFail,
        isTrue,
        reason:
            'Death start preflight must hard-fail and log '
            'deathTimerQrUnavailable when signing secret is missing.',
      );
    });

    test('death confirm preflights signing secret before navigating', () {
      // Prefer preflight at the confirm screen so players never land on an
      // active countdown that immediately aborts.
      final preflights = deathConfirmSrc.contains('DeathInterventionSecrets') ||
          deathConfirmSrc.contains('getCachedSecrets') ||
          deathConfirmSrc.contains('qrSigningSecret') ||
          deathConfirmSrc.contains('deathTimerQrUnavailable') ||
          deathConfirmSrc.contains('recordDeathTimerQr');
      expect(
        preflights,
        isTrue,
        reason:
            'DeathCountConfirmScreen must check cached signing secret '
            '(and hard-fail / log) before opening DeathTimerScreen.',
      );
    });

    test('hard-fail path uses reportAppError', () {
      final startPath = '$deathTimerSrc\n$deathConfirmSrc';
      // Must tie reportAppError to the QR-unavailable hard-fail, not unrelated
      // load errors or soft "Connect online" copy.
      final reportsHardFail = startPath.contains('reportAppError') &&
          (startPath.contains('deathTimerQrUnavailable') ||
              startPath.contains('DeathTimerQrUnavailable') ||
              startPath.contains('recordDeathTimerQr') ||
              startPath.contains('QrUnavailable'));
      expect(
        reportsHardFail,
        isTrue,
        reason:
            'QR hard-fail must reportAppError (terminal) with a user-facing message.',
      );
    });

    test(
        'soft Connect-online placeholder is not the substitute for a new start',
        () {
      // Soft message may remain for resume-of-already-active timer, but a new
      // start with intervention enabled must not setActive then show placeholder.
      final softForNewStart =
          deathTimerSrc.contains('Connect online once to enable medic QR') &&
              deathTimerSrc.contains('setActive') &&
              !deathTimerSrc.contains('deathTimerQrUnavailable') &&
              !deathTimerSrc.contains('DeathTimerQrUnavailable') &&
              !deathConfirmSrc.contains('deathTimerQrUnavailable') &&
              !deathConfirmSrc.contains('DeathTimerQrUnavailable');
      expect(
        softForNewStart,
        isFalse,
        reason:
            'Do not start a timer and show "Connect online once…" as the '
            'medic QR substitute for a new start when intervention is enabled.',
      );
    });
  });

  group('Task 017 — offline signed medic QR with warm cache', () {
    late MockFlutterSecureStorage secureStorage;
    late FakeFirebaseFirestore firestore;
    late MockFirebaseFunctions functions;

    DeathInterventionSecretsService makeSvc() => DeathInterventionSecretsService(
          secureStorage: secureStorage,
          firestore: firestore,
          functions: functions,
          tenant: kTestGameTenant,
        );

    setUp(() {
      secureStorage = MockFlutterSecureStorage();
      firestore = FakeFirebaseFirestore();
      functions = MockFirebaseFunctions();
      GameContextService.instance.currentTenantForTest = kTestGameTenant;
    });

    test(
        'warm cache yields signed medic QR without calling network',
        () async {
      const secrets = DeathInterventionSecrets(
        totpSecret: 'JBSWY3DPEHPK3PXP',
        qrSigningSecret: 'warm-cache-signing-secret',
      );
      when(
        () => secureStorage.read(
          key: DeathInterventionSecretsService.storageKeyForTenant(
            kTestGameTenant.tenantKey,
          ),
        ),
      ).thenAnswer((_) async => jsonEncode(secrets.toJson()));

      final cached = await makeSvc().getCachedSecrets();
      expect(cached?.qrSigningSecret, secrets.qrSigningSecret);

      final raw = buildDeathMedicQrPayload(
        shortId: 'A1B',
        fallenPlayerId: 'player-1',
        activityEventId: 'evt-offline',
        signingSecret: cached!.qrSigningSecret,
      );
      expect(
        verifyDeathInterventionQr(
          raw,
          signingSecret: secrets.qrSigningSecret,
        ),
        isTrue,
      );
      verifyNever(() => functions.httpsCallable(any()));
    });

    test(
        'resolveSecrets returns warm cache without callable when already cached',
        () async {
      const secrets = DeathInterventionSecrets(
        totpSecret: 'JBSWY3DPEHPK3PXP',
        qrSigningSecret: 'cached-signing-secret',
      );
      when(
        () => secureStorage.read(
          key: DeathInterventionSecretsService.storageKeyForTenant(
            kTestGameTenant.tenantKey,
          ),
        ),
      ).thenAnswer((_) async => jsonEncode(secrets.toJson()));

      final resolved = await makeSvc().resolveSecrets();
      expect(resolved?.qrSigningSecret, 'cached-signing-secret');
      verifyNever(() => functions.httpsCallable(any()));
    });
  });

  group('Task 017 — ADR 003 eager prefetch', () {
    test('ADR documents eager prefetch on LARP/home load', () {
      expect(
        adr003Src.toLowerCase().contains('eager'),
        isTrue,
        reason: 'ADR 003 must require eager secret distribution.',
      );
      expect(
        adr003Src.contains('bootstrap') ||
            adr003Src.contains('home load') ||
            adr003Src.contains('LARP/home'),
        isTrue,
        reason:
            'ADR 003 must place prefetch on LARP/home load, not fetch-at-need.',
      );
    });
  });
}
