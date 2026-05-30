import 'package:flutter/material.dart';

import '../services/larp_manager_integration_status_service.dart';

/// Blocks the app until LarpManager server sync is configured and working.
class LmIntegrationSetupPrompt extends StatelessWidget {
  const LmIntegrationSetupPrompt({
    super.key,
    required this.readiness,
    required this.onOpenIntegration,
    this.errorDetail,
  });

  final LmIntegrationReadiness readiness;
  final VoidCallback onOpenIntegration;
  final String? errorDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final title = readiness == LmIntegrationReadiness.notOperational
        ? 'Fix LarpManager integration'
        : 'Set up LarpManager sync';

    final body = readiness == LmIntegrationReadiness.notOperational
        ? 'RoleKeeper has connection details for this event, but the server could not '
            'sync with LarpManager yet (often Secret Manager permissions or LM login). '
            'Open LM Integration to update credentials, or fix Cloud setup per FIREBASE_SETUP.md.'
        : 'RoleKeeper needs a dedicated LarpManager login for this event (one-time setup). '
            'That account must sign up and register on LarpManager first, then you grant '
            'it export permissions — see LM Integration for steps.';

    return Card(
      color: scheme.tertiaryContainer.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.integration_instructions_outlined,
                  color: scheme.tertiary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (errorDetail != null && errorDetail!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                errorDetail!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onOpenIntegration,
                icon: const Icon(Icons.settings),
                label: const Text('Open LM Integration'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
