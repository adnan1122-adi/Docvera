import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

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

/// Counts non-white (inked) pixels; for the blue text, counts "blue" pixels.
Future<int> _inkedPixels(ui.Image img, {bool blueOnly = false}) async {
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return 0;
  final bytes = data.buffer.asUint8List();
  var count = 0;
  for (var i = 0; i + 3 < bytes.length; i += 4) {
    final r = bytes[i];
    final g = bytes[i + 1];
    final b = bytes[i + 2];
    final a = bytes[i + 3];
    if (a == 0) continue;
    if (blueOnly) {
      if (b > 120 && b > r + 30 && b > g + 30) count++;
    } else if (r < 250 || g < 250 || b < 250) {
      count++;
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('committed FreeText paints visibly on the rendered page',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = await _makeDoc();
      final editing = PdfEditingController(bytes);
      final pageElems = editing.elementsOn(0);
      final textEl =
          pageElems.elements.firstWhere((e) => e.kind == PdfElementKind.text);
      final (fontSize, color) = _styleFor(editing, 0, textEl);
      // ignore: avoid_print
      print('RENDER | style | fontSize=$fontSize color=#${color.toRadixString(16).padLeft(6, '0')}');
      expect(fontSize, 16.0);

      // Baseline: the original blue text renders.
      var img = await PdfPageRenderer.renderImage(
          PdfDocument.open(bytes).page(0),
          annotations: true);
      final before = await _inkedPixels(img, blueOnly: true);
      // ignore: avoid_print
      print('RENDER | before | bluePixels=$before');
      expect(before, greaterThan(50));
      img.dispose();

      // Commit exactly like _commitInPlaceEdit.
      editing.apply((e) => e.deleteElements(pageElems, [textEl.id]));
      editing.apply((e) => e.addFreeText(0, textEl.bounds!, 'EDITED_OK',
          fontSize: fontSize, color: color));

      final reopened = PdfDocument.open(Uint8List.fromList(editing.bytes));
      img = await PdfPageRenderer.renderImage(reopened.page(0),
          annotations: true);
      final after = await _inkedPixels(img, blueOnly: true);
      // ignore: avoid_print
      print('RENDER | after | bluePixels=$after');
      img.dispose();
      expect(after, greaterThan(50));
    });
  });
}
