import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({
    required this.title,
    required this.hint,
    super.key,
  });

  final String title;
  final String hint;

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  late final MobileScannerController _controller;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      autoStart: true,
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.code93,
        BarcodeFormat.codabar,
        BarcodeFormat.itf14,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.qrCode,
        BarcodeFormat.dataMatrix,
        BarcodeFormat.pdf417,
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    String? value;
    for (final barcode in capture.barcodes) {
      final candidate = barcode.rawValue?.trim();
      if (candidate != null && candidate.isNotEmpty) {
        value = candidate;
        break;
      }
    }
    if (value == null) return;
    _handled = true;
    await _controller.stop();
    if (mounted) Navigator.pop(context, value);
  }

  Future<void> _restartCamera() async {
    try {
      await _controller.stop();
    } on Object {
      // The controller can already be stopped after an initialization error.
    }
    if (!mounted) return;
    try {
      await _controller.start();
    } on Object {
      // The scanner error builder displays the native error details.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Фонарик',
            onPressed: _controller.toggleTorch,
            icon: const Icon(Icons.flashlight_on_outlined),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final scanWindow = Rect.fromCenter(
            center: Offset(constraints.maxWidth / 2, constraints.maxHeight / 2),
            width: constraints.maxWidth - 48,
            height: 190,
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _controller,
                fit: BoxFit.cover,
                scanWindow: scanWindow,
                tapToFocus: true,
                onDetect: _onDetect,
                errorBuilder: (context, error) => _CameraError(
                  error: error,
                  onRetry: _restartCamera,
                ),
              ),
              _ScannerOverlay(scanWindow: scanWindow),
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  minimum: const EdgeInsets.all(20),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.76),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Text(
                        widget.hint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay({required this.scanWindow});

  final Rect scanWindow;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fromRect(
            rect: scanWindow,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Positioned(
            left: scanWindow.left,
            width: scanWindow.width,
            top: scanWindow.top - 34,
            child: const Text(
              'В рамке должен быть только один код',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(blurRadius: 6, color: Colors.black)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error, required this.onRetry});

  final MobileScannerException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final detailCode = error.errorDetails?.code;
    final detailMessage = error.errorDetails?.message;
    final technicalDetails = <String>[
      error.errorCode.name,
      if (detailCode != null && detailCode.isNotEmpty) detailCode,
      if (detailMessage != null && detailMessage.isNotEmpty) detailMessage,
    ].join('\n');

    return ColoredBox(
      color: const Color(0xFF101828),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: Colors.white,
                size: 48,
              ),
              const SizedBox(height: 16),
              const Text(
                'Камера недоступна',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Не удалось запустить модуль сканирования. Закройте другие приложения, использующие камеру, и нажмите «Повторить».',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Text(
                technicalDetails,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
