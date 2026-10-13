import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen camera for reading a facility's QR code (manuscript §1.7).
///
/// The design has no frame for this, so it is plain Material and flagged
/// as such (Objective 3.C): the camera, a torch toggle, one line of
/// guidance, and a way back. It returns the first code it reads.
///
/// The personnel app (Objective 5.C) opens the same screen with its own
/// wording, reading barcodes as well (§1.5: "QR code or barcode scanning
/// for identifying and recording materials, tools, and equipment").
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({
    super.key,
    this.title = 'Scan facility QR code',
    this.guidance = 'Point the camera at the QR code on the room or equipment.',
    this.fallback = 'choose the building and room instead',
    this.formats = const [BarcodeFormat.qrCode],
  });

  final String title;
  final String guidance;

  /// What to do instead when the camera cannot scan, ending the sentence
  /// "Allow it in your phone's Settings to scan, or …".
  final String fallback;

  final List<BarcodeFormat> formats;

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  late final _controller = MobileScannerController(formats: widget.formats);

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
      title: Text(widget.title),
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
          errorBuilder: (context, error) =>
              _ScannerError(error: error, fallback: widget.fallback),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 32,
          child: Text(
            widget.guidance,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      ],
    ),
  );
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.error, required this.fallback});

  final MobileScannerException error;
  final String fallback;

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
                  'Settings to scan, or $fallback.',
            MobileScannerErrorCode.unsupported =>
              "This device can't scan codes. ${_sentence(fallback)}.",
            _ => "The camera couldn't start. ${_sentence(fallback)}.",
          },
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
    ),
  );

  static String _sentence(String phrase) =>
      phrase.isEmpty ? phrase : phrase[0].toUpperCase() + phrase.substring(1);
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

/// The personnel app's scanner (Objective 5.C): any code GSUhub prints,
/// QR or barcode, on a material, a tool, a room or equipment.
final personnelScanLauncherProvider = Provider<QrScanLauncher>(
  (ref) =>
      (context) => Navigator.of(context).push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const QrScannerScreen(
            title: 'Scan a code',
            guidance:
                'Point the camera at the QR code or barcode on a material, a '
                'tool, a room or a piece of equipment.',
            fallback: 'pick the item from its list instead',
            formats: [BarcodeFormat.all],
          ),
        ),
      ),
);
