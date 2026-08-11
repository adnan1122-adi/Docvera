import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

/// Minimal reproducible test for Arabic text editing on real Chrome output.
///
/// Fixture: a real Chrome "Print to PDF" Arabic page (`/tmp/pdfedit/chrome_ar.pdf`).
///
/// How Chrome draws Arabic:
///   * glyphs in *visual* (RTL) order, each wrapped in `BDC Span … EMC` and
///     positioned by its own `Td`, inside a `/ReversedChars` marked-content
///     object - so the engine's old run grouping (consecutive `Tj`/`TJ`) gave
///     one run per glyph and decoded visual-order text that a logical-order
///     Arabic `find` never matched.
///   * the engine now rewrites such structured runs whole (the whole `BT…ET`
///     object), matches `find` against the reversed (logical) /ToUnicode text
///     inside `/ReversedChars`, and splices the replacement in place.
///
/// The test asserts the fix (count > 0) and that the replacement survives a
/// re-open and extraction.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerBundledEditorAssets();

  test('Arabic word (logical order) matches a visual-order RTL run', () async {
    final bytes = File('/tmp/pdfedit/chrome_ar.pdf').readAsBytesSync();
    final doc = PdfDocument.open(bytes);

    // 1. extraction: the logical-order text a user copies.
    final extracted = PdfTextExtractor.extract(doc, 0).text;
    final token = extracted
        .split(RegExp(r'\s+'))
        .firstWhere(
            (w) => w.runes.length >= 3 && w.runes.any((r) => r > 0x20),
            orElse: () => '')
        .trim();
    expect(token, isNotEmpty, reason: 'fixture must contain Arabic text');
    // ignore: avoid_print
    print('REPRO | extracted logical text = "$extracted"');
    // ignore: avoid_print
    print('REPRO | logical find token = "$token"');

    // 2. edit with bundled fallback fonts (the Latin replacement "TESTX" is
    // not drawable by the Arabic subset font, so it lands in the fallback).
    final editing = PdfEditingController(bytes);
    var count = 0;
    final fallbacks = await loadFallbackFonts();
    editing.apply((e) => count =
        e.replaceText(0, token, 'TESTX', fallbackFonts: fallbacks));
    // ignore: avoid_print
    print('REPRO | replaceText("$token" -> "TESTX") = $count');
    expect(count, greaterThan(0),
        reason: 'logical-order Arabic find must match the visual-order RTL run');

    // 3. the replacement survives a re-open and shows up in extraction.
    final reopened = PdfDocument.open(Uint8List.fromList(editing.bytes));
    final after = PdfTextExtractor.extract(reopened, 0).text;
    // ignore: avoid_print
    print('REPRO | after edit = "$after"');
    expect(after.contains('TESTX'), isTrue,
        reason: 'replacement must be visible to extraction');

    // 4. render before/after for visual confirmation.
    await _render(bytes, '/tmp/pdfedit/renders/ar_before.png');
    await _render(Uint8List.fromList(editing.bytes),
        '/tmp/pdfedit/renders/ar_after.png');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<void> _render(Uint8List bytes, String path) async {
  try {
    final doc = PdfDocument.open(bytes);
    final img = await PdfPageRenderer.renderImage(doc.page(0),
        pixelRatio: 2, annotations: false);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    await File(path).parent.create(recursive: true);
    await File(path).writeAsBytes(data!.buffer.asUint8List());
    img.dispose();
    // ignore: avoid_print
    print('RENDER | $path');
  } catch (e) {
    // ignore: avoid_print
    print('RENDER | $path FAILED: $e');
  }
}
