import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'screens/sign_in_screen.dart';
import 'services/auth_service.dart';
import 'utils/error_reporting.dart';
import 'widgets/signed_in_gate.dart';

/// Routes between sign-in and home based on auth state.
///
/// Keeps a single [AuthService] so [StreamBuilder] subscribes to one stable stream
/// instance (avoids resubscribe / timing issues from recreating the service each build).
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthService _auth = AuthService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _auth.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final report = reportAppError(
            'AuthGate.authState',
            snapshot.error!,
            snapshot.stackTrace,
          );
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(report.userMessage, textAlign: TextAlign.center),
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user != null) {
          return SignedInGate(user: user);
        }
        return const SignInScreen();
      },
    );
  }
}
