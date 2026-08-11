import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_editor/src/services/document_io.dart';
import 'package:pdf_editor/src/tools/merge_pdf_screen.dart';
import 'package:pdf_editor/src/tools/pdf_tool_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpScreen(WidgetTester tester, List<PickedPdf> queue,
      {SavePdf? savePdf}) async {
    await tester.pumpWidget(MaterialApp(
      home: MergePdfScreen(
        pickPdf: () async => queue.removeAt(0),
        savePdf: savePdf,
      ),
    ));
    await tester.pump();
  }

  testWidgets('starts empty with merge disabled', (tester) async {
    await tester.pumpWidget(MaterialApp(home: MergePdfScreen()));
    await tester.pump();

    expect(find.text('Combine PDFs into one file'), findsOneWidget);
    final button =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Merge PDFs'));
    expect(button.onPressed, isNull);
  });

  testWidgets('adds PDFs and shows page counts and order positions',
      (tester) async {
    final queue = [
      PickedPdf(name: 'a.pdf', bytes: await _makeDoc(2)),
      PickedPdf(name: 'b.pdf', bytes: await _makeDoc(3)),
    ];
    await pumpScreen(tester, queue);

    await tester.tap(find.text('Add PDF'));
    await tester.pump();
    expect(find.text('a.pdf'), findsOneWidget);
    final buttonAfterOne =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Merge PDFs'));
    expect(buttonAfterOne.onPressed, isNull); // still needs a second PDF

    await tester.tap(find.text('Add PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('b.pdf'), findsOneWidget);
    expect(find.textContaining('2 pages'), findsOneWidget);
    expect(find.textContaining('3 pages'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    final button =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Merge PDFs'));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('disambiguates duplicate filenames', (tester) async {
    final queue = [
      PickedPdf(name: 'same.pdf', bytes: await _makeDoc(1)),
      PickedPdf(name: 'same.pdf', bytes: await _makeDoc(1)),
    ];
    await pumpScreen(tester, queue);

    await tester.tap(find.text('Add PDF'));
    await tester.pump();
    await tester.tap(find.text('Add PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('same.pdf'), findsOneWidget);
    expect(find.text('same (2).pdf'), findsOneWidget);
  });

  testWidgets('removing a PDF only removes the list entry', (tester) async {
    final queue = [
      PickedPdf(name: 'a.pdf', bytes: await _makeDoc(1)),
      PickedPdf(name: 'b.pdf', bytes: await _makeDoc(1)),
    ];
    await pumpScreen(tester, queue);

    await tester.tap(find.text('Add PDF'));
    await tester.pump();
    await tester.tap(find.text('Add PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('a.pdf'), findsOneWidget);
    expect(find.text('b.pdf'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();

    expect(find.text('a.pdf'), findsNothing);
    expect(find.text('b.pdf'), findsOneWidget);
    final button =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Merge PDFs'));
    expect(button.onPressed, isNull); // back below two PDFs
  });

  testWidgets('drag-reordering moves a tile down', (tester) async {
    final queue = [
      PickedPdf(name: 'a.pdf', bytes: await _makeDoc(1)),
      PickedPdf(name: 'b.pdf', bytes: await _makeDoc(1)),
      PickedPdf(name: 'c.pdf', bytes: await _makeDoc(1)),
    ];
    await pumpScreen(tester, queue);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Add PDF'));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 100));

    final beforeY = tester.getTopLeft(find.text('a.pdf')).dy;
    await tester.drag(
        find.byIcon(Icons.drag_handle).first, const Offset(0, 150));
    await tester.pumpAndSettle();
    final afterY = tester.getTopLeft(find.text('a.pdf')).dy;

    expect(afterY, greaterThan(beforeY));
  });

  testWidgets('a cancelled picker adds nothing', (tester) async {
    var cancelled = false;
    await tester.pumpWidget(MaterialApp(
      home: MergePdfScreen(pickPdf: () async {
        cancelled = true;
        return null;
      }),
    ));
    await tester.pump();
    await tester.tap(find.text('Add PDF'));
    await tester.pump();
    expect(cancelled, isTrue);
    expect(find.text('Combine PDFs into one file'), findsOneWidget);
  });

  testWidgets('merges and shows the result screen with a default filename',
      (tester) async {
    final queue = [
      PickedPdf(name: 'a.pdf', bytes: await _makeDoc(2, marker: 'A')),
      PickedPdf(name: 'b.pdf', bytes: await _makeDoc(1, marker: 'B')),
    ];
    Uint8List? savedBytes;
    String? savedName;
    await pumpScreen(tester, queue, savePdf: (b, n) async {
      savedBytes = b;
      savedName = n;
      return true;
    });

    await tester.tap(find.text('Add PDF'));
    await tester.pump();
    await tester.tap(find.text('Add PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.widgetWithText(FilledButton, 'Merge PDFs'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Merge Complete'), findsWidgets);
    expect(find.textContaining('3 pages'), findsOneWidget);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Merged_Document.pdf');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(savedName, 'Merged_Document.pdf');
    expect(savedBytes, isNotNull);
    final doc = PdfDocument.open(savedBytes!);
    expect(doc.pageCount, 3);
    expect(String.fromCharCodes(doc.page(0).contentBytes()), contains('A1'));
    expect(String.fromCharCodes(doc.page(2).contentBytes()), contains('B1'));
    expect(find.textContaining('Saved Merged_Document'), findsWidgets);
  });

  testWidgets('a merge failure shows a friendly message', (tester) async {
    final queue = [
      PickedPdf(name: 'ok.pdf', bytes: await _makeDoc(1)),
      PickedPdf(name: 'broken.pdf', bytes: Uint8List.fromList([1, 2, 3])),
    ];
    await pumpScreen(tester, queue);

    await tester.tap(find.text('Add PDF'));
    await tester.pump();
    await tester.tap(find.text('Add PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.widgetWithText(FilledButton, 'Merge PDFs'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Could not read "broken.pdf"'), findsOneWidget);
    expect(find.text('Merge Complete'), findsNothing);
  });

  testWidgets('merge screen fits a narrow phone viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final queue = [
      PickedPdf(name: 'a.pdf', bytes: await _makeDoc(2)),
      PickedPdf(name: 'b.pdf', bytes: await _makeDoc(1)),
    ];
    await pumpScreen(tester, queue);
    await tester.tap(find.text('Add PDF'));
    await tester.pump();
    await tester.tap(find.text('Add PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('a.pdf'), findsOneWidget);
    expect(find.text('b.pdf'), findsOneWidget);
  });
}
