import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rolekeeper/models/game_tenant_ref.dart';
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

const _testTenant = GameTenantRef(
  instanceId: 'test.example.com',
  eventSlug: 'evt',
);

const _baseLat = 37.7749;
const _baseLng = -122.4194;

/// Approximate latitude delta for [meters] north at [_baseLat].
double _latOffsetMeters(double meters) => meters / 111320.0;

Position _position(
  double lat,
  double lng, {
  double accuracy = 10,
}) =>
    Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.utc(2026, 6, 28),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void _mockFixedPosition(double lat, double lng, {double accuracy = 10}) {
  LocationUtils.debugWebGetCurrentPosition = ({
    desiredAccuracy = LocationAccuracy.medium,
    timeLimit = const Duration(seconds: 15),
  }) =>
      Future.value(_position(lat, lng, accuracy: accuracy));
}

/// Flushes [start]/[syncConditions] futures and in-flight ping work under fake time.
void _pumpServiceStart(FakeAsync async, Future<void> startFuture) {
  async.elapse(Duration.zero);
  var done = false;
  startFuture.then((_) => done = true);
  while (!done) {
    async.elapse(Duration.zero);
  }
}

/// Drains microtasks scheduled by async ping work after a timer elapse.
void _drainAsync(FakeAsync async) {
  for (var i = 0; i < 100; i++) {
    async.flushMicrotasks();
  }
}

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

  group('LocationPingService movement threshold', () {
    test('first ping after start always sends', () {
      fakeAsync((async) {
        var pingCount = 0;
        final service = LocationPingService(tenant: _testTenant);
        service.debugSendPing = ({required tenant, required location, characterId}) {
          pingCount++;
          return Future<void>.value();
        };
        _mockFixedPosition(_baseLat, _baseLng);

        _pumpServiceStart(
          async,
          service.start(
            rules: _enabledRules(interval: 60),
            eventLive: true,
            presence: _presence(),
          ),
        );

        expect(pingCount, 1);
      });
    });

    test('stationary player does not ping on every timer tick', () {
      fakeAsync((async) {
        var pingCount = 0;
        final service = LocationPingService(tenant: _testTenant);
        service.debugSendPing = ({required tenant, required location, characterId}) {
          pingCount++;
          return Future<void>.value();
        };
        _mockFixedPosition(_baseLat, _baseLng);

        _pumpServiceStart(
          async,
          service.start(
            rules: _enabledRules(interval: 10),
            eventLive: true,
            presence: _presence(),
          ),
        );

        async.elapse(const Duration(minutes: 4));
        _drainAsync(async);

        expect(pingCount, 1);
      });
    });

    test('moving player sends when movement exceeds threshold', () {
      fakeAsync((async) {
        var pingCount = 0;
        var lat = _baseLat;
        final service = LocationPingService(tenant: _testTenant);
        service.debugSendPing = ({required tenant, required location, characterId}) {
          pingCount++;
          return Future<void>.value();
        };
        LocationUtils.debugWebGetCurrentPosition = ({
          desiredAccuracy = LocationAccuracy.medium,
          timeLimit = const Duration(seconds: 15),
        }) =>
            Future.value(_position(lat, _baseLng));

        _pumpServiceStart(
          async,
          service.start(
            rules: _enabledRules(interval: 10),
            eventLive: true,
            presence: _presence(),
          ),
        );
        expect(pingCount, 1);

        async.elapse(const Duration(seconds: 10));
        _drainAsync(async);
        expect(pingCount, 1, reason: 'no ping while stationary between moves');

        lat = _baseLat + _latOffsetMeters(15);
        async.elapse(const Duration(seconds: 10));
        _drainAsync(async);

        expect(pingCount, 2);
      });
    });

    test('syncConditions sends ping when presence changes while tracking active',
        () {
      fakeAsync((async) {
        var pingCount = 0;
        final service = LocationPingService(tenant: _testTenant);
        service.debugSendPing = ({required tenant, required location, characterId}) {
          pingCount++;
          return Future<void>.value();
        };
        _mockFixedPosition(_baseLat, _baseLng);

        _pumpServiceStart(
          async,
          service.start(
            rules: _enabledRules(interval: 10),
            eventLive: true,
            presence: _presence(),
          ),
        );
        expect(pingCount, 1);

        _pumpServiceStart(
          async,
          service.syncConditions(
            rules: _enabledRules(interval: 10),
            eventLive: true,
            presence: _presence(state: PresenceState.outOfGame),
          ),
        );
        _drainAsync(async);

        expect(pingCount, 2);
      });
    });
  });

  group('LocationPingService.shouldSendPing', () {
    final sentAt = DateTime.utc(2026, 6, 28, 12);

    test('sends when no prior ping recorded', () {
      expect(
        LocationPingService.shouldSendPing(
          latitude: _baseLat,
          longitude: _baseLng,
          accuracy: 10,
          lastSentLat: null,
          lastSentLng: null,
          lastSentAccuracy: null,
          lastSentAt: null,
          now: sentAt,
          force: false,
        ),
        isTrue,
      );
    });

    test('skips when stationary within heartbeat window', () {
      expect(
        LocationPingService.shouldSendPing(
          latitude: _baseLat,
          longitude: _baseLng,
          accuracy: 10,
          lastSentLat: _baseLat,
          lastSentLng: _baseLng,
          lastSentAccuracy: 10,
          lastSentAt: sentAt,
          now: sentAt.add(const Duration(minutes: 4)),
          force: false,
        ),
        isFalse,
      );
    });

    test('sends heartbeat when interval elapsed even if stationary', () {
      expect(
        LocationPingService.shouldSendPing(
          latitude: _baseLat,
          longitude: _baseLng,
          accuracy: 10,
          lastSentLat: _baseLat,
          lastSentLng: _baseLng,
          lastSentAccuracy: 10,
          lastSentAt: sentAt,
          now: sentAt.add(
            const Duration(seconds: LocationPingService.heartbeatIntervalSeconds),
          ),
          force: false,
        ),
        isTrue,
      );
    });

    test('sends when movement exceeds threshold', () {
      expect(
        LocationPingService.shouldSendPing(
          latitude: _baseLat + _latOffsetMeters(15),
          longitude: _baseLng,
          accuracy: 10,
          lastSentLat: _baseLat,
          lastSentLng: _baseLng,
          lastSentAccuracy: 10,
          lastSentAt: sentAt,
          now: sentAt.add(const Duration(minutes: 1)),
          force: false,
        ),
        isTrue,
      );
    });

    test('sends when forced', () {
      expect(
        LocationPingService.shouldSendPing(
          latitude: _baseLat,
          longitude: _baseLng,
          accuracy: 10,
          lastSentLat: _baseLat,
          lastSentLng: _baseLng,
          lastSentAccuracy: 10,
          lastSentAt: sentAt,
          now: sentAt.add(const Duration(seconds: 30)),
          force: true,
        ),
        isTrue,
      );
    });
  });
}
