import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Options for customizing the QR scanner presentation.
class QrScannerOptions {
  const QrScannerOptions({
    this.instructionText = 'Scan a QR code',
    this.title = 'Scan QR',
    this.validate,
  });

  /// Text shown above the camera to guide the user.
  final String instructionText;

  /// App bar title.
  final String title;

  /// Optional validator. If provided, only results passing this test complete the scan.
  /// Return true to accept and return; false to ignore and keep scanning.
  final bool Function(String rawValue)? validate;
}

/// Presents a full-screen QR scanner, then returns the scanned value to the caller.
///
/// Returns the first successfully scanned string, or null if the user cancelled
/// (e.g. back button) or the scanner failed (e.g. permissions).
///
/// Example:
/// ```dart
/// final result = await scanQrCode(context, QrScannerOptions(
///   instructionText: 'Scan the QR on the fallen player\'s screen',
/// ));
/// if (result != null) {
///   // Handle result
/// }
/// ```
Future<String?> scanQrCode(
  BuildContext context, {
  QrScannerOptions options = const QrScannerOptions(),
}) async {
  final value = await Navigator.push<String>(
    context,
    MaterialPageRoute(
      builder: (context) => _QrScannerScreen(options: options),
      fullscreenDialog: true,
    ),
  );
  return value;
}

class _QrScannerScreen extends StatefulWidget {
  const _QrScannerScreen({required this.options});

  final QrScannerOptions options;

  @override
  State<_QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<_QrScannerScreen> {
  late final MobileScannerController _controller;
  String? _error;
  bool _hasScanned = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final raw = barcodes.first.rawValue?.trim();
    if (raw == null || raw.isEmpty) return;

    if (widget.options.validate != null &&
        !widget.options.validate!(raw)) {
      return;
    }

    _hasScanned = true;
    Navigator.pop(context, raw);
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (mounted) {
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.options.title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Cancel',
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            onDetectError: _onError,
            errorBuilder: (context, error, child) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.camera_alt_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Camera unavailable',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      error.errorDetails?.message ?? error.toString(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.options.instructionText,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
