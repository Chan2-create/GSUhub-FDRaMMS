import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen camera for reading a facility's QR code (manuscript §1.7).
///
/// The design has no frame for this, so it is plain Material and flagged
/// as such (Objective 3.C): the camera, a torch toggle, one line of
/// guidance, and a way back. It returns the first code it reads.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  /// The scanner reports the same code many times a second; only the
  /// first may close the screen.
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: const Text('Scan facility QR code'),
      actions: [
        IconButton(
          tooltip: 'Torch',
          onPressed: _controller.toggleTorch,
          icon: const Icon(Icons.flashlight_on_outlined),
        ),
      ],
    ),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => _ScannerError(error: error),
        ),
        const Positioned(
          left: 24,
          right: 24,
          bottom: 32,
          child: Text(
            'Point the camera at the QR code on the room or equipment.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      ],
    ),
  );
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          switch (error.errorCode) {
            MobileScannerErrorCode.permissionDenied =>
              "Camera access is blocked for GSUhub. Allow it in your phone's "
                  'Settings to scan, or choose the building and room instead.',
            MobileScannerErrorCode.unsupported =>
              "This device can't scan QR codes. Choose the building and room "
                  'instead.',
            _ =>
              "The camera couldn't start. Choose the building and room "
                  'instead.',
          },
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
    ),
  );
}

/// Opens [QrScannerScreen] and returns what it read, or null when the
/// requestor backs out. A provider so tests can answer without a camera.
typedef QrScanLauncher = Future<String?> Function(BuildContext context);

final qrScanLauncherProvider = Provider<QrScanLauncher>(
  (ref) =>
      (context) => Navigator.of(context).push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const QrScannerScreen(),
        ),
      ),
);
