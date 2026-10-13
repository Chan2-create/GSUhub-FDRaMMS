import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/di/service_providers.dart';
import '../../core/utils/result.dart';
import 'qr_label.dart';
import 'qr_label_sheet.dart';

/// Saves [labels] as a PDF sheet named [fileName], and says how it went
/// (Objective 6.C).
Future<void> downloadQrLabels(
  BuildContext context,
  WidgetRef ref, {
  required List<QrLabel> labels,
  required String fileName,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (labels.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('There is nothing to print labels for.')),
    );
    return;
  }
  final download = ref.read(fileDownloadServiceProvider);
  final bytes = await QrLabelSheet.build(labels);
  final saved = await download.saveBytes(
    fileName: fileName,
    bytes: bytes,
    mimeType: 'application/pdf',
  );
  messenger.showSnackBar(switch (saved) {
    Success() => SnackBar(
      content: Text(
        '${labels.length} label${labels.length == 1 ? '' : 's'} saved to '
        '$fileName. Print it and cut along the borders.',
      ),
    ),
    Error(:final failure) => SnackBar(
      content: Text(failure.message),
      backgroundColor: AppColors.error,
    ),
  });
}

/// The code on screen, large enough to scan from the monitor, with its
/// printable label (Figure 15's QR column).
Future<void> showQrLabelDialog(BuildContext context, QrLabel label) =>
    showDialog<void>(
      context: context,
      builder: (context) => _QrLabelDialog(label: label),
    );

class _QrLabelDialog extends ConsumerWidget {
  const _QrLabelDialog({required this.label});

  final QrLabel label;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AlertDialog(
    title: Text(label.title),
    content: SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label.subtitle case final subtitle?)
            Text(subtitle, style: AppTextStyles.inventoryStatNote),
          const SizedBox(height: 16),
          Semantics(
            image: true,
            label: 'QR code for ${label.code}',
            child: BarcodeWidget(
              barcode: Barcode.qrCode(),
              data: label.code,
              width: 220,
              height: 220,
              drawText: false,
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(label.code, style: AppTextStyles.monoIdentifier),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
      FilledButton.icon(
        onPressed: () => downloadQrLabels(
          context,
          ref,
          labels: [label],
          fileName: 'label-${_safe(label.code)}.pdf',
        ),
        icon: const Icon(Icons.print_outlined, size: 18),
        label: const Text('Download label'),
      ),
    ],
  );
}

/// A code as part of a file name.
String _safe(String code) =>
    code.replaceAll(RegExp('[^A-Za-z0-9-]+'), '-').toLowerCase();
