import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/constants/game_constants.dart';
import 'package:rolekeeper/models/location_tracking_rules.dart';
import 'package:rolekeeper/screens/location_tracking_rules_section.dart';
import 'package:rolekeeper/screens/rules_screen.dart';
import 'package:rolekeeper/services/event_session_repository.dart';
import 'package:rolekeeper/services/location_tracking_rules_repository.dart';
import 'package:rolekeeper/services/rules_repository.dart';
import 'package:rolekeeper/services/game_context_service.dart';
import 'package:rolekeeper/utils/error_reporting.dart';
import 'package:rolekeeper/utils/game_firestore_paths.dart';

import '../helpers/game_tenant_test_paths.dart';

Finder enableSwitchFinder() =>
    find.widgetWithText(SwitchListTile, 'Enable location tracking');

class _FakeLocationTrackingRulesRepository
    extends LocationTrackingRulesRepository {
  _FakeLocationTrackingRulesRepository({
    required this.rulesToReturn,
    this.getDelay = Duration.zero,
    this.saveDelay = Duration.zero,
    this.saveError,
  }) : super(firestore: FakeFirebaseFirestore(), tenant: kTestGameTenant);

  LocationTrackingRules rulesToReturn;
  final Duration getDelay;
  final Duration saveDelay;
  final Object? saveError;

  LocationTrackingRules? lastSaved;
  int saveCallCount = 0;

  @override
  Future<LocationTrackingRules> get() async {
    if (getDelay > Duration.zero) {
      await Future<void>.delayed(getDelay);
    }
    return rulesToReturn;
  }

  @override
  Future<void> save(LocationTrackingRules rules) async {
    saveCallCount++;
    if (saveDelay > Duration.zero) {
      await Future<void>.delayed(saveDelay);
    }
    if (saveError != null) throw saveError!;
    lastSaved = rules;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;

  setUp(() async {
    GameContextService.instance.currentTenantForTest = kTestGameTenant;
    firestore = FakeFirebaseFirestore();
    await seedGameTenantDocs(firestore, kTestGameTenant);
  });

  tearDown(GameContextService.instance.resetForTest);

  Future<void> seedLocationRules({
    required bool enabled,
    int pingIntervalSeconds = 60,
  }) async {
    await GameFirestorePaths.locationTrackingRules(firestore, kTestGameTenant)
        .set(LocationTrackingRules(
      enabled: enabled,
      pingIntervalSeconds: pingIntervalSeconds,
    ).toMap());
  }

  Widget wrapSection({
    required LocationTrackingRulesRepository rulesRepo,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: LocationTrackingRulesSection(
          locationRulesRepository: rulesRepo,
        ),
      ),
    );
  }

  group('LocationTrackingRulesSection', () {
    testWidgets('shows loading indicator until rules load; then enable switch',
        (tester) async {
      final rulesRepo = _FakeLocationTrackingRulesRepository(
        rulesToReturn: LocationTrackingRules.defaultRules,
        getDelay: const Duration(milliseconds: 100),
      );

      await tester.pumpWidget(wrapSection(rulesRepo: rulesRepo));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(enableSwitchFinder(), findsNothing);

      await tester.pumpAndSettle();

      expect(find.text('Location tracking'), findsOneWidget);
      expect(enableSwitchFinder(), findsOneWidget);
    });

    testWidgets('switch is off when rules doc is missing', (tester) async {
      final rulesRepo = LocationTrackingRulesRepository(
        firestore: firestore,
        tenant: kTestGameTenant,
      );

      await tester.pumpWidget(wrapSection(rulesRepo: rulesRepo));
      await tester.pumpAndSettle();

      final switchTile = tester.widget<SwitchListTile>(enableSwitchFinder());
      expect(switchTile.value, isFalse);
    });

    testWidgets('switch is off when tracking is disabled in Firestore',
        (tester) async {
      await seedLocationRules(enabled: false, pingIntervalSeconds: 90);

      final rulesRepo = LocationTrackingRulesRepository(
        firestore: firestore,
        tenant: kTestGameTenant,
      );

      await tester.pumpWidget(wrapSection(rulesRepo: rulesRepo));
      await tester.pumpAndSettle();

      final switchTile = tester.widget<SwitchListTile>(enableSwitchFinder());
      expect(switchTile.value, isFalse);
    });

    testWidgets(
        'toggling on saves enabled true and preserves pingIntervalSeconds',
        (tester) async {
      final rulesRepo = _FakeLocationTrackingRulesRepository(
        rulesToReturn: const LocationTrackingRules(
          enabled: false,
          pingIntervalSeconds: 90,
        ),
      );

      await tester.pumpWidget(wrapSection(rulesRepo: rulesRepo));
      await tester.pumpAndSettle();

      await tester.tap(enableSwitchFinder());
      await tester.pumpAndSettle();

      expect(rulesRepo.saveCallCount, 1);
      expect(rulesRepo.lastSaved?.enabled, isTrue);
      expect(rulesRepo.lastSaved?.pingIntervalSeconds, 90);
    });

    testWidgets(
        'toggling off saves enabled false and preserves pingIntervalSeconds',
        (tester) async {
      final rulesRepo = _FakeLocationTrackingRulesRepository(
        rulesToReturn: const LocationTrackingRules(
          enabled: true,
          pingIntervalSeconds: 45,
        ),
      );

      await tester.pumpWidget(wrapSection(rulesRepo: rulesRepo));
      await tester.pumpAndSettle();

      await tester.tap(enableSwitchFinder());
      await tester.pumpAndSettle();

      expect(rulesRepo.saveCallCount, 1);
      expect(rulesRepo.lastSaved?.enabled, isFalse);
      expect(rulesRepo.lastSaved?.pingIntervalSeconds, 45);
    });

    testWidgets('failed save reverts switch and shows user-facing error',
        (tester) async {
      final rulesRepo = _FakeLocationTrackingRulesRepository(
        rulesToReturn: const LocationTrackingRules(
          enabled: false,
          pingIntervalSeconds: 60,
        ),
        saveError: Exception('INTERNAL: raw failure detail'),
      );

      await tester.pumpWidget(wrapSection(rulesRepo: rulesRepo));
      await tester.pumpAndSettle();

      await tester.tap(enableSwitchFinder());
      await tester.pumpAndSettle();

      final switchTile = tester.widget<SwitchListTile>(enableSwitchFinder());
      expect(switchTile.value, isFalse);

      final report = reportAppError(
        'LocationTrackingRulesSection.save',
        Exception('INTERNAL: raw failure detail'),
      );
      expect(
        find.widgetWithText(SnackBar, report.userMessage),
        findsOneWidget,
      );
      expect(find.textContaining('INTERNAL'), findsNothing);
      expect(find.textContaining('Exception:'), findsNothing);
    });

    testWidgets('switch disabled and busy indicator shown while save in flight',
        (tester) async {
      final rulesRepo = _FakeLocationTrackingRulesRepository(
        rulesToReturn: const LocationTrackingRules(
          enabled: false,
          pingIntervalSeconds: 60,
        ),
        saveDelay: const Duration(seconds: 5),
      );

      await tester.pumpWidget(wrapSection(rulesRepo: rulesRepo));
      await tester.pumpAndSettle();

      await tester.tap(enableSwitchFinder());
      await tester.pump();

      final switchTile = tester.widget<SwitchListTile>(enableSwitchFinder());
      expect(switchTile.onChanged, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('shows explanatory copy about voluntary opt-in and live events',
        (tester) async {
      final rulesRepo = _FakeLocationTrackingRulesRepository(
        rulesToReturn: LocationTrackingRules.defaultRules,
      );

      await tester.pumpWidget(wrapSection(rulesRepo: rulesRepo));
      await tester.pumpAndSettle();

      expect(find.textContaining('voluntarily'), findsOneWidget);
      expect(find.textContaining('live'), findsOneWidget);
    });
  });

  group('RulesScreen location tracking section order', () {
    Widget wrapRulesScreen({
      LocationTrackingRulesRepository? locationRulesRepo,
    }) {
      return MaterialApp(
        home: RulesScreen(
          eventSessionRepository: EventSessionRepository(
            firestore: firestore,
            tenant: kTestGameTenant,
          ),
          rulesRepository: RulesRepository(
            firestore: firestore,
            tenant: kTestGameTenant,
          ),
          locationTrackingRulesRepository: locationRulesRepo ??
              LocationTrackingRulesRepository(
                firestore: firestore,
                tenant: kTestGameTenant,
              ),
        ),
      );
    }

    testWidgets('renders Event session, Location tracking, then Death rules',
        (tester) async {
      await tester.pumpWidget(wrapRulesScreen());
      await tester.pumpAndSettle();

      expect(find.text('Event session'), findsOneWidget);
      expect(find.text('Location tracking'), findsOneWidget);
      expect(find.text('Death'), findsOneWidget);

      final eventSessionY = tester.getTopLeft(find.text('Event session')).dy;
      final locationTrackingY =
          tester.getTopLeft(find.text('Location tracking')).dy;
      final deathY = tester.getTopLeft(find.text('Death')).dy;

      expect(eventSessionY, lessThan(locationTrackingY));
      expect(locationTrackingY, lessThan(deathY));
    });

    testWidgets('includes Scavenger hunts navigation entry', (tester) async {
      await tester.pumpWidget(wrapRulesScreen());
      await tester.pumpAndSettle();

      expect(find.text('Scavenger hunts'), findsOneWidget);
    });
  });
}
