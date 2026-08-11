import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

/// Probes why the pdf-package subset font reports `glyphForRune == 0` for the
/// document's own characters - the trigger for unnecessary fallback embedding.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pdf-package subset cmap coverage', () async {
    final data = await rootBundle
        .load('packages/dart_pdf_editor_assets/assets/fonts/DejaVuSans.ttf');
    final font = pw.Font.ttf(data);
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: pdf.PdfPageFormat.a4,
      build: (_) => pw.Padding(
        padding: const pw.EdgeInsets.all(48),
        child: pw.Text('SUBSET_TTF_PROBE line with several words here.',
            style: pw.TextStyle(font: font, fontSize: 14)),
      ),
    ));
    final bytes = Uint8List.fromList(await doc.save());
    final d = PdfDocument.open(bytes);
    final cos = d.cos;
    final fonts = cos.resolve(d.page(0).resources['Font']);
    final f = cos.resolve((fonts as CosDictionary).entries.values.first);
    final embedded = PdfEmbeddedFont.fromFontDict(cos, f as CosDictionary, 'F0');
    // ignore: avoid_print
    print('CMAP | embedded parsed: ${embedded != null} '
        'bytes=${embedded?.fontBytes.length}');
    if (embedded == null) return;
    for (final rune in 'SUBSET_TTF_PROBE'.runes) {
      // ignore: avoid_print
      print('CMAP | glyphForRune("${String.fromCharCode(rune)}") = '
          '${embedded.glyphForRune(rune)}');
    }
    // ignore: avoid_print
    print('CMAP | distinct nonzero gids for the doc text: ${{
      for (final r in 'SUBSET_TTF_PROBE line with several words here.'.runes)
        if (embedded.glyphForRune(r) != 0) r
    }}');
  });
}
