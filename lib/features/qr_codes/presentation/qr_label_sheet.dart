import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'qr_label.dart';

/// Lays labels out on A4 for printing and cutting (Objective 6.C): three
/// across, five down, each with its QR code, what it is, and the code in
/// text for when a scanner cannot read it.
///
/// DERIVED: neither the design nor the manuscript shows a label. Sized so
/// the code scans from arm's length (4 cm square).
abstract final class QrLabelSheet {
  static const int columns = 3;
  static const int rows = 5;

  /// The PDF, ready to save.
  static Future<Uint8List> build(List<QrLabel> labels) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/PublicSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/PublicSans-Bold.ttf'),
    );
    final document = pw.Document(
      title: 'GSUhub QR labels',
      author: 'GSUhub',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    const perPage = columns * rows;
    for (var start = 0; start < labels.length; start += perPage) {
      final page = labels.skip(start).take(perPage).toList();
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(10 * PdfPageFormat.mm),
          build: (context) => pw.GridView(
            crossAxisCount: columns,
            childAspectRatio: 1.08,
            children: [for (final label in page) _label(label)],
          ),
        ),
      );
    }
    return document.save();
  }

  static pw.Widget _label(QrLabel label) => pw.Container(
    margin: const pw.EdgeInsets.all(2 * PdfPageFormat.mm),
    padding: const pw.EdgeInsets.all(3 * PdfPageFormat.mm),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey500, width: 0.5),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
    ),
    child: pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: label.code,
          width: 40 * PdfPageFormat.mm,
          height: 40 * PdfPageFormat.mm,
        ),
        pw.SizedBox(height: 2 * PdfPageFormat.mm),
        pw.Text(
          label.title,
          maxLines: 2,
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 9,
          ),
        ),
        if (label.subtitle case final subtitle?)
          pw.Text(
            subtitle,
            maxLines: 1,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        pw.Text(
          label.code,
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey800),
        ),
      ],
    ),
  );
}
