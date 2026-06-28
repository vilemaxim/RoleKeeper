import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/home_assistant_integration.dart';
import '../services/home_assistant_integration_configure_service.dart';
import '../services/home_assistant_integration_repository.dart';
import '../utils/error_reporting.dart';

/// Staff+ setup: enable Home Assistant location reads and manage API keys.
class HomeAssistantIntegrationScreen extends StatefulWidget {
  const HomeAssistantIntegrationScreen({
    super.key,
    this.repository,
  });

  final HomeAssistantIntegrationRepository? repository;

  @override
  State<HomeAssistantIntegrationScreen> createState() =>
      _HomeAssistantIntegrationScreenState();
}

class _HomeAssistantIntegrationScreenState
    extends State<HomeAssistantIntegrationScreen> {
  late final HomeAssistantIntegrationRepository _repo =
      widget.repository ?? HomeAssistantIntegrationRepository();
  late final _configureService = HomeAssistantIntegrationConfigureService();

  bool _loading = true;
  bool _busy = false;
  HomeAssistantIntegrationConfig _config = HomeAssistantIntegrationConfig.empty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final config = await _repo.get();
      if (!mounted) return;
      setState(() {
        _config = config;
        _loading = false;
      });
    } catch (e, st) {
      final report =
          reportAppError('HomeAssistantIntegrationScreen.load', e, st);
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(report.userMessage)),
      );
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() => _busy = true);
    try {
      final key = await _configureService.configure(
        enabled: enabled,
        regenerateKey: enabled && !_config.apiKeyConfigured,
      );
      if (!mounted) return;
      if (key != null) {
        await _showApiKeyOnce(key);
      }
      await _load();
    } catch (e, st) {
      final report =
          reportAppError('HomeAssistantIntegrationScreen.setEnabled', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(report.userMessage)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _regenerateKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Regenerate API key?'),
        content: const Text(
          'The current key will stop working immediately. Update Home Assistant '
          'with the new key after regeneration.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final key = await _configureService.configure(
        enabled: _config.enabled,
        regenerateKey: true,
      );
      if (!mounted) return;
      if (key != null) {
        await _showApiKeyOnce(key);
      }
      await _load();
    } catch (e, st) {
      final report =
          reportAppError('HomeAssistantIntegrationScreen.regenerate', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(report.userMessage)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showApiKeyOnce(String apiKey) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Copy your API key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'This key is shown once. Store it in Home Assistant now — '
              'RoleKeeper cannot display it again.',
            ),
            const SizedBox(height: 16),
            SelectableText(
              apiKey,
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: apiKey));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home Assistant')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Location read API',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Allow Home Assistant to poll latest player positions during '
                  'live events. Players must have location opt-in and recent pings.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.35,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 24),
                SwitchListTile(
                  title: const Text('Enable integration'),
                  subtitle: Text(
                    _config.apiKeyConfigured
                        ? 'API key configured'
                        : 'Generate a key when enabling',
                  ),
                  value: _config.enabled,
                  onChanged: _busy ? null : _setEnabled,
                ),
                if (_config.apiKeyConfigured) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy || !_config.enabled ? null : _regenerateKey,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Regenerate API key'),
                  ),
                ],
              ],
            ),
    );
  }
}
