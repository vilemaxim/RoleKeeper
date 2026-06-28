import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rolekeeper/models/location_tracking_rules.dart';
import 'package:rolekeeper/models/member_presence.dart';
import 'package:rolekeeper/services/location_ping_service.dart';
import 'package:rolekeeper/utils/location_utils.dart';

LocationTrackingRules _enabledRules({int interval = 60}) =>
    LocationTrackingRules(enabled: true, pingIntervalSeconds: interval);

const _disabledRules = LocationTrackingRules(
  enabled: false,
  pingIntervalSeconds: 60,
);

MemberPresence _presence({
  bool optedIn = true,
  PresenceState state = PresenceState.inGame,
}) =>
    MemberPresence(
      locationOptIn: optedIn,
      presenceState: state,
    );

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    LocationUtils.debugIsWeb = true;
    LocationUtils.debugWebIsWhenInUseGranted = () async => true;
    LocationUtils.debugWebRequestWhenInUse = () async => true;
    LocationUtils.debugWebGetCurrentPosition = ({
      desiredAccuracy = LocationAccuracy.medium,
      timeLimit = const Duration(seconds: 15),
    }) async => null;
  });

  tearDown(() {
    LocationUtils.debugIsWeb = null;
    LocationUtils.debugWebIsWhenInUseGranted = null;
    LocationUtils.debugWebRequestWhenInUse = null;
    LocationUtils.debugWebGetCurrentPosition = null;
  });

  group('LocationPingService.shouldRun', () {
    test('true when tracking enabled, event live, opted in, permission granted',
        () {
      expect(
        LocationPingService.shouldRun(
          rules: _enabledRules(),
          eventLive: true,
          presence: _presence(),
        ),
        isTrue,
      );
    });

    test('true when player is out_of_game (presence does not gate pinging)', () {
      expect(
        LocationPingService.shouldRun(
          rules: _enabledRules(),
          eventLive: true,
          presence: _presence(state: PresenceState.outOfGame),
        ),
        isTrue,
      );
    });

    test('false when tracking disabled', () {
      expect(
        LocationPingService.shouldRun(
          rules: _disabledRules,
          eventLive: true,
          presence: _presence(),
        ),
        isFalse,
      );
    });

    test('false when event not live', () {
      expect(
        LocationPingService.shouldRun(
          rules: _enabledRules(),
          eventLive: false,
          presence: _presence(),
        ),
        isFalse,
      );
    });

    test('false when player has not opted in', () {
      expect(
        LocationPingService.shouldRun(
          rules: _enabledRules(),
          eventLive: true,
          presence: _presence(optedIn: false),
        ),
        isFalse,
      );
    });

    test('true when opted in even if browser permission not yet granted', () {
      expect(
        LocationPingService.shouldRun(
          rules: _enabledRules(),
          eventLive: true,
          presence: _presence(),
        ),
        isTrue,
      );
    });
  });

  group('LocationPingService lifecycle', () {
    late LocationPingService service;

    setUp(() {
      service = LocationPingService();
    });

    test('start sets isRunning when all conditions met', () async {
      await service.start(
        rules: _enabledRules(interval: 1),
        eventLive: true,
        presence: _presence(),
      );

      expect(service.isRunning, isTrue);
    });

    test('stop clears isRunning', () async {
      await service.start(
        rules: _enabledRules(interval: 1),
        eventLive: true,
        presence: _presence(),
      );

      service.stop();

      expect(service.isRunning, isFalse);
    });

    test('syncConditions stops when event ends', () async {
      await service.start(
        rules: _enabledRules(interval: 1),
        eventLive: true,
        presence: _presence(),
      );

      await service.syncConditions(
        rules: _enabledRules(interval: 1),
        eventLive: false,
        presence: _presence(),
      );

      expect(service.isRunning, isFalse);
    });

    test('syncConditions keeps running when player toggles to out_of_game', () async {
      await service.start(
        rules: _enabledRules(interval: 1),
        eventLive: true,
        presence: _presence(),
      );

      await service.syncConditions(
        rules: _enabledRules(interval: 1),
        eventLive: true,
        presence: _presence(state: PresenceState.outOfGame),
      );

      expect(service.isRunning, isTrue);
    });

    test('syncConditions stops when player opts out', () async {
      await service.start(
        rules: _enabledRules(interval: 1),
        eventLive: true,
        presence: _presence(),
      );

      await service.syncConditions(
        rules: _enabledRules(interval: 1),
        eventLive: true,
        presence: _presence(optedIn: false),
      );

      expect(service.isRunning, isFalse);
    });

    test('dispose stops an active timer', () async {
      await service.start(
        rules: _enabledRules(interval: 1),
        eventLive: true,
        presence: _presence(),
      );

      service.dispose();

      expect(service.isRunning, isFalse);
    });

    test('start prompts for permission when opted in but permission not yet granted',
        () async {
      var prompted = false;
      LocationUtils.debugIsWeb = true;
      LocationUtils.debugWebIsWhenInUseGranted = () async => false;
      LocationUtils.debugWebRequestWhenInUse = () async {
        prompted = true;
        return true;
      };

      await service.start(
        rules: _enabledRules(interval: 1),
        eventLive: true,
        presence: _presence(),
      );

      expect(prompted, isTrue);
      expect(service.isRunning, isTrue);
    });

    test('start does not run timer when user denies permission prompt', () async {
      LocationUtils.debugIsWeb = true;
      LocationUtils.debugWebIsWhenInUseGranted = () async => false;
      LocationUtils.debugWebRequestWhenInUse = () async => false;

      await service.start(
        rules: _enabledRules(interval: 1),
        eventLive: true,
        presence: _presence(),
      );

      expect(service.isRunning, isFalse);
    });

    test('syncConditions prompts and starts when opted in without prior permission',
        () async {
      LocationUtils.debugIsWeb = true;
      LocationUtils.debugWebIsWhenInUseGranted = () async => false;
      LocationUtils.debugWebRequestWhenInUse = () async => true;

      await service.syncConditions(
        rules: _enabledRules(interval: 1),
        eventLive: true,
        presence: _presence(),
      );

      expect(service.isRunning, isTrue);
    });
  });
}
