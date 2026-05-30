import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rolekeeper/screens/sign_in_screen.dart';
import 'package:rolekeeper/services/auth_service.dart';

void main() {
  group('SignInScreen', () {
    testWidgets('displays RoleKeeper title and Sign in with Google button',
        (WidgetTester tester) async {
      final auth = MockFirebaseAuth(signedIn: false);
      final authService = AuthService(auth: auth, isWeb: true);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6366F1)),
            useMaterial3: true,
          ),
          home: SignInScreen(authService: authService),
        ),
      );

      expect(find.text('RoleKeeper'), findsOneWidget);
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.text('Character & event management for LARPs'), findsOneWidget);
    });
  });
}
