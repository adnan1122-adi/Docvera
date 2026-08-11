import 'dart:typed_data';
import 'dart:ui' as ui;

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
      child: pw.Text('HELLO EDIT PROBE 123',
          style: pw.TextStyle(fontSize: 16, color: pdf.PdfColors.blue)),
    ),
  ));
  return Uint8List.fromList(await doc.save());
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('in-place text edit commits a visible FreeText overlay',
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
      final bounds = textEl.bounds!;
      final hit = editing.selectElementAt(
          0, (bounds.left + bounds.right) / 2, (bounds.top + bounds.bottom) / 2);
      // ignore: avoid_print
      print('WIDGET | selected=${editing.selectedElement?.text} hit=$hit');
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
      // ignore: avoid_print
      print('WIDGET | editButton found=${editButton.evaluate().length}');
      expect(editButton, findsOneWidget);

      await tester.tap(editButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final editorFinder =
          find.byKey(ValueKey('inplace-0-${textEl.id}'));
      // ignore: avoid_print
      print('WIDGET | inPlace box found=${editorFinder.evaluate().length}');
      expect(editorFinder, findsOneWidget);

      final field = find.descendant(
          of: editorFinder, matching: find.byType(TextField));
      await tester.enterText(field, 'EDITED_OK');
      await tester.pump();

      final done = find.descendant(
          of: editorFinder, matching: find.byIcon(Icons.check));
      expect(done, findsOneWidget);
      await tester.tap(done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // ignore: avoid_print
      print('WIDGET | after commit box still present='
          '${editorFinder.evaluate().length}');

      final committed = PdfDocument.open(editing.bytes);
      final annotations = committed.page(0).annotations
          .where((a) => a.subtype == 'FreeText')
          .toList();
      // ignore: avoid_print
      print('WIDGET | FreeText count=${annotations.length} '
          'texts=${annotations.map((a) => a.contents).toList()}');
      expect(annotations, hasLength(1));
      expect(annotations.single.contents, 'EDITED_OK');

      final remaining = editing
          .elementsOn(0)
          .elements
          .where((e) => e.kind == PdfElementKind.text)
          .length;
      // ignore: avoid_print
      print('WIDGET | remaining content text runs=$remaining');

      // The committed FreeText must actually paint - render the saved page
      // (annotations on) and count inked pixels where the text sits.
      final reopened = PdfDocument.open(Uint8List.fromList(editing.bytes));
      final img = await PdfPageRenderer.renderImage(reopened.page(0),
          annotations: true);
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      final px = data!.buffer.asUint8List();
      var inked = 0;
      for (var i = 0; i + 3 < px.length; i += 4) {
        final r = px[i];
        final g = px[i + 1];
        final b = px[i + 2];
        if (b > 120 && b > r + 30 && b > g + 30) inked++;
      }
      // ignore: avoid_print
      print('WIDGET | blue inked pixels after commit=$inked');
      expect(inked, greaterThan(50));
    });
  });

  testWidgets('EditorScreen opens a PDF without an injected controller',
      (tester) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final bytes = await _makeDoc();
      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(title: 'probe', bytes: bytes),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Could not open this PDF'), findsNothing);
      expect(find.text('The file appears to be damaged or not a valid PDF.'),
          findsNothing);
      expect(find.byType(PdfEditorView), findsOneWidget);
    });
  });

  testWidgets('EditorScreen shows the error state for invalid PDF bytes',
      (tester) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
          title: 'broken.pdf',
          bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x00, 0x01]),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Could not open this PDF'), findsOneWidget);
      expect(find.text('The file appears to be damaged or not a valid PDF.'),
          findsOneWidget);
      expect(find.byType(PdfEditorView), findsNothing);
    });
  });

  testWidgets('EditorScreen lays out on a narrow phone viewport',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final bytes = await _makeDoc();
      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(title: 'probe', bytes: bytes),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(find.byType(PdfEditorView), findsOneWidget);
      expect(find.byIcon(Icons.grid_view_outlined), findsOneWidget);
    });
  });
}
