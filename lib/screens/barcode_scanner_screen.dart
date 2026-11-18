import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/app_strings.dart';

class ScanBatchFeedback {
  const ScanBatchFeedback({
    required this.found,
    required this.message,
  });

  final bool found;
  final String message;
}

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({
    super.key,
    required this.strings,
    this.onContinuousScan,
  });

  final AppStrings strings;
  final ScanBatchFeedback Function(String code)? onContinuousScan;

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  late final MobileScannerController _scannerController;
  final TextEditingController _manualController = TextEditingController();
  bool _handled = false;
  String? _lastCode;
  DateTime? _lastScanAt;
  ScanBatchFeedback? _lastFeedback;
  int _scanCount = 0;

  bool get _isContinuous => widget.onContinuousScan != null;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed:
          _isContinuous ? DetectionSpeed.normal : DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _playFeedback(bool success) async {
    try {
      await SystemSound.play(SystemSoundType.click);
      if (success) {
        await HapticFeedback.mediumImpact();
      } else {
        await HapticFeedback.heavyImpact();
      }
    } catch (_) {}
  }

  void _handleCode(String raw, {bool fromManual = false}) {
    final code = raw.trim();
    if (code.isEmpty) return;

    if (!_isContinuous) {
      if (_handled) return;
      _handled = true;
      Navigator.of(context).pop(code);
      return;
    }

    final now = DateTime.now();
    if (!fromManual &&
        _lastCode == code &&
        _lastScanAt != null &&
        now.difference(_lastScanAt!) < const Duration(milliseconds: 1500)) {
      return;
    }

    _lastCode = code;
    _lastScanAt = now;

    final feedback = widget.onContinuousScan!(code);
    _playFeedback(feedback.found);
    if (fromManual) {
      _manualController.clear();
    }
    setState(() {
      _lastFeedback = feedback;
      if (feedback.found) {
        _scanCount += 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.scanBarcodeTitle),
        actions: [
          IconButton(
            onPressed: () => _scannerController.toggleTorch(),
            icon: const Icon(Icons.flash_on_outlined),
          ),
          IconButton(
            onPressed: () => _scannerController.switchCamera(),
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
          if (_isContinuous)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.doneAction),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _scannerController,
                  errorBuilder: (context, error, child) {
                    return ColoredBox(
                      color: Colors.black87,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.videocam_off_outlined,
                                color: Colors.white70,
                                size: 48,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '${error.errorCode.name}: ${error.errorDetails?.message ?? ''}',
                                style: const TextStyle(color: Colors.white),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: () => _scannerController.start(),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  onDetect: (capture) {
                    for (final barcode in capture.barcodes) {
                      final value = barcode.rawValue ?? barcode.displayValue;
                      if (value != null && value.trim().isNotEmpty) {
                        _handleCode(value);
                        break;
                      }
                    }
                  },
                ),
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 240,
                      height: 160,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _lastFeedback == null
                              ? Colors.white
                              : (_lastFeedback!.found
                                  ? Colors.greenAccent
                                  : Colors.redAccent),
                          width: 2.5,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                if (_isContinuous)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 12,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_lastFeedback != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: _lastFeedback!.found
                                  ? theme.colorScheme.primaryContainer
                                  : theme.colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _lastFeedback!.message,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _lastFeedback!.found
                                    ? theme.colorScheme.onPrimaryContainer
                                    : theme.colorScheme.onErrorContainer,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        if (_scanCount > 0) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              strings.scannedCountLabel(_scanCount),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (v) => _handleCode(v, fromManual: true),
                      decoration: InputDecoration(
                        hintText: strings.scanBarcodeHint,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () =>
                        _handleCode(_manualController.text, fromManual: true),
                    child: Text(strings.findAction),
                  ),
                  if (_isContinuous) ...[
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(strings.doneAction),
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
