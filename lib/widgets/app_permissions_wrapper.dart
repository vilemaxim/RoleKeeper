import 'package:flutter/material.dart';

import '../auth_gate.dart';
import '../screens/permissions_screen.dart';
import '../utils/startup_permissions_utils.dart';

/// Runs [requestStartupPermissions] at startup, then shows [AuthGate] or
/// [PermissionsScreen] with Recheck until vibration/haptics requirements pass.
class AppPermissionsWrapper extends StatefulWidget {
  const AppPermissionsWrapper({super.key});

  @override
  State<AppPermissionsWrapper> createState() => _AppPermissionsWrapperState();
}

class _AppPermissionsWrapperState extends State<AppPermissionsWrapper> {
  bool _loading = true;
  bool _passed = false;
  StartupPermissionsResult? _last;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final r = await requestStartupPermissions();
    if (!mounted) return;
    setState(() {
      _last = r;
      _passed = r.allGranted;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_passed) {
      return AuthGate();
    }
    return PermissionsScreen(
      result: _last!,
      onRecheck: _run,
    );
  }
}
