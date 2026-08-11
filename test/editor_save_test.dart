import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_editor/src/editor/editor_screen.dart';
import 'package:pdf_editor/src/models/recent_document.dart';
import 'package:pdf_editor/src/services/document_io.dart';
import 'package:pdf_editor/src/services/recent_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Uint8List> _makeDoc(int pages) async {
  final doc = pw.Document();
  for (var i = 0; i < pages; i++) {
    doc.addPage(pw.Page(
      pageFormat: pdf.PdfPageFormat.a4,
      build: (_) => pw.Text('PAGE ${i + 1}'),
    ));
  }
  return Uint8List.fromList(await doc.save());
}

/// Commits a small edit so the document becomes dirty.
void _editDoc(PdfEditingController editing) {
  editing.apply(
    (e) => e.addFreeText(0, PdfRect(60, 700, 300, 760), 'edited'),
  );
}

void _usePlatform(TargetPlatform platform) {
  debugDefaultTargetPlatformOverride = platform;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
}

/// Pumps EditorScreen as a pushed route so back navigation can be verified.
Future<void> _pumpEditorPushed(WidgetTester tester, EditorScreen editor) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => editor),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('primary Save over a recents-opened doc writes in place and '
      'clears the dirty state', (tester) async {
    _usePlatform(TargetPlatform.macOS);
    tester.view.physicalSize = const Size(1100, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final bytes = await _makeDoc(2);
      final editing = PdfEditingController(bytes);
      final store = RecentStore();
      final original = RecentDocument(
        name: 'contract.pdf',
        sizeBytes: bytes.length,
        lastOpened: DateTime.now(),
        path: '/app/pdfs/1-contract.pdf',
      );
      await store.upsert(original);

      String? savedPath;
      Uint8List? savedBytes;
      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
          title: 'contract.pdf',
          bytes: bytes,
          controller: editing,
          recent: original,
          recentStore: store,
          saveToPath: (path, b) async {
            savedPath = path;
            savedBytes = b;
          },
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Starts clean (opened from recents -> already on disk).
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Unsaved changes'), findsNothing);

      // An edit marks the document dirty.
      _editDoc(editing);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(find.text('Saved'), findsNothing);

      // Save writes to the existing app copy and clears the dirty state.
      await tester.tap(find.byKey(const ValueKey('editor-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(savedPath, '/app/pdfs/1-contract.pdf');
      expect(savedBytes, editing.bytes);
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Unsaved changes'), findsNothing);
      expect(find.text('Saved contract.pdf'), findsOneWidget);

      final recents = await store.load();
      expect(recents, hasLength(1));
      expect(recents.single.name, 'contract.pdf');
      expect(recents.single.sizeBytes, editing.bytes.length);

      editing.dispose();
    });
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Save As renames the document and keeps the original recent',
      (tester) async {
    _usePlatform(TargetPlatform.macOS);
    tester.view.physicalSize = const Size(1100, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final bytes = await _makeDoc(2);
      final editing = PdfEditingController(bytes);
      final store = RecentStore();
      final original = RecentDocument(
        name: 'report.pdf',
        sizeBytes: bytes.length,
        lastOpened: DateTime.now(),
        path: '/app/pdfs/2-report.pdf',
      );
      await store.upsert(original);

      String? suggestedName;
      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
          title: 'report.pdf',
          bytes: bytes,
          controller: editing,
          recent: original,
          recentStore: store,
          saveAsPdf: (b, suggested) async {
            suggestedName = suggested;
            return const PdfSaveOutcome(
              saved: true,
              path: '/Users/tester/Desktop/report-edited.pdf',
            );
          },
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      _editDoc(editing);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('editor-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save As'));
      await tester.pumpAndSettle();

      expect(suggestedName, 'report-edited.pdf');
      // The document is renamed to the new file.
      expect(find.text('report-edited.pdf'), findsOneWidget);
      expect(find.text('report.pdf'), findsNothing);
      // The original recent entry is untouched; the new file was added.
      final recents = await store.load();
      expect(recents.map((r) => r.name).toSet(),
          {'report.pdf', 'report-edited.pdf'});
      final renamed =
          recents.firstWhere((r) => r.name == 'report-edited.pdf');
      expect(renamed.path, '/Users/tester/Desktop/report-edited.pdf');
      final kept = recents.firstWhere((r) => r.name == 'report.pdf');
      expect(kept.path, '/app/pdfs/2-report.pdf');

      editing.dispose();
    });
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Save a Copy keeps the current document and adds the copy',
      (tester) async {
    _usePlatform(TargetPlatform.macOS);
    tester.view.physicalSize = const Size(1100, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final bytes = await _makeDoc(2);
      final editing = PdfEditingController(bytes);
      final store = RecentStore();
      final original = RecentDocument(
        name: 'report.pdf',
        sizeBytes: bytes.length,
        lastOpened: DateTime.now(),
        path: '/app/pdfs/2-report.pdf',
      );
      await store.upsert(original);

      String? suggestedName;
      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
          title: 'report.pdf',
          bytes: bytes,
          controller: editing,
          recent: original,
          recentStore: store,
          saveAsPdf: (b, suggested) async {
            suggestedName = suggested;
            return const PdfSaveOutcome(
              saved: true,
              path: '/Users/tester/Desktop/report-copy.pdf',
            );
          },
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      _editDoc(editing);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('editor-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save a Copy'));
      await tester.pumpAndSettle();

      expect(suggestedName, 'report-copy.pdf');
      // The current document keeps its title/location.
      expect(find.text('report.pdf'), findsOneWidget);
      // The copy was added to recents.
      final recents = await store.load();
      expect(recents.map((r) => r.name).toSet(),
          {'report.pdf', 'report-copy.pdf'});

      editing.dispose();
    });
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('primary Save on a fresh desktop doc falls back to Save As',
      (tester) async {
    _usePlatform(TargetPlatform.macOS);
    tester.view.physicalSize = const Size(1100, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final bytes = await _makeDoc(2);
      final editing = PdfEditingController(bytes);
      final store = RecentStore();

      String? suggestedName;
      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
          title: 'fresh.pdf',
          bytes: bytes,
          controller: editing,
          recentStore: store,
          saveAsPdf: (b, suggested) async {
            suggestedName = suggested;
            return const PdfSaveOutcome(
              saved: true,
              path: '/Users/tester/Desktop/fresh-edited.pdf',
            );
          },
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      _editDoc(editing);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('editor-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(suggestedName, 'fresh-edited.pdf');
      expect(find.text('fresh-edited.pdf'), findsOneWidget);
      expect(find.text('Saved fresh-edited.pdf'), findsOneWidget);

      final recents = await store.load();
      expect(recents.single.name, 'fresh-edited.pdf');

      editing.dispose();
    });
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('mobile primary Save keeps an in-app copy without a picker',
      (tester) async {
    _usePlatform(TargetPlatform.android);
    tester.view.physicalSize = const Size(1100, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final bytes = await _makeDoc(2);
      final editing = PdfEditingController(bytes);
      final store = RecentStore();

      String? persistedName;
      String? writtenPath;
      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
          title: 'mobile.pdf',
          bytes: bytes,
          controller: editing,
          recentStore: store,
          saveToPath: (path, b) async {
            writtenPath = path;
          },
          persistForRecents: (pdf) async {
            persistedName = pdf.name;
            return RecentDocument(
              name: pdf.name,
              sizeBytes: pdf.bytes.length,
              lastOpened: DateTime.now(),
              path: '/app/pdfs/3-mobile.pdf',
            );
          },
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      _editDoc(editing);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('editor-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(persistedName, 'mobile.pdf');
      expect(writtenPath, isNull);
      expect(find.text('Saved mobile.pdf'), findsOneWidget);
      expect(find.text('Unsaved changes'), findsNothing);

      final recents = await store.load();
      expect(recents.single.path, '/app/pdfs/3-mobile.pdf');

      editing.dispose();
    });
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('leave guard: Save on back persists then pops', (tester) async {
    _usePlatform(TargetPlatform.macOS);
    tester.view.physicalSize = const Size(1100, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final bytes = await _makeDoc(2);
      final editing = PdfEditingController(bytes);
      final store = RecentStore();
      final original = RecentDocument(
        name: 'report.pdf',
        sizeBytes: bytes.length,
        lastOpened: DateTime.now(),
        path: '/app/pdfs/2-report.pdf',
      );
      await store.upsert(original);

      String? savedPath;
      await _pumpEditorPushed(
        tester,
        EditorScreen(
          title: 'report.pdf',
          bytes: bytes,
          controller: editing,
          recent: original,
          recentStore: store,
          saveToPath: (path, b) async {
            savedPath = path;
          },
        ),
      );

      _editDoc(editing);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Save changes?'), findsOneWidget);

      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Save'),
      ));
      await tester.pumpAndSettle();

      expect(savedPath, '/app/pdfs/2-report.pdf');
      // Back on the launcher screen.
      expect(find.text('open'), findsOneWidget);

      editing.dispose();
    });
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('leave guard: Don\u2019t Save discards and pops', (tester) async {
    _usePlatform(TargetPlatform.macOS);
    tester.view.physicalSize = const Size(1100, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final bytes = await _makeDoc(2);
      final editing = PdfEditingController(bytes);
      final store = RecentStore();
      final original = RecentDocument(
        name: 'report.pdf',
        sizeBytes: bytes.length,
        lastOpened: DateTime.now(),
        path: '/app/pdfs/2-report.pdf',
      );
      await store.upsert(original);

      String? savedPath;
      await _pumpEditorPushed(
        tester,
        EditorScreen(
          title: 'report.pdf',
          bytes: bytes,
          controller: editing,
          recent: original,
          recentStore: store,
          saveToPath: (path, b) async {
            savedPath = path;
          },
        ),
      );

      _editDoc(editing);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Don't Save"));
      await tester.pumpAndSettle();

      expect(savedPath, isNull);
      expect(find.text('open'), findsOneWidget);

      editing.dispose();
    });
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('leave guard: Cancel stays in the editor', (tester) async {
    _usePlatform(TargetPlatform.macOS);
    tester.view.physicalSize = const Size(1100, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final bytes = await _makeDoc(2);
      final editing = PdfEditingController(bytes);
      final store = RecentStore();
      final original = RecentDocument(
        name: 'report.pdf',
        sizeBytes: bytes.length,
        lastOpened: DateTime.now(),
        path: '/app/pdfs/2-report.pdf',
      );
      await store.upsert(original);

      await _pumpEditorPushed(
        tester,
        EditorScreen(
          title: 'report.pdf',
          bytes: bytes,
          controller: editing,
          recent: original,
          recentStore: store,
          saveToPath: (path, b) async {},
        ),
      );

      _editDoc(editing);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Still in the editor, still dirty.
      expect(find.byType(EditorScreen), findsOneWidget);
      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(find.text('open'), findsNothing);

      editing.dispose();
    });
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('clean document pops without the guard dialog', (tester) async {
    _usePlatform(TargetPlatform.macOS);
    tester.view.physicalSize = const Size(1100, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final bytes = await _makeDoc(2);
      final editing = PdfEditingController(bytes);
      final store = RecentStore();
      final original = RecentDocument(
        name: 'report.pdf',
        sizeBytes: bytes.length,
        lastOpened: DateTime.now(),
        path: '/app/pdfs/2-report.pdf',
      );
      await store.upsert(original);

      await _pumpEditorPushed(
        tester,
        EditorScreen(
          title: 'report.pdf',
          bytes: bytes,
          controller: editing,
          recent: original,
          recentStore: store,
        ),
      );

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Save changes?'), findsNothing);
      expect(find.text('open'), findsOneWidget);

      editing.dispose();
    });
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Share hands the current bytes and name to the platform seam',
      (tester) async {
    _usePlatform(TargetPlatform.macOS);
    tester.view.physicalSize = const Size(1100, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final bytes = await _makeDoc(2);
      final editing = PdfEditingController(bytes);

      Uint8List? sharedBytes;
      String? sharedName;
      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
          title: 'report.pdf',
          bytes: bytes,
          controller: editing,
          sharePdf: (b, name) async {
            sharedBytes = b;
            sharedName = name;
          },
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      _editDoc(editing);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('editor-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(sharedName, 'report.pdf');
      expect(sharedBytes, editing.bytes);

      editing.dispose();
    });
    debugDefaultTargetPlatformOverride = null;
  });
}
