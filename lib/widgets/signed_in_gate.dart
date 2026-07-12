import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/home_screen.dart';
import '../screens/larp_picker_screen.dart';
import '../services/game_context_service.dart';
import '../services/user_profile_service.dart';
import '../utils/error_reporting.dart';

class _SignedInRoute {
  const _SignedInRoute({required this.showPicker});
  final bool showPicker;
}

/// After sign-in, loads profile to decide between the LARP directory and home.
class SignedInGate extends StatefulWidget {
  const SignedInGate({super.key, required this.user});

  final User user;

  @override
  State<SignedInGate> createState() => _SignedInGateState();
}

class _SignedInGateState extends State<SignedInGate> {
  late Future<_SignedInRoute> _routeFuture;

  @override
  void initState() {
    super.initState();
    _routeFuture = _resolveRoute();
  }

  Future<_SignedInRoute> _resolveRoute() async {
    final profile = UserProfileService();
    var showPicker = await profile.shouldShowLarpPicker();
    if (!showPicker) {
      await profile.restoreActiveGameContext();
      if (!GameContextService.instance.hasSelectedGame) {
        showPicker = true;
      }
    }
    return _SignedInRoute(showPicker: showPicker);
  }

  void _reloadAfterError() {
    setState(() {
      _routeFuture = _resolveRoute();
    });
  }

  void _onFirstRunLarpChosen() {
    setState(() {
      _routeFuture = Future.value(_SignedInRoute(showPicker: false));
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SignedInRoute>(
      future: _routeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          final report = reportAppError(
            'SignedInGate.route',
            snapshot.error!,
            snapshot.stackTrace,
          );
          return Scaffold(
            appBar: AppBar(title: const Text('RoleKeeper')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      report.userMessage,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _reloadAfterError,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final route = snapshot.data!;
        if (route.showPicker) {
          return LarpPickerScreen(
            user: widget.user,
            onFirstRunLarpChosen: _onFirstRunLarpChosen,
          );
        }

        return HomeScreen(user: widget.user);
      },
    );
  }
}
