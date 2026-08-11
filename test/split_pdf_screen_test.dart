import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_editor/src/services/document_io.dart';
import 'package:pdf_editor/src/tools/pdf_tool_util.dart';
import 'package:pdf_editor/src/tools/split_pdf_screen.dart';
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

  Future<void> pumpScreen(WidgetTester tester, Uint8List source,
      {String name = 'doc.pdf', SavePdf? savePdf}) async {
    await tester.pumpWidget(MaterialApp(
      home: SplitPdfScreen(
        pickPdf: () async => PickedPdf(name: name, bytes: source),
        showThumbnails: false,
        savePdf: savePdf,
      ),
    ));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Select PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('selecting a PDF shows its info and page grid', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SplitPdfScreen(
        pickPdf: () async => PickedPdf(name: 'doc.pdf', bytes: await _makeDoc(6)),
        showThumbnails: false,
      ),
    ));
    await tester.pump();

    expect(find.text('Select a PDF to split'), findsOneWidget);
    final splitButton =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Split PDF'));
    expect(splitButton.onPressed, isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Select PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('doc.pdf'), findsOneWidget);
    expect(find.textContaining('6 pages'), findsOneWidget);
    for (var i = 1; i <= 6; i++) {
      expect(find.byKey(ValueKey('split-page-$i')), findsOneWidget);
    }
  });

  testWidgets('extract selected pages visually into one PDF', (tester) async {
    final source = await _makeDoc(6, marker: 'P');
    Uint8List? savedBytes;
    String? savedName;
    await pumpScreen(tester, source, savePdf: (b, n) async {
      savedBytes = b;
      savedName = n;
      return true;
    });

    await tester.tap(find.byKey(const ValueKey('split-page-2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('split-page-4')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('split-page-6')));
    await tester.pump();

    expect(find.text('Extracting: 2, 4, 6'), findsOneWidget);
    // Tapping a selected page again deselects it.
    await tester.tap(find.byKey(const ValueKey('split-page-4')));
    await tester.pump();
    expect(find.text('Extracting: 2, 6'), findsOneWidget);
    // Re-selecting appends at the end: extraction follows tap order.
    await tester.tap(find.byKey(const ValueKey('split-page-4')));
    await tester.pump();
    expect(find.text('Extracting: 2, 6, 4'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Split PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Split Complete'), findsWidgets);
    expect(find.text('doc_pages_2-6-4.pdf'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(savedName, 'doc_pages_2-6-4.pdf');
    expect(savedBytes, isNotNull);
    final doc = PdfDocument.open(savedBytes!);
    expect(doc.pageCount, 3);
    expect(String.fromCharCodes(doc.page(0).contentBytes()), contains('P2'));
    expect(String.fromCharCodes(doc.page(1).contentBytes()), contains('P6'));
    expect(String.fromCharCodes(doc.page(2).contentBytes()), contains('P4'));
  });

  testWidgets('extract requires at least one selected page', (tester) async {
    await pumpScreen(tester, await _makeDoc(3));
    await tester.tap(find.widgetWithText(FilledButton, 'Split PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Select at least one page to extract.'), findsOneWidget);
    expect(find.text('Split Complete'), findsNothing);
  });

  testWidgets('clear removes the selection', (tester) async {
    await pumpScreen(tester, await _makeDoc(4));
    await tester.tap(find.byKey(const ValueKey('split-page-1')));
    await tester.pump();
    expect(find.textContaining('Extracting: 1'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pump();
    expect(find.text('Tap pages to extract'), findsOneWidget);
  });

  testWidgets('split by ranges', (tester) async {
    await pumpScreen(tester, await _makeDoc(6));

    await tester.tap(find.text('Ranges'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '1-2, 4');
    await tester.pump();
    expect(find.text('3 pages across 2 parts'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Split PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Split Complete'), findsWidgets);
    expect(find.text('2 files created'), findsOneWidget);
    expect(find.text('doc_pages_1-2.pdf'), findsOneWidget);
    expect(find.text('doc_pages_4.pdf'), findsOneWidget);
  });

  testWidgets('rejects an out-of-range range gracefully', (tester) async {
    await pumpScreen(tester, await _makeDoc(6));

    await tester.tap(find.text('Ranges'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '1-9');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Split PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('beyond this document'), findsOneWidget);
    expect(find.text('Split Complete'), findsNothing);
  });

  testWidgets('rejects malformed ranges gracefully', (tester) async {
    await pumpScreen(tester, await _makeDoc(6));

    await tester.tap(find.text('Ranges'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Split PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('not a valid page or range'), findsWidgets);
  });

  testWidgets('split every N pages', (tester) async {
    await pumpScreen(tester, await _makeDoc(6));

    await tester.tap(find.text('Every N'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '2');
    await tester.pump();
    expect(find.text('3 parts: 1-2, 3-4, 5-6'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Split PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Split Complete'), findsWidgets);
    expect(find.text('3 files created'), findsOneWidget);
    expect(find.text('doc_part_1.pdf'), findsOneWidget);
    expect(find.text('doc_part_3.pdf'), findsOneWidget);
  });

  testWidgets('split every N validates the size', (tester) async {
    await pumpScreen(tester, await _makeDoc(6));

    await tester.tap(find.text('Every N'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '0');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Split PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('Split size must be between'), findsWidgets);
    expect(find.text('Split Complete'), findsNothing);
  });

  testWidgets('a cancelled picker keeps the empty state', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SplitPdfScreen(
        pickPdf: () async => null,
        showThumbnails: false,
      ),
    ));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Select PDF'));
    await tester.pump();
    expect(find.text('Select a PDF to split'), findsOneWidget);
  });

  testWidgets('split and result screens fit a narrow phone viewport',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpScreen(tester, await _makeDoc(4));
    await tester.tap(find.text('Every N'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '2');
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Split PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Split Complete'), findsWidgets);
    expect(tester.takeException(), isNull);
    expect(find.text('2 files created'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save all'), findsOneWidget);
  });
}
