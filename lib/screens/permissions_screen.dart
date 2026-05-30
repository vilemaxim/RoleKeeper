import 'package:flutter/material.dart';

import '../utils/location_utils.dart';
import '../utils/startup_permissions_utils.dart';

/// Shown when [StartupPermissionsResult.allGranted] is false after startup or recheck.
class PermissionsScreen extends StatelessWidget {
  const PermissionsScreen({
    super.key,
    required this.result,
    required this.onRecheck,
  });

  final StartupPermissionsResult result;
  final Future<void> Function() onRecheck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locOk = result.locationGranted;
    final vibOk = result.vibrationReady;
    final gpsOn = result.locationServiceEnabled;

    return Scaffold(
      appBar: AppBar(title: const Text('Permissions')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'RoleKeeper needs the following so in-game features can work correctly.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            _StatusCard(
              title: 'Location',
              granted: locOk,
              children: [
                if (!gpsOn)
                  Text(
                    'Location services appear to be off. Turn on GPS/location for this device, then tap Recheck.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                if (gpsOn && !locOk)
                  Text(
                    'Location access was not granted. You can open system settings for RoleKeeper and allow location, then tap Recheck.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => LocationUtils.openLocationAppSettings(),
                  icon: const Icon(Icons.settings),
                  label: const Text('Open location settings'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _StatusCard(
              title: 'Vibration & haptics',
              granted: vibOk,
              children: [
                if (!vibOk)
                  Text(
                    'This device does not report a vibration motor. Alerts may be limited.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => onRecheck(),
              icon: const Icon(Icons.refresh),
              label: const Text('Recheck'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.granted,
    required this.children,
  });

  final String title;
  final bool granted;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  granted ? Icons.check_circle : Icons.cancel,
                  color: granted
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  granted ? 'OK' : 'Needed',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: granted
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                ),
              ],
            ),
            if (children.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...children,
            ],
          ],
        ),
      ),
    );
  }
}
