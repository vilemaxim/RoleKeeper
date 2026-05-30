import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'widgets/app_permissions_wrapper.dart';
import 'widgets/death_timer_global_listener.dart';

/// Root navigator for global overlays (e.g. death dialog off-route).
final GlobalKey<NavigatorState> roleKeeperNavigatorKey =
    GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Web builds (including in mobile browsers) must use web config with authDomain
  // for Firebase Auth popup/redirect. currentPlatform can return android on
  // Chrome/Android, which lacks authDomain.
  final options = kIsWeb
      ? DefaultFirebaseOptions.web
      : DefaultFirebaseOptions.currentPlatform;
  await Firebase.initializeApp(options: options);

  // Optional: Use emulators for local dev. Run with:
  //   flutter run --dart-define=USE_EMULATORS=true
  const useEmulators =
      bool.fromEnvironment('USE_EMULATORS', defaultValue: false);
  if (kDebugMode && useEmulators) {
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  }

  runApp(const RoleKeeperApp());
}

class RoleKeeperApp extends StatelessWidget {
  const RoleKeeperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: roleKeeperNavigatorKey,
      title: 'RoleKeeper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6366F1)),
        useMaterial3: true,
      ),
      builder: (context, child) => DeathTimerGlobalListener(
        navigatorKey: roleKeeperNavigatorKey,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const AppPermissionsWrapper(),
    );
  }
}
