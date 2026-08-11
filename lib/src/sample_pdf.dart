import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds a small sample PDF entirely on device.
///
/// It uses the plain Type1 (simple) Helvetica font so the DartPDF engine can
/// safely rewrite existing text runs and re-extract them afterwards - no
/// composite-/Type0 subset fonts are involved in the editable phrase.
Future<Uint8List> createSamplePdf() async {
  final doc = pw.Document();
  final body = pw.Font.helvetica();
  final bold = pw.Font.helveticaBold();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) {
        return pw.Padding(
          padding: const pw.EdgeInsets.all(48),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text('DartPDF Engine Workflow Test',
                  style: pw.TextStyle(font: bold, fontSize: 22)),
              pw.SizedBox(height: 8),
              pw.Text('This file was generated locally on the device.',
                  style: pw.TextStyle(
                      font: body, fontSize: 10, color: PdfColors.grey)),
              pw.Divider(height: 24),
              pw.Text('The quick brown fox jumps over the lazy dog.',
                  style: pw.TextStyle(font: body, fontSize: 14)),
              pw.SizedBox(height: 14),
              pw.Text('FIND_ME_PROGRAMMATIC line rewritten by the engine.',
                  style: pw.TextStyle(font: body, fontSize: 14)),
              pw.SizedBox(height: 14),
              pw.Text('Annotation test zone (highlight + freehand below).',
                  style: pw.TextStyle(font: body, fontSize: 14)),
            ],
          ),
        );
      },
    ),
  );

  final bytes = await doc.save();
  return Uint8List.fromList(bytes);
}