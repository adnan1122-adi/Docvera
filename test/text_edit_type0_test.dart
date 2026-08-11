import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

const String _type0Find = 'TYPE0_EDIT_PROBE';
const String _type0Replace = 'TYPE0_EDITED_OK';

/// A PDF whose text uses an embedded, subset TrueType font. Such fonts are
/// /Type0 composite fonts and represent what most real-world PDFs contain
/// (exported by Word, browsers, report generators). This is where text
/// editing historically struggles, so it is tested explicitly.
Future<Uint8List> _makeType0Doc() async {
  final data = await rootBundle
      .load('packages/dart_pdf_editor_assets/assets/fonts/DejaVuSans.ttf');
  final font = pw.Font.ttf(data);
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: pdf.PdfPageFormat.a4,
    build: (_) => pw.Padding(
      padding: const pw.EdgeInsets.all(48),
      child: pw.Text('$_type0Find on a composite font line',
          style: pw.TextStyle(font: font, fontSize: 16)),
    ),
  ));
  return Uint8List.fromList(await doc.save());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerBundledEditorAssets();

  test('text editing on a composite (/Type0) font PDF', () async {
    final bytes = await _makeType0Doc();

    final doc = PdfDocument.open(bytes);
    final pageText = PdfTextExtractor.extract(doc, 0).text;
    // ignore: avoid_print
    print('RESULT | type0: extractable text present | '
        '${pageText.contains(_type0Find) ? 'PASS' : 'FAIL'} | contains=$_type0Find');

    final editing = PdfEditingController(bytes);
    final fallbacks = await loadFallbackFonts();

    // without fallback fonts
    final okNoFallback = editing.apply(
        (e) => e.replaceText(0, _type0Find, _type0Replace));
    final afterNoFallback = PdfTextExtractor.extract(editing.document, 0).text;
    // ignore: avoid_print
    print('RESULT | type0: replaceText (no fallback fonts) | '
        '${afterNoFallback.contains(_type0Replace) ? 'PASS' : 'FAIL'} | '
        'replaced=${afterNoFallback.contains(_type0Replace)} '
        'original=${afterNoFallback.contains(_type0Find)} apply=$okNoFallback');

    // fresh doc, with fallback fonts (the engine bundles DejaVu)
    final editing2 = PdfEditingController(bytes);
    final okWithFallback = editing2.apply((e) => e.replaceText(
        0, _type0Find, _type0Replace,
        fallbackFonts: fallbacks));
    final saved = Uint8List.fromList(editing2.bytes);
    final reopened = PdfDocument.open(saved);
    final afterFallback = PdfTextExtractor.extract(reopened, 0).text;
    // ignore: avoid_print
    print('RESULT | type0: replaceText (with bundled fallback fonts) | '
        '${afterFallback.contains(_type0Replace) ? 'PASS' : 'FAIL'} | '
        'replaced=${afterFallback.contains(_type0Replace)} '
        'original=${afterFallback.contains(_type0Find)} apply=$okWithFallback');
  });
}