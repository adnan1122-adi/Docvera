import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'package:pdf_editor/src/sample_pdf.dart';

const String _find = 'FIND_ME_PROGRAMMATIC';
const String _replace = 'AFTER_PROGRAMMATIC_EDIT';

/// The core engine-level round trip:
/// import -> modify text -> add highlight + freehand ink -> save ->
/// reopen -> verify both the text edit and the annotations survived.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerBundledEditorAssets();

  testWidgets('text edit, highlight and freehand persistence', (tester) async {
    final bytes = await createSamplePdf();
    final document = PdfDocument.open(bytes);
    expect(PdfTextExtractor.extract(document, 0).text, contains(_find));

    final editing = PdfEditingController(bytes);
    final fallbacks = await loadFallbackFonts();

    // 1. Rewrite existing text through the engine.
    final textEditApplied = editing.apply(
      (e) => e.replaceText(0, _find, _replace, fallbackFonts: fallbacks),
    );
    expect(textEditApplied, isTrue);

    // 2. Add a highlight annotation and a freehand ink annotation.
    final highlightApplied = editing.apply(
      (e) => e.addHighlight(0, [const PdfRect(48, 460, 360, 478)],
          color: 0xFFD100, author: 'test'),
    );
    expect(highlightApplied, isTrue);

    final inkApplied = editing.apply(
      (e) => e.addInk(0, [
        [(90, 400), (200, 430), (360, 395), (460, 420)],
      ], strokeWidth: 2.0, author: 'test'),
    );
    expect(inkApplied, isTrue);

    // 3. Save the modified bytes as the new PDF file.
    final saved = Uint8List.fromList(editing.bytes);

    // 4. Reopen the saved PDF, as if in a fresh session.
    final reopened = PdfDocument.open(saved);
    final pageText = PdfTextExtractor.extract(reopened, 0).text;

    // 5. Verify the text modification persisted and the old text is gone.
    expect(pageText, contains(_replace));
    expect(pageText, isNot(contains(_find)));

    // 6. Verify the annotations persisted.
    final subtypes = reopened.page(0).annotations.map((a) => a.subtype);
    expect(subtypes, contains('Highlight'));
    expect(subtypes, contains('Ink'));
  });
}