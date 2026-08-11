import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_editor/src/services/document_io.dart';
import 'package:pdf_editor/src/tools/pdf_merge_service.dart';
import 'package:pdf_editor/src/tools/pdf_split_service.dart';

Future<Uint8List> _makeDoc(int pages, {String marker = 'P'}) async {
  final doc = pw.Document();
  for (var i = 0; i < pages; i++) {
    doc.addPage(pw.Page(
      pageFormat: pdf.PdfPageFormat.a4,
      build: (_) => pw.Center(
        child: pw.Text('$marker${i + 1}',
            style: pw.TextStyle(fontSize: 16, color: pdf.PdfColors.blue)),
      ),
    ));
  }
  return Uint8List.fromList(await doc.save());
}

/// Round trips for the merge/split outputs exactly like the real app:
/// open the produced PDF in the editor, edit text and add an annotation,
/// save, then reopen and verify everything survived.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerBundledEditorAssets();

  const mergeService = PdfMergeService();
  const splitService = PdfSplitService();

  testWidgets('merged PDF opens, edits, saves and reopens', (tester) async {
    final a = await _makeDoc(2, marker: 'A');
    final b = await _makeDoc(3, marker: 'B');
    final merged = mergeService.merge([
      PickedPdf(name: 'a.pdf', bytes: a),
      PickedPdf(name: 'b.pdf', bytes: b),
    ]);

    final editing = PdfEditingController(merged.bytes);
    expect(PdfTextExtractor.extract(editing.document, 0).text, contains('A1'));
    final fallbacks = await loadFallbackFonts();

    final edited = editing.apply(
      (e) => e.replaceText(0, 'A1', 'EDITED_A1', fallbackFonts: fallbacks),
    );
    expect(edited, isTrue);

    final highlighted = editing.apply(
      (e) => e.addHighlight(0, [const PdfRect(48, 460, 360, 478)],
          color: 0xFFD100, author: 'test'),
    );
    expect(highlighted, isTrue);

    final saved = Uint8List.fromList(editing.bytes);

    // Reopen in a fresh session.
    final reopened = PdfDocument.open(saved);
    expect(reopened.pageCount, 5);
    expect(PdfTextExtractor.extract(reopened, 0).text, contains('EDITED_A1'));
    expect(PdfTextExtractor.extract(reopened, 2).text, contains('B1'));
    final subtypes = reopened.page(0).annotations.map((a) => a.subtype);
    expect(subtypes, contains('Highlight'));
  });

  testWidgets('split PDF opens, edits, saves and reopens', (tester) async {
    final doc = await _makeDoc(6, marker: 'P');
    final parts = splitService.splitEvery(doc, 'original.pdf', 2);
    expect(parts.length, 3);
    final first = parts.first;

    final editing = PdfEditingController(first.bytes);
    expect(PdfTextExtractor.extract(editing.document, 0).text, contains('P1'));
    final fallbacks = await loadFallbackFonts();

    final edited = editing.apply(
      (e) => e.replaceText(0, 'P1', 'EDITED_P1', fallbackFonts: fallbacks),
    );
    expect(edited, isTrue);

    final inked = editing.apply(
      (e) => e.addInk(0, [
        [(90, 400), (200, 430), (360, 395)],
      ], strokeWidth: 2.0, author: 'test'),
    );
    expect(inked, isTrue);

    final saved = Uint8List.fromList(editing.bytes);

    // Reopen in a fresh session.
    final reopened = PdfDocument.open(saved);
    expect(reopened.pageCount, 2);
    expect(PdfTextExtractor.extract(reopened, 0).text, contains('EDITED_P1'));
    final subtypes = reopened.page(0).annotations.map((a) => a.subtype);
    expect(subtypes, contains('Ink'));
  });
}
