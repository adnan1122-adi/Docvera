import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_editor/src/editor/editor_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Uint8List> _makeDoc() async {
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: pdf.PdfPageFormat.a4,
    build: (_) => pw.Padding(
      padding: const pw.EdgeInsets.all(48),
      child: pw.Text('HELLO REE DIT 123',
          style: pw.TextStyle(fontSize: 16, color: pdf.PdfColors.blue)),
    ),
  ));
  return Uint8List.fromList(await doc.save());
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('committed FreeText stays re-editable in place',
      (tester) async {
    tester.view.physicalSize = const Size(700, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final bytes = await _makeDoc();

      final editing = PdfEditingController(bytes);
      final textEl = editing
          .elementsOn(0)
          .elements
          .firstWhere((e) => e.kind == PdfElementKind.text);
      final b = textEl.bounds!;
      editing.selectElementAt(0, (b.left + b.right) / 2, (b.top + b.bottom) / 2);

      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
          title: 'probe',
          bytes: bytes,
          controller: editing,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(
          find.byKey(const ValueKey('pdf-replace-element-text')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final editorFinder = find.byKey(ValueKey('inplace-0-${textEl.id}'));
      expect(editorFinder, findsOneWidget);
      final field = find.descendant(
          of: editorFinder, matching: find.byType(TextField));
      await tester.enterText(field, 'RERUN TEXT');
      await tester.pump();
      final done = find.descendant(
          of: editorFinder, matching: find.byIcon(Icons.check));
      await tester.tap(done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final reopened = PdfDocument.open(Uint8List.fromList(editing.bytes));
      final annotations = reopened.page(0).annotations
          .where((a) => a.subtype == 'FreeText')
          .toList();
      expect(annotations, hasLength(1));
      expect(annotations.single.contents, 'RERUN TEXT');

      // The committed box must be selected again automatically so the user
      // can hit its edit affordance (or tap it) to re-edit, without needing
      // to switch to the Select tool.
      expect(editing.selectedAnnotation?.subtype, 'FreeText');
      expect(editing.canEditSelectedText, isTrue);

      // The engine's inline editor opens for the selected box.
      final requested = editing.requestEditSelectedTextInline();
      expect(requested, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final engineFields = find.descendant(
          of: find.byType(PdfEditorView),
          matching: find.byType(TextField));
      // ignore: avoid_print
      print('REEDIT | engine editor fields=${engineFields.evaluate().length}');
      expect(engineFields, findsWidgets);
    });
  });
}
