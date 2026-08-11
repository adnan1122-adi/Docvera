import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

/// Verifies the in-place text-edit commit path:
/// delete the original run -> add a /FreeText overlay carrying the edited
/// text in the original run's size/colour. Guards the regression where the
/// font size was clamped into the 0-1 colour range, producing a ~1pt (nearly
/// invisible) FreeText that made committed edits "disappear".
Future<Uint8List> _makeDoc() async {
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: pdf.PdfPageFormat.a4,
    build: (_) => pw.Padding(
      padding: const pw.EdgeInsets.all(48),
      child: pw.Text('HELLO EDIT PROBE 123',
          style: pw.TextStyle(fontSize: 16, color: pdf.PdfColors.blue)),
    ),
  ));
  return Uint8List.fromList(await doc.save());
}

/// Mirrors the (fixed) style recovery in editor_screen.dart: reads the active
/// Tf/rg/g/k operators leading up to the run, treating the Tf operand as a
/// point size (NOT a 0-1 colour channel).
(double, int) _styleFor(
  PdfEditingController editing,
  int page,
  PdfContentElement el,
) {
  final ops = editing.elementsOn(page).operations;
  var fontSize = 12.0;
  var color = 0x000000;

  double raw(CosObject o) => switch (o) {
        CosInteger(:final value) => value.toDouble(),
        CosReal(:final value) => value,
        _ => 0.0,
      };
  double channel(CosObject o) => raw(o).clamp(0.0, 1.0);
  double points(CosObject o) => raw(o).clamp(1.0, 500.0);
  int rgb(double r, double g, double b) =>
      ((r * 255).round() << 16) |
      ((g * 255).round() << 8) |
      (b * 255).round();

  for (var i = 0; i < ops.length && i < el.start; i++) {
    final op = ops[i];
    switch (op.operator) {
      case 'Tf':
        if (op.operands.length >= 2) fontSize = points(op.operands[1]);
      case 'rg':
        if (op.operands.length >= 3) {
          color = rgb(
            channel(op.operands[0]),
            channel(op.operands[1]),
            channel(op.operands[2]),
          );
        }
      case 'g':
        if (op.operands.isNotEmpty) {
          final v = (channel(op.operands[0]) * 255).round();
          color = (v << 16) | (v << 8) | v;
        }
      case 'k':
        if (op.operands.length >= 4) {
          final c = channel(op.operands[0]);
          final m = channel(op.operands[1]);
          final y = channel(op.operands[2]);
          final k = channel(op.operands[3]);
          color = rgb((1 - c) * (1 - k), (1 - m) * (1 - k), (1 - y) * (1 - k));
        }
      default:
        break;
    }
  }
  return (fontSize, color);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('in-place commit leaves a FreeText at the original size/colour',
      (tester) async {
    final bytes = await _makeDoc();
    final editing = PdfEditingController(bytes);
    final pageElems = editing.elementsOn(0);
    final textEl =
        pageElems.elements.firstWhere((e) => e.kind == PdfElementKind.text);
    final (fontSize, color) = _styleFor(editing, 0, textEl);
    // ignore: avoid_print
    print('COMMIT | style | fontSize=$fontSize '
        'color=#${color.toRadixString(16).padLeft(6, '0')}');

    // The bug clamps 16pt -> 1pt. Assert the fix recovers the real size.
    expect(fontSize, 16.0);
    expect(color, 0x2196F3); // PdfColors.blue

    // Exactly what _commitInPlaceEdit does: delete the run, then add the
    // /FreeText overlay with the recovered style.
    final deleted = editing.apply(
      (e) => e.deleteElements(pageElems, [textEl.id]),
    );
    expect(deleted, isTrue);
    final applied = editing.apply(
      (e) => e.addFreeText(0, textEl.bounds!, 'EDITED_OK',
          fontSize: fontSize, color: color),
    );
    expect(applied, isTrue);

    final reopened = PdfDocument.open(Uint8List.fromList(editing.bytes));

    // Original run is gone.
    final pageText = PdfTextExtractor.extract(reopened, 0).text;
    // ignore: avoid_print
    print('COMMIT | pageText | $pageText');
    expect(pageText, isNot(contains('HELLO')));

    // The overlay annotation exists and carries the correct point size - not
    // the clamped 1pt that would make the edit invisible.
    final annots = reopened.page(0).annotations;
    final ft = annots.firstWhere((a) => a.subtype == 'FreeText');
    final da = reopened.cos.resolve(ft.dict['DA']);
    final daText = da is CosString ? da.text : '';
    // ignore: avoid_print
    print('COMMIT | DA | $daText');
    expect(daText, contains('16 Tf'));
    expect(daText, contains('0.129'), reason: 'blue fill should survive');
  });
}
