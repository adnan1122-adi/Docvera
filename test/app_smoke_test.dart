import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_editor/main.dart';
import 'package:pdf_editor/src/models/recent_document.dart';
import 'package:pdf_editor/src/services/recent_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('upsert on an empty store does not throw (unmodifiable list)', () async {
    SharedPreferences.setMockInitialValues({});
    final store = RecentStore();
    await store.upsert(RecentDocument(
      name: 'a.pdf',
      sizeBytes: 1,
      lastOpened: DateTime.now(),
    ));
    final list = await store.load();
    expect(list.length, 1);
    expect(list.first.name, 'a.pdf');
  });

  test('upsert deduplicates by name+path and moves to the front', () async {
    SharedPreferences.setMockInitialValues({});
    final store = RecentStore();
    final d1 = RecentDocument(
        name: 'a.pdf', sizeBytes: 1, lastOpened: DateTime.now());
    final d2 = RecentDocument(
        name: 'a.pdf', sizeBytes: 2, lastOpened: DateTime.now());
    await store.upsert(d1);
    await store.upsert(d2);
    final list = await store.load();
    expect(list.length, 1);
    expect(list.first.sizeBytes, 2); // the newest copy wins
  });

  test('recents are capped at maxEntries (oldest dropped)', () async {
    SharedPreferences.setMockInitialValues({});
    final store = RecentStore();
    for (var i = 0; i < RecentStore.maxEntries + 5; i++) {
      await store.upsert(RecentDocument(
          name: 'doc-$i.pdf', sizeBytes: i, lastOpened: DateTime.now()));
    }
    final list = await store.load();
    expect(list.length, RecentStore.maxEntries);
    expect(list.first.name, 'doc-${RecentStore.maxEntries + 4}.pdf');
  });

  test('remove deletes a matching entry', () async {
    SharedPreferences.setMockInitialValues({});
    final store = RecentStore();
    final a = RecentDocument(
        name: 'a.pdf', sizeBytes: 1, lastOpened: DateTime.now());
    final b = RecentDocument(
        name: 'b.pdf', sizeBytes: 1, lastOpened: DateTime.now());
    await store.upsert(a);
    await store.upsert(b);
    await store.remove(a);
    final list = await store.load();
    expect(list.length, 1);
    expect(list.first.name, 'b.pdf');
  });

  test('corrupt stored JSON recovers to an empty list', () async {
    SharedPreferences.setMockInitialValues(
        {'pdf_editor.recent_documents.v1': 'not-json{{{'});
    final store = RecentStore();
    final list = await store.load();
    expect(list, isEmpty);
  });

  testWidgets('home screen renders brand, actions and empty recents',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PdfEditorApp());
    await tester.pumpAndSettle();

    expect(find.text('Docvera PDF Editor'), findsOneWidget);
    expect(find.text('Open PDF'), findsOneWidget);
    expect(find.text('Recent documents'), findsOneWidget);
    expect(find.text('No recent documents yet'), findsOneWidget);
  });

  testWidgets('home screen shows PDF Tools and opens Merge PDF', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PdfEditorApp());
    await tester.pumpAndSettle();

    expect(find.text('PDF Tools'), findsOneWidget);
    expect(find.text('Merge PDF'), findsOneWidget);
    expect(find.text('Split PDF'), findsOneWidget);

    await tester.tap(find.text('Merge PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Add at least two PDFs, then arrange and merge them.'),
        findsOneWidget);
    expect(find.text('Merge PDFs'), findsOneWidget);
  });

  testWidgets('home screen fits a narrow phone viewport', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PdfEditorApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('PDF Tools'), findsOneWidget);
    expect(find.text('Merge PDF'), findsOneWidget);
    expect(find.text('Split PDF'), findsOneWidget);
  });

  testWidgets('recents list renders persisted documents', (tester) async {
    SharedPreferences.setMockInitialValues({
      'pdf_editor.recent_documents.v1':
          '[{"name":"report.pdf","sizeBytes":2048,'
              '"lastOpened":1780000000000,"path":null,"base64":null}]',
    });
    await tester.pumpWidget(const PdfEditorApp());
    await tester.pumpAndSettle();

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.textContaining('2 KB'), findsOneWidget);
  });
}
