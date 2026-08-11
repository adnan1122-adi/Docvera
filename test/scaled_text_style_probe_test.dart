import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_editor/src/editor/editor_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Uint8List> _makeScaledDoc() async {
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: pdf.PdfPageFormat.a4,
    build: (_) => pw.Padding(
      padding: const pw.EdgeInsets.all(48),
      child: pw.Transform.scale(
        scale: 2.0,
        child: pw.Text('HELLO SCALED 123',
            style: pw.TextStyle(fontSize: 8, color: pdf.PdfColors.blue)),
      ),
    ),
  ));
  return Uint8List.fromList(await doc.save());
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('in-place commit uses rendered size for scaled text',
      (tester) async {
    tester.view.physicalSize = const Size(700, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final bytes = await _makeScaledDoc();

      final editing = PdfEditingController(bytes);
      final textEl = editing
          .elementsOn(0)
          .elements
          .firstWhere((e) => e.kind == PdfElementKind.text);
      final b = textEl.bounds!;
      // ignore: avoid_print
      print('SCALED-BEFORE | boundsHeight=${b.height}');
      expect(b.height / 1.2, closeTo(16.0, 0.5),
          reason: 'sanitize: text is drawn at an effective 16pt under a 2x '
              'scale matrix');

      final hit = editing.selectElementAt(
          0, (b.left + b.right) / 2, (b.top + b.bottom) / 2);
      // ignore: avoid_print
      print('SCALED | selected=${editing.selectedElement?.text} hit=$hit');
      expect(editing.selectedElement?.kind, PdfElementKind.text);

      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
          title: 'probe',
          bytes: bytes,
          controller: editing,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final editButton = find.byKey(const ValueKey('pdf-replace-element-text'));
      expect(editButton, findsOneWidget);
      await tester.tap(editButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final editorFinder = find.byKey(ValueKey('inplace-0-${textEl.id}'));
      expect(editorFinder, findsOneWidget);

      final field = find.descendant(
          of: editorFinder, matching: find.byType(TextField));
      await tester.enterText(field, 'SCALED EDIT');
      await tester.pump();

      final done = find.descendant(
          of: editorFinder, matching: find.byIcon(Icons.check));
      await tester.tap(done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final committed = PdfDocument.open(editing.bytes);
      final annotations = committed.page(0).annotations
          .where((a) => a.subtype == 'FreeText')
          .toList();
      expect(annotations, hasLength(1));
      expect(annotations.single.contents, 'SCALED EDIT');

      final da = annotations.single.defaultAppearance!;
      final match = RegExp(r'/(\S+)\s+([\d.]+)\s+Tf').firstMatch(da);
      final committedSize = double.parse(match!.group(2)!);
      // ignore: avoid_print
      print('SCALED-AFTER | DA Tf size=$committedSize');
      expect(committedSize, closeTo(16.0, 0.5),
          reason: 'FreeText should use the rendered em (16), not the raw '
              'Tf size (8)');
    });
  });
}
