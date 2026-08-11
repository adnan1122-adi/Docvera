import 'dart:async';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

import 'package:pdf_editor/src/sample_pdf.dart';

/// Viewer/UI-level matrix.
///
/// - Shell-based checks use bounded `pump(duration)` calls instead of
///   `pumpAndSettle` because PdfEditorView schedules continuous tile renders,
///   and end with an explicit unmount so no timers stay pending at teardown.
/// - Search/navigation run against a bare [PdfViewer] with the auto render
///   worker disabled (same setup the engine's own test suite uses) so the
///   search path is on-thread and `pumpAndSettle` can drain its per-page
///   timers. Through the editing shell the search path goes over an isolate
///   worker, which cannot be drained deterministically in a widget test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerBundledEditorAssets();
  PdfViewer.debugAutoRenderWorkerEnabled = false;

  void report(String name, bool pass, [String? detail]) {
    // ignore: avoid_print
    print('RESULT | $name | ${pass ? 'PASS' : 'FAIL'} | $detail');
  }

  testWidgets(
    'viewer shell matrix',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final bytes = await createSamplePdf();
      final editing = PdfEditingController(bytes);
      final viewer = PdfViewerController();
      Uint8List? saveBytes;
      String? buildError;

      Future<void> pumpFrames() async {
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
      }

      try {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: PdfEditorView(
              controller: editing,
              viewerController: viewer,
              documentId: 'viewer-matrix-test',
              onSave: (b) => saveBytes = Uint8List.fromList(b),
            ),
          ),
        ));
        await pumpFrames();
      } catch (e, st) {
        buildError = '$e\n$st';
      }

      report('display / render (PdfEditorView shell)', buildError == null,
          buildError ?? 'viewer built without exception');
      if (buildError != null) {
        // ignore: avoid_print
        print('RESULT | display / render | ERROR | $buildError');
        return;
      }

      var ok = false;
      var detail = '';
      try {
        final before = viewer.zoom;
        viewer.setZoom(2.0);
        await pumpFrames();
        ok = viewer.zoom > before;
        detail = 'before=$before after=${viewer.zoom}';
      } catch (e) {
        detail = 'ERROR: $e';
      }
      report('zoom control', ok, detail);

      ok = false;
      detail = '';
      try {
        await tester.drag(find.byType(PdfEditorView), const Offset(0, -150),
            warnIfMissed: false);
        await pumpFrames();
        ok = true;
        detail = 'pan gesture completed without exception';
      } catch (e) {
        detail = 'ERROR: $e';
      }
      report('pan gesture (no exception)', ok, detail);

      ok = false;
      detail = '';
      try {
        editing.apply(
            (e) => e.replaceText(0, 'FIND_ME_PROGRAMMATIC', 'FIND_ME_EDITED'));
        await pumpFrames();
        final saveFinder = find.byKey(const ValueKey('pdf-shell-save'));
        final found = saveFinder.evaluate().isNotEmpty;
        var enabled = false;
        if (found) {
          final b = tester.widget<FilledButton>(saveFinder);
          enabled = b.onPressed != null;
          if (enabled) await tester.tap(saveFinder);
        }
        await pumpFrames();
        ok = found && enabled && saveBytes != null && saveBytes!.length > 100 &&
            String.fromCharCodes(saveBytes!.sublist(0, 5)) == '%PDF-';
        detail = found
            ? 'found, enabled=$enabled, isModified=${editing.isModified}, '
                'onSave bytes=${saveBytes?.length}'
            : 'Save button (pdf-shell-save) not found';
      } catch (e) {
        detail = 'ERROR: $e';
      }
      report('shell Save triggers onSave callback', ok, detail);

      ok = false;
      detail = '';
      try {
        viewer.setZoom(1.0);
        await pumpFrames();
        final b = editing.bytes;
        ok = b.isNotEmpty && String.fromCharCodes(b.sublist(0, 5)) == '%PDF-';
        detail = 'controller.bytes=${b.length}';
      } catch (e) {
        detail = 'ERROR: $e';
      }
      report('modified bytes available (PDF output)', ok, detail);

      // Unmount so the shell can cancel its tile-render timers.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'viewer search & navigation matrix (bare viewer)',
    (tester) async {
      final bytes = await createSamplePdf();
      final editing = PdfEditingController(bytes);
      final viewer = PdfViewerController();
      addTearDown(viewer.dispose);

      try {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: PdfViewer(
              document: editing.document,
              controller: viewer,
              documentId: 'viewer-search-matrix',
            ),
          ),
        ));
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
      } catch (e, st) {
        // ignore: avoid_print
        print('RESULT | search (find text) | ERROR | $e\n$st');
        return;
      }

      var ok = false;
      var detail = '';
      try {
        unawaited(viewer.search('PROGRAMMATIC'));
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        ok = viewer.matchCount >= 1 && viewer.searchResults.isNotEmpty;
        detail = 'matchCount=${viewer.matchCount} '
            'results=${viewer.searchResults.map((r) => r.pageIndex).toList()}';
      } catch (e) {
        detail = 'ERROR: $e';
      }
      report('search / find text', ok, detail);

      ok = false;
      detail = '';
      try {
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        ok = viewer.currentPage == 0;
        detail = 'currentPage=${viewer.currentPage}';
      } catch (e) {
        detail = 'ERROR: $e';
      }
      report('page navigation (current page)', ok, detail);

      ok = false;
      detail = '';
      try {
        viewer.setZoom(1.5);
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        ok = viewer.zoom > 1.0;
        detail = 'zoom=${viewer.zoom}';
      } catch (e) {
        detail = 'ERROR: $e';
      }
      report('zoom control (bare viewer)', ok, detail);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}