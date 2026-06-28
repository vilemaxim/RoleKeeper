import 'package:flutter/material.dart';

import '../services/member_presence_repository.dart';
import '../utils/error_reporting.dart';

/// Non-modal card prompting the player to opt in to location sharing during a live event.
class LocationOptInPrompt extends StatefulWidget {
  const LocationOptInPrompt({
    super.key,
    required this.presenceRepository,
    required this.onOptInEnabled,
    required this.visible,
    this.onDismiss,
  });

  final MemberPresenceRepository presenceRepository;
  final VoidCallback onOptInEnabled;
  final bool visible;
  final VoidCallback? onDismiss;

  @override
  State<LocationOptInPrompt> createState() => _LocationOptInPromptState();
}

class _LocationOptInPromptState extends State<LocationOptInPrompt> {
  bool _sessionDismissed = false;
  bool _enabling = false;

  Future<void> _onEnable() async {
    if (_enabling) return;
    setState(() => _enabling = true);
    try {
      await widget.presenceRepository.setLocationOptIn(true);
      widget.onOptInEnabled();
    } catch (e, st) {
      final report = reportAppError('LocationOptInPrompt.enable', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(report.userMessage)),
      );
    } finally {
      if (mounted) setState(() => _enabling = false);
    }
  }

  void _onNotNow() {
    setState(() => _sessionDismissed = true);
    widget.onDismiss?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible || _sessionDismissed) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on_outlined, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Share your location during the event',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Your organizer has enabled location tracking for this live event. '
              'Sharing your position is voluntary and helps with safety, anti-cheat, '
              'and in-game features.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _enabling ? null : _onEnable,
                child: _enabling
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enable location sharing'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _enabling ? null : _onNotNow,
                child: const Text('Not now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
