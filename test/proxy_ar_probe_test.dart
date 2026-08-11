import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

// ignore_for_file: avoid_print

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerBundledEditorAssets();

  test('proxy ar probe', () async {
    final data = File(
            '/Users/muhammadadnan/.pub-cache/hosted/pub.dev/'
            'dart_pdf_editor_assets-3.4.0/assets/fonts/DejaVuSans.ttf')
        .readAsBytesSync();
    final font = pw.Font.ttf(ByteData.sublistView(data));
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: pdf.PdfPageFormat.a4,
      build: (_) => pw.Padding(
        padding: const pw.EdgeInsets.all(48),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('هذه جملة عربية للاختبار',
                style: pw.TextStyle(font: font, fontSize: 14)),
            pw.SizedBox(height: 12),
            pw.Text('English words here then Arabic',
                style: pw.TextStyle(font: font, fontSize: 14)),
          ],
        ),
      ),
    ));
    final bytes = Uint8List.fromList(await doc.save());
    final d = PdfDocument.open(bytes);
    final cos = d.cos;
    final fonts = cos.resolve(d.page(0).resources['Font']);
    final names = <String>[];
    if (fonts is CosDictionary) {
      fonts.entries.forEach((k, v) {
        final f = cos.resolve(v);
        if (f is CosDictionary) {
          final sub = f['Subtype'] is CosName ? (f['Subtype'] as CosName).value : '?';
          names.add('$k:$sub');
        }
      });
    }
    print('PX | fonts=${names.join(',')}');
    print('PX | text=${PdfTextExtractor.extract(d, 0).text.replaceAll('\n', '⏎')}');
    final img = await PdfPageRenderer.renderImage(d.page(0), pixelRatio: 1.5);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('/tmp/pdfedit/compat/renders/proxy_ar_before.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
    print('PX | rendered ${png.lengthInBytes} bytes');
  });
}
