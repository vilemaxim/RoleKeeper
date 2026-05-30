import 'package:flutter/material.dart';

import '../screens/larp_manager_integration_screen.dart';
import '../services/larp_manager_integration_status_service.dart';
import '../utils/error_reporting.dart';
import 'lm_integration_setup_prompt.dart';

/// Wraps [child] and shows only LM Integration setup until sync works.
class LmIntegrationGate extends StatefulWidget {
  const LmIntegrationGate({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  State<LmIntegrationGate> createState() => _LmIntegrationGateState();
}

class _LmIntegrationGateState extends State<LmIntegrationGate> {
  final _statusService = LarpManagerIntegrationStatusService();
  LmIntegrationEvaluation? _evaluation;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _evaluate();
  }

  Future<void> _evaluate({bool forceSync = false}) async {
    setState(() => _loading = true);
    final evaluation =
        await _statusService.evaluate(forceSync: forceSync);
    if (!mounted) return;
    setState(() {
      _evaluation = evaluation;
      _loading = false;
    });
  }

  Future<void> _openIntegration() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (context) => const LarpManagerIntegrationScreen(),
      ),
    );
    await _evaluate(forceSync: true);
  }

  String? get _errorDetail {
    final err = _evaluation?.lastError;
    if (err == null) return null;
    return reportAppError('LmIntegrationGate', err).userMessage;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final evaluation = _evaluation!;
    if (evaluation.isReady) {
      return widget.child;
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: LmIntegrationSetupPrompt(
            readiness: evaluation.readiness,
            onOpenIntegration: _openIntegration,
            errorDetail: _errorDetail,
          ),
        ),
      ),
    );
  }
}
