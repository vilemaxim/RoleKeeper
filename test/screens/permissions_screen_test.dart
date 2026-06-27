import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/screens/permissions_screen.dart';
import 'package:rolekeeper/utils/startup_permissions_utils.dart';

void main() {
  testWidgets('does not show location as a startup requirement', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PermissionsScreen(
          result: const StartupPermissionsResult(
            locationGranted: false,
            vibrationReady: false,
            locationServiceEnabled: false,
          ),
          onRecheck: () async {},
        ),
      ),
    );

    expect(find.text('Location'), findsNothing);
    expect(find.text('Vibration & haptics'), findsOneWidget);
  });

  testWidgets('shows vibration troubleshooting when haptics unavailable',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PermissionsScreen(
          result: const StartupPermissionsResult(
            locationGranted: true,
            vibrationReady: false,
            locationServiceEnabled: true,
          ),
          onRecheck: () async {},
        ),
      ),
    );

    expect(find.text('Vibration & haptics'), findsOneWidget);
    expect(find.text('Needed'), findsOneWidget);
    expect(find.text('Location'), findsNothing);
  });
}
