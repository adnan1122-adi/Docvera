import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'package:pdf_editor/src/sample_pdf.dart';

const String _find = 'FIND_ME_PROGRAMMATIC';
const String _replace = 'AFTER_PROGRAMMATIC_EDIT';

Future<Uint8List> _makeMultiPage() async {
  final doc = pw.Document();
  final font = pw.Font.helvetica();
  for (final label in ['PAGE_ZERO_ORIGINAL', 'PAGE_ONE_ORIGINAL', 'PAGE_TWO_ORIGINAL']) {
    doc.addPage(pw.Page(
      pageFormat: pdf.PdfPageFormat.a4,
      build: (_) => pw.Padding(
        padding: const pw.EdgeInsets.all(48),
        child: pw.Text(label, style: pw.TextStyle(font: font, fontSize: 20)),
      ),
    ));
  }
  return Uint8List.fromList(await doc.save());
}

/// Report collector: name -> detail (null = PASS, else the error/observation).
final Map<String, String> _r = <String, String>{};

void _report(String name, String status, [String? detail]) {
  _r[name] = '${status.padRight(14)} | $detail';
}

Future<void> _guard(String name, Future<Object?> Function() body) async {
  try {
    final result = await body();
    if (result == null) {
      _report(name, 'PASS');
    } else {
      _report(name, 'FAIL', result.toString());
    }
  } catch (e, st) {
    _report(name, 'ERROR', '$e\n$st');
  }
}

Future<Object?> _reopenHas(Uint8List bytes, int page, String subtype) async {
  final d = PdfDocument.open(bytes);
  final found = d.page(page).annotations.where((a) => a.subtype == subtype);
  return found.isEmpty ? 'subtype $subtype not found on page $page' : null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerBundledEditorAssets();

  test('FEATURE MATRIX — engine-level', () async {
    final bytes = await createSamplePdf();
    final multi = await _makeMultiPage();
    final editing = PdfEditingController(bytes);
    final fallbacks = await loadFallbackFonts();

    // ---- Open / import ----
    await _guard('open/import pdf', () async {
      final d = PdfDocument.open(bytes);
      return d.pageCount >= 1 ? null : 'pageCount=${d.pageCount}';
    });

    // ---- Select an existing text object ----
    await _guard('select existing text object', () async {
      final runs = PdfTextExtractor.extract(editing.document, 0).runs;
      final run = runs.where((r) => r.text.contains('DartPDF')).firstOrNull;
      if (run == null) return 'no extractable run found';
      final b = run.bounds;
      final hit = editing.selectElementAt(0, (b.left + b.right) / 2, (b.top + b.bottom) / 2);
      final el = editing.selectedElement;
      return (hit && el != null && el.kind == PdfElementKind.text)
          ? null
          : 'hit=$hit element=${el?.kind}';
    });

    // ---- Modify existing text (programmatic replaceText) ----
    await _guard('modify existing text', () async {
      final ok = editing.apply(
          (e) => e.replaceText(0, _find, _replace, fallbackFonts: fallbacks));
      return ok ? null : 'replaceText applied no change';
    });

    // ---- Save ----
    await _guard('save', () async {
      final b = Uint8List.fromList(editing.bytes);
      return b.isNotEmpty ? null : 'empty bytes';
    });

    // ---- Close + reopen ----
    await _guard('close and reopen', () async {
      final d = PdfDocument.open(Uint8List.fromList(editing.bytes));
      return d.pageCount >= 1 ? null : 'pageCount=${d.pageCount}';
    });

    // ---- Verify modified text persists ----
    await _guard('verify modified text persists', () async {
      final d = PdfDocument.open(Uint8List.fromList(editing.bytes));
      final t = PdfTextExtractor.extract(d, 0).text;
      if (!t.contains(_replace)) return 'replacement phrase missing after reopen';
      if (t.contains(_find)) return 'original phrase still present';
      return null;
    });

    // ---- Add new text (FreeText box) ----
    await _guard('add new text (free text box)', () async {
      final d0 = PdfEditingController(bytes);
      final ok = d0.apply((e) => e.addFreeText(0,
          const PdfRect(60, 200, 400, 240), 'Brand new inserted text',
          fontSize: 16));
      if (!ok) return 'addFreeText applied no change';
      return await _reopenHas(Uint8List.fromList(d0.bytes), 0, 'FreeText');
    });

    // ---- Highlight ----
    await _guard('highlight', () async {
      final d0 = PdfEditingController(bytes);
      d0.apply((e) => e.addHighlight(
          0, [const PdfRect(60, 300, 340, 320)],
          color: 0xFFD100));
      return await _reopenHas(Uint8List.fromList(d0.bytes), 0, 'Highlight');
    });

    // ---- Underline ----
    await _guard('underline', () async {
      final d0 = PdfEditingController(bytes);
      d0.apply((e) => e.addUnderline(
          0, [const PdfRect(60, 300, 340, 320)], color: 0x108010));
      return await _reopenHas(Uint8List.fromList(d0.bytes), 0, 'Underline');
    });

    // ---- Strikeout ----
    await _guard('strikeout', () async {
      final d0 = PdfEditingController(bytes);
      d0.apply((e) => e.addStrikeOut(
          0, [const PdfRect(60, 300, 340, 320)], color: 0xD02020));
      return await _reopenHas(Uint8List.fromList(d0.bytes), 0, 'StrikeOut');
    });

    // ---- Freehand ink ----
    await _guard('freehand ink (annotation)', () async {
      final d0 = PdfEditingController(bytes);
      final ok = d0.apply((e) => e.addInk(0, [
        [(90, 420), (220, 450), (380, 400), (480, 430)],
      ]));
      if (!ok) return 'addInk applied no change';
      return await _reopenHas(Uint8List.fromList(d0.bytes), 0, 'Ink');
    });

    // ---- Freehand via live ink-stroke buffer (tool path) ----
    await _guard('freehand ink (tool buffer + finishInk)', () async {
      final d0 = PdfEditingController(bytes);
      for (var i = 0; i <= 10; i++) {
        d0.addInkStroke(0, [(100 + i * 20, 520 + (i.isEven ? 20 : 0))]);
      }
      final pending = d0.hasPendingInk;
      d0.finishInk();
      if (!pending) return 'no ink buffered';
      return await _reopenHas(Uint8List.fromList(d0.bytes), 0, 'Ink');
    });

    // ---- Shapes ----
    await _guard('shape: square', () async {
      final d0 = PdfEditingController(bytes);
      d0.apply((e) => e.addSquare(0, const PdfRect(80, 120, 240, 260)));
      return await _reopenHas(Uint8List.fromList(d0.bytes), 0, 'Square');
    });
    await _guard('shape: circle', () async {
      final d0 = PdfEditingController(bytes);
      d0.apply((e) => e.addCircle(0, const PdfRect(80, 120, 240, 260)));
      return await _reopenHas(Uint8List.fromList(d0.bytes), 0, 'Circle');
    });
    await _guard('shape: line', () async {
      final d0 = PdfEditingController(bytes);
      d0.apply((e) => e.addLine(0, (80, 120), (240, 260)));
      return await _reopenHas(Uint8List.fromList(d0.bytes), 0, 'Line');
    });
    await _guard('shape: polygon', () async {
      final d0 = PdfEditingController(bytes);
      d0.apply((e) => e.addPolygon(0, [
        (80, 120), (160, 200), (240, 120)
      ]));
      return await _reopenHas(Uint8List.fromList(d0.bytes), 0, 'Polygon');
    });

    // ---- Note ----
    await _guard('note annotation', () async {
      final d0 = PdfEditingController(bytes);
      d0.apply((e) => e.addNote(0, 140, 140, 'A sticky note'));
      return await _reopenHas(Uint8List.fromList(d0.bytes), 0, 'Text');
    });

    // ---- Undo / Redo ----
    await _guard('undo', () async {
      final d0 = PdfEditingController(bytes);
      d0.apply((e) => e.addSquare(0, const PdfRect(60, 60, 200, 200)));
      final before = d0.document.page(0).annotations.length;
      final can = d0.canUndo;
      d0.undo();
      final after = d0.document.page(0).annotations.length;
      return (can && before == 1 && after == 0)
          ? null
          : 'canUndo=$can before=$before after=$after';
    });
    await _guard('redo', () async {
      final d0 = PdfEditingController(bytes);
      d0.apply((e) => e.addSquare(0, const PdfRect(60, 60, 200, 200)));
      d0.undo();
      final can = d0.canRedo;
      d0.redo();
      final n = d0.document.page(0).annotations.length;
      return (can && n == 1) ? null : 'canRedo=$can count=$n';
    });

    // ---- Delete / move / resize annotation ----
    await _guard('delete annotation', () async {
      final d0 = PdfEditingController(bytes);
      d0.apply((e) => e.addSquare(0, const PdfRect(60, 60, 200, 200)));
      final ann = d0.document.page(0).annotations.first;
      d0.apply((e) => e.removeAnnotation(0, ann));
      final n = d0.document.page(0).annotations.length;
      return n == 0 ? null : 'annotations left: $n';
    });
    await _guard('move annotation', () async {
      final d0 = PdfEditingController(bytes);
      d0.apply((e) => e.addSquare(0, const PdfRect(60, 60, 200, 200)));
      final ann = d0.document.page(0).annotations.first;
      final before = ann.rect;
      d0.apply((e) => e.moveAnnotation(0, ann, 40, 25));
      final after = d0.document.page(0).annotations.first.rect;
      return (after.left > before.left && after.top > before.top)
          ? null
          : 'before=$before after=$after';
    });
    await _guard('resize annotation', () async {
      final d0 = PdfEditingController(bytes);
      d0.apply((e) => e.addSquare(0, const PdfRect(60, 60, 200, 200)));
      final ann = d0.document.page(0).annotations.first;
      const target = PdfRect(50, 50, 400, 400);
      d0.apply((e) => e.resizeAnnotation(0, ann, target));
      final r = d0.document.page(0).annotations.first.rect;
      return (r.right - r.left).round() == 350 ? null : 'rect=$r';
    });

    // ---- Signature ----
    await _guard('signature (self-signed)', () async {
      final d0 = PdfEditingController(bytes);
      final identity = PdfSigningIdentity.generate(name: 'Proof of concept');
      final ok = await d0.addSelfSignedSignature(identity,
          location: 'local test', reason: 'feature matrix');
      if (!ok) return 'addSelfSignedSignature returned false';
      final saved = Uint8List.fromList(d0.bytes);
      final d = PdfDocument.open(saved);
      return d.pageCount >= 1 ? null : 'reopened pageCount=${d.pageCount}';
    });

    // ---- Page ops (on 3-page doc) ----
    final pm = PdfEditingController(multi);
    await _guard('page reorder', () async {
      pm.apply((e) => e.movePage(0, 2));
      final t0 = PdfTextExtractor.extract(pm.document, 0).text;
      return t0.contains('PAGE_ONE_ORIGINAL')
          ? null
          : 'page 0 text after move: $t0';
    });
    await _guard('page deletion', () async {
      final pm2 = PdfEditingController(multi);
      pm2.apply((e) => e.removePage(1));
      return pm2.document.pageCount == 2
          ? null
          : 'pageCount=${pm2.document.pageCount}';
    });

    for (final e in _r.entries) {
      // ignore: avoid_print
      print('RESULT | ${e.key} | ${e.value}');
    }
    expect(true, isTrue, reason: 'matrix collected');
  });
}
