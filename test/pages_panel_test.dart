import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_editor/src/editor/editor_screen.dart';
import 'package:pdf_editor/src/editor/pages_panel.dart';
import 'package:pdf_editor/src/services/document_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Uint8List> _makeDoc(int pages) async {
  final doc = pw.Document();
  for (var i = 0; i < pages; i++) {
    doc.addPage(pw.Page(
      pageFormat: pdf.PdfPageFormat.a4,
      build: (_) => pw.Padding(
        padding: const pw.EdgeInsets.all(48),
        child: pw.Text('PAGE ${i + 1}',
            style: pw.TextStyle(fontSize: 16, color: pdf.PdfColors.blue)),
      ),
    ));
  }
  return Uint8List.fromList(await doc.save());
}

/// Taps a bottom action-bar button, scrolling the bar so an off-screen
/// button (the bar scrolls horizontally on narrower windows) is visible.
Future<void> tapAction(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('page manager: toolbar states, add, duplicate, rotate, undo',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final editing = PdfEditingController(await _makeDoc(4));
      final viewer = PdfViewerController();

      await tester.pumpWidget(MaterialApp(
        home: PagesPanel(
          editing: editing,
          viewer: viewer,
          documentName: 'report.pdf',
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // All 4 tiles render.
      expect(find.byKey(const ValueKey('pdf-thumbnail-grid-cell-3')),
          findsOneWidget);
      // Page count in the app bar.
      expect(find.text('Pages · 4'), findsOneWidget);

      // No selection -> neutral toolbar.
      expect(find.byKey(const ValueKey('pages-action-select-all')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pages-action-add')), findsOneWidget);
      expect(find.byKey(const ValueKey('pages-action-insert')), findsOneWidget);
      expect(find.byKey(const ValueKey('pages-action-delete')), findsNothing);

      // Add a blank page at the end (default) via the dialog.
      await tapAction(tester, const ValueKey('pages-action-add'));
      await tester.pumpAndSettle();
      expect(find.text('Add blank page'), findsOneWidget);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(editing.document.pageCount, 5);
      expect(find.text('Pages · 5'), findsOneWidget);

      // Duplicate page 0.
      editing.selectPage(0);
      await tester.pump();
      expect(find.byKey(const ValueKey('pages-action-duplicate')),
          findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      await tapAction(tester, const ValueKey('pages-action-duplicate'));
      await tester.pumpAndSettle();
      expect(editing.document.pageCount, 6);

      // Rotate page 0 right -> /Rotate 90.
      editing.selectPage(0);
      await tester.pump();
      await tapAction(tester, const ValueKey('pages-action-rotate-right'));
      await tester.pumpAndSettle();
      expect(editing.pageAt(0).rotation, 90);

      // Undo restores rotation.
      expect(editing.canUndo, isTrue);
      await tester.tap(find.byIcon(Icons.undo));
      await tester.pumpAndSettle();
      expect(editing.pageAt(0).rotation, 0);

      editing.dispose();
      viewer.dispose();
    });
  });

  testWidgets('page manager: delete guard refuses to empty the document',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final editing = PdfEditingController(await _makeDoc(2));
      final viewer = PdfViewerController();

      await tester.pumpWidget(MaterialApp(
        home: PagesPanel(editing: editing, viewer: viewer),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      editing.selectAllPages();
      await tester.pump();
      await tapAction(tester, const ValueKey('pages-action-delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Guard message, no dialog, no page removed.
      expect(find.textContaining('at least one page'), findsOneWidget);
      expect(find.text('Delete pages?'), findsNothing);
      expect(editing.document.pageCount, 2);

      // Deleting a single page works after confirmation.
      editing.clearPageSelection();
      editing.selectPage(1);
      await tester.pump();
      await tapAction(tester, const ValueKey('pages-action-delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete page?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(editing.document.pageCount, 1);

      editing.dispose();
      viewer.dispose();
    });
  });

  testWidgets('page manager: add blank page after selected + A4 size',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final editing = PdfEditingController(await _makeDoc(4));
      final viewer = PdfViewerController();

      await tester.pumpWidget(MaterialApp(
        home: PagesPanel(editing: editing, viewer: viewer),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Insert a blank page after the selected page 0.
      editing.selectPage(0);
      await tester.pump();
      await tapAction(tester, const ValueKey('pages-action-add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('After selected page'));
      await tester.pump();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(editing.document.pageCount, 5);
      // The blank page lands at index 1 (after page 0), not at the end.
      final textRuns = editing
          .elementsOn(1)
          .elements
          .where((e) => e.kind == PdfElementKind.text)
          .length;
      expect(textRuns, 0);

      // Undo + redo of the structural change through the app bar.
      await tester.tap(find.byIcon(Icons.undo));
      await tester.pumpAndSettle();
      expect(editing.document.pageCount, 4);
      await tester.tap(find.byIcon(Icons.redo));
      await tester.pumpAndSettle();
      expect(editing.document.pageCount, 5);

      // Undo/redo restored the page selection, so clear it before adding.
      editing.clearPageSelection();
      await tester.pump();

      // Add an explicit A4 page at the end.
      await tapAction(tester, const ValueKey('pages-action-add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A4'));
      await tester.pump();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(editing.document.pageCount, 6);
      final box = editing.pageAt(5).mediaBox;
      expect(box.width, closeTo(595.28, 0.5));
      expect(box.height, closeTo(841.89, 0.5));

      editing.dispose();
      viewer.dispose();
    });
  });

  testWidgets('page manager: clear selection restores neutral toolbar',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final editing = PdfEditingController(await _makeDoc(2));
      final viewer = PdfViewerController();

      await tester.pumpWidget(MaterialApp(
        home: PagesPanel(editing: editing, viewer: viewer),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      editing.selectPage(0);
      await tester.pump();
      expect(find.byKey(const ValueKey('pages-action-delete')), findsOneWidget);

      await tapAction(tester, const ValueKey('pages-action-clear'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pages-action-delete')), findsNothing);
      expect(find.byKey(const ValueKey('pages-action-select-all')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pages-action-add')), findsOneWidget);

      editing.dispose();
      viewer.dispose();
    });
  });

  testWidgets('editor screen: Pages button opens the page manager',
      (tester) async {
    tester.view.physicalSize = const Size(700, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final bytes = await _makeDoc(3);
      final editing = PdfEditingController(bytes);

      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
          title: 'report.pdf',
          bytes: bytes,
          controller: editing,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byIcon(Icons.grid_view_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(PagesPanel), findsOneWidget);
      expect(find.text('Pages · 3'), findsOneWidget);

      // The panel shares the same editing controller, so edits persist.
      await tapAction(tester, const ValueKey('pages-action-select-all'));
      await tester.pump();
      // My selection toolbar appears and reports the count (the engine's
      // grid header also shows one for multi-select).
      expect(find.byKey(const ValueKey('pages-action-export')), findsOneWidget);
      expect(find.text('3 selected'), findsWidgets);
      expect(find.text('1 page'), findsNothing);

      editing.dispose();
    });
  });

  testWidgets('page manager: insert PDF after selected page', (tester) async {
    tester.view.physicalSize = const Size(1100, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final editing = PdfEditingController(await _makeDoc(2));
      final viewer = PdfViewerController();
      // The imported file the picker would return: a single page whose
      // content is distinct from the host doc so the insertion spot is
      // provable.
      final incomingDoc = pw.Document();
      incomingDoc.addPage(pw.Page(
        pageFormat: pdf.PdfPageFormat.a4,
        build: (_) => pw.Center(
          child: pw.Text('INSERTED MARKER',
              style: pw.TextStyle(fontSize: 20, color: pdf.PdfColors.red)),
        ),
      ));
      final incoming = Uint8List.fromList(await incomingDoc.save());

      await tester.pumpWidget(MaterialApp(
        home: PagesPanel(
          editing: editing,
          viewer: viewer,
          pickPdf: () async => PickedPdf(name: 'incoming.pdf', bytes: incoming),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Insert after the selected page 0 -> lands at index 1.
      editing.selectPage(0);
      await tester.pump();
      await tapAction(tester, const ValueKey('pages-action-insert'));
      await tester.pumpAndSettle();
      expect(find.text('Insert pages'), findsOneWidget);
      await tester.tap(find.text('After selected page'));
      await tester.pump();
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      expect(editing.document.pageCount, 3);
      final pageOneText = editing
          .elementsOn(1)
          .elements
          .where((e) => e.kind == PdfElementKind.text)
          .map((e) => e.text)
          .join(' ');
      expect(pageOneText, contains('INSERTED'));
      // The host page 0 is untouched at its original spot.
      final pageZeroText = editing
          .elementsOn(0)
          .elements
          .where((e) => e.kind == PdfElementKind.text)
          .map((e) => e.text)
          .join(' ');
      expect(pageZeroText, contains('PAGE 1'));

      editing.dispose();
      viewer.dispose();
    });
  });

  testWidgets('page manager: export selection uses chosen filename',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final editing = PdfEditingController(await _makeDoc(3));
      final viewer = PdfViewerController();
      Uint8List? saved;
      String? savedName;

      await tester.pumpWidget(MaterialApp(
        home: PagesPanel(
          editing: editing,
          viewer: viewer,
          documentName: 'report.pdf',
          savePdf: (bytes, name) async {
            saved = bytes;
            savedName = name;
            return true;
          },
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      editing
        ..selectPage(0)
        ..togglePageSelection(2);
      await tester.pump();
      await tapAction(tester, const ValueKey('pages-action-export'));
      await tester.pumpAndSettle();

      expect(savedName, 'report_pages_1-3.pdf');
      expect(find.text('Exported 2 pages.'), findsOneWidget);
      final exported = PdfDocument.open(saved!);
      expect(exported.pageCount, 2);

      editing.dispose();
      viewer.dispose();
    });
  });
}
