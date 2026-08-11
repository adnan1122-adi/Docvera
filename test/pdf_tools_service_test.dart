import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_editor/src/services/document_io.dart';
import 'package:pdf_editor/src/tools/page_range.dart';
import 'package:pdf_editor/src/tools/pdf_merge_service.dart';
import 'package:pdf_editor/src/tools/pdf_split_service.dart';
import 'package:pdf_editor/src/tools/pdf_tool_util.dart';

/// Builds an in-memory [pages]-page PDF whose page N contains the literal
/// marker text `{marker}{N}` (so page order is checkable via content bytes).
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

String _text(PdfDocument doc, int pageIndex) =>
    String.fromCharCodes(doc.page(pageIndex).contentBytes());

String _textOf(Uint8List bytes, int pageIndex) =>
    _text(PdfDocument.open(bytes), pageIndex);

void main() {
  const mergeService = PdfMergeService();
  const splitService = PdfSplitService();

  group('PdfMergeService', () {
    test('merges two PDFs into one with the right page count', () async {
      final a = await _makeDoc(2, marker: 'A');
      final b = await _makeDoc(3, marker: 'B');
      final result = mergeService.merge([
        PickedPdf(name: 'a.pdf', bytes: a),
        PickedPdf(name: 'b.pdf', bytes: b),
      ]);

      expect(result.pageCount, 5);
      final doc = PdfDocument.open(result.bytes);
      expect(doc.pageCount, 5);
      expect(_text(doc, 0), contains('A1'));
      expect(_text(doc, 1), contains('A2'));
      expect(_text(doc, 2), contains('B1'));
    });

    test('merges three PDFs in the given order', () async {
      final a = await _makeDoc(1, marker: 'A');
      final b = await _makeDoc(1, marker: 'B');
      final c = await _makeDoc(1, marker: 'C');
      final result = mergeService.merge([
        PickedPdf(name: 'b.pdf', bytes: b),
        PickedPdf(name: 'c.pdf', bytes: c),
        PickedPdf(name: 'a.pdf', bytes: a),
      ]);

      expect(result.pageCount, 3);
      expect(_textOf(result.bytes, 0), contains('B1'));
      expect(_textOf(result.bytes, 1), contains('C1'));
      expect(_textOf(result.bytes, 2), contains('A1'));
    });

    test('output order matches a reordered input list', () async {
      final a = await _makeDoc(2, marker: 'A');
      final b = await _makeDoc(1, marker: 'B');
      // Start a, b then reorder to b, a.
      final result = mergeService.merge([
        PickedPdf(name: 'b.pdf', bytes: b),
        PickedPdf(name: 'a.pdf', bytes: a),
      ]);
      expect(_textOf(result.bytes, 0), contains('B1'));
      expect(_textOf(result.bytes, 1), contains('A1'));
      expect(_textOf(result.bytes, 2), contains('A2'));
    });

    test('duplicate filenames merge without conflict', () async {
      final a = await _makeDoc(1, marker: 'A');
      final b = await _makeDoc(1, marker: 'B');
      final result = mergeService.merge([
        PickedPdf(name: 'same.pdf', bytes: a),
        PickedPdf(name: 'same.pdf', bytes: b),
      ]);
      expect(result.pageCount, 2);
      expect(_textOf(result.bytes, 0), contains('A1'));
      expect(_textOf(result.bytes, 1), contains('B1'));
    });

    test('original files remain unchanged', () async {
      final a = await _makeDoc(2, marker: 'A');
      final b = await _makeDoc(1, marker: 'B');
      final copyA = Uint8List.fromList(a);
      final copyB = Uint8List.fromList(b);

      mergeService.merge([
        PickedPdf(name: 'a.pdf', bytes: a),
        PickedPdf(name: 'b.pdf', bytes: b),
      ]);

      expect(a, copyA);
      expect(b, copyB);
      expect(PdfDocument.open(a).pageCount, 2);
      expect(PdfDocument.open(b).pageCount, 1);
    });

    test('rejects fewer than two PDFs', () async {
      final a = await _makeDoc(1, marker: 'A');
      expect(
        () => mergeService.merge([PickedPdf(name: 'a.pdf', bytes: a)]),
        throwsA(isA<PdfToolException>()),
      );
    });

    test('rejects a damaged / empty file', () async {
      final a = await _makeDoc(1, marker: 'A');
      final broken = PickedPdf(
          name: 'broken.pdf', bytes: Uint8List.fromList([1, 2, 3]));
      expect(
        () => mergeService.merge([
          PickedPdf(name: 'a.pdf', bytes: a),
          broken,
        ]),
        throwsA(isA<PdfToolException>()
            .having((e) => e.message, 'message', contains('broken.pdf'))),
      );
    });

    test('rejects an empty byte file', () async {
      final a = await _makeDoc(1, marker: 'A');
      expect(
        () => mergeService.merge([
          PickedPdf(name: 'a.pdf', bytes: a),
          PickedPdf(name: 'empty.pdf', bytes: Uint8List(0)),
        ]),
        throwsA(isA<PdfToolException>()),
      );
    });
  });

  group('PdfSplitService.extractPages', () {
    test('extracts selected pages in selection order', () async {
      final doc = await _makeDoc(6, marker: 'P');
      final part = splitService.extractPages(doc, 'original.pdf', [2, 4, 6]);

      expect(part.name, 'original_pages_2-4-6.pdf');
      expect(part.label, 'pages 2-4-6');
      expect(part.pageCount, 3);
      final out = PdfDocument.open(part.bytes);
      expect(out.pageCount, 3);
      expect(_text(out, 0), contains('P2'));
      expect(_text(out, 1), contains('P4'));
      expect(_text(out, 2), contains('P6'));
    });

    test('extract can reorder pages (reverse selection)', () async {
      final doc = await _makeDoc(3, marker: 'P');
      final part = splitService.extractPages(doc, 'original.pdf', [3, 1]);
      final out = PdfDocument.open(part.bytes);
      expect(out.pageCount, 2);
      expect(_text(out, 0), contains('P3'));
      expect(_text(out, 1), contains('P1'));
    });

    test('extract keeps the original untouched', () async {
      final doc = await _makeDoc(4, marker: 'P');
      final copy = Uint8List.fromList(doc);
      splitService.extractPages(doc, 'original.pdf', [1, 4]);
      expect(doc, copy);
      expect(PdfDocument.open(doc).pageCount, 4);
    });

    test('rejects an empty selection', () async {
      final doc = await _makeDoc(3, marker: 'P');
      expect(
        () => splitService.extractPages(doc, 'original.pdf', []),
        throwsA(isA<PdfToolException>()),
      );
    });

    test('rejects an out-of-range page', () async {
      final doc = await _makeDoc(3, marker: 'P');
      expect(
        () => splitService.extractPages(doc, 'original.pdf', [4]),
        throwsA(isA<PdfToolException>().having(
            (e) => e.message, 'message', contains('out of range'))),
      );
    });

    test('rejects a damaged source', () {
      expect(
        () => splitService.extractPages(
            Uint8List.fromList([1, 2, 3]), 'original.pdf', [1]),
        throwsA(isA<PdfToolException>()),
      );
    });
  });

  group('PdfSplitService.splitByRanges', () {
    test('splits into one PDF per range', () async {
      final doc = await _makeDoc(10, marker: 'P');
      final parts = splitService.splitByRanges(
          doc, 'original.pdf', parsePageRanges('1-3, 5-7, 10'));

      expect(parts.length, 3);
      expect(parts[0].name, 'original_pages_1-3.pdf');
      expect(parts[0].pageCount, 3);
      expect(parts[1].name, 'original_pages_5-7.pdf');
      expect(parts[2].name, 'original_pages_10.pdf');
      expect(parts[2].pageCount, 1);

      final first = PdfDocument.open(parts[0].bytes);
      expect(first.pageCount, 3);
      expect(_text(first, 0), contains('P1'));
      expect(_text(first, 2), contains('P3'));
      final last = PdfDocument.open(parts[2].bytes);
      expect(_text(last, 0), contains('P10'));
    });

    test('multiple ranges produce multiple standalone files', () async {
      final doc = await _makeDoc(8, marker: 'P');
      final parts = splitService.splitByRanges(
          doc, 'original.pdf', parsePageRanges('1-1, 8-8'));
      expect(parts.length, 2);
      for (final part in parts) {
        expect(PdfDocument.open(part.bytes).pageCount, 1);
      }
    });

    test('rejects a range beyond the document', () async {
      final doc = await _makeDoc(5, marker: 'P');
      expect(
        () => splitService.splitByRanges(doc, 'original.pdf', [const PageRange(1, 6)]),
        throwsA(isA<PdfToolException>().having(
            (e) => e.message, 'message', contains('beyond this document'))),
      );
    });

    test('leaves the original unchanged', () async {
      final doc = await _makeDoc(5, marker: 'P');
      final copy = Uint8List.fromList(doc);
      splitService.splitByRanges(doc, 'original.pdf', [const PageRange(2, 3)]);
      expect(doc, copy);
    });
  });

  group('PdfSplitService.splitEvery', () {
    test('splits a 10-page PDF every 2 pages into 5 parts', () async {
      final doc = await _makeDoc(10, marker: 'P');
      final parts = splitService.splitEvery(doc, 'original.pdf', 2);

      expect(parts.length, 5);
      expect(parts[0].name, 'original_part_1.pdf');
      expect(parts[0].pageCount, 2);
      expect(parts[4].name, 'original_part_5.pdf');
      expect(parts[4].pageCount, 2);

      final first = PdfDocument.open(parts[0].bytes);
      expect(_text(first, 0), contains('P1'));
      final last = PdfDocument.open(parts[4].bytes);
      expect(_text(last, 0), contains('P9'));
      expect(_text(last, 1), contains('P10'));
    });

    test('produces a short final part when pages do not divide evenly',
        () async {
      final doc = await _makeDoc(10, marker: 'P');
      final parts = splitService.splitEvery(doc, 'original.pdf', 3);
      expect(parts.length, 4);
      expect(parts[0].pageCount, 3);
      expect(parts[3].pageCount, 1);
      expect(_text(PdfDocument.open(parts[3].bytes), 0), contains('P10'));
    });

    test('splitting by 1 keeps every page as its own file', () async {
      final doc = await _makeDoc(3, marker: 'P');
      final parts = splitService.splitEvery(doc, 'original.pdf', 1);
      expect(parts.length, 3);
      for (var i = 0; i < 3; i++) {
        expect(parts[i].pageCount, 1);
        expect(_text(PdfDocument.open(parts[i].bytes), 0), contains('P${i + 1}'));
      }
    });

    test('rejects an invalid split size', () async {
      final doc = await _makeDoc(4, marker: 'P');
      expect(() => splitService.splitEvery(doc, 'original.pdf', 0),
          throwsA(isA<PdfToolException>()));
      expect(() => splitService.splitEvery(doc, 'original.pdf', 5),
          throwsA(isA<PdfToolException>()));
    });

    test('leaves the original unchanged', () async {
      final doc = await _makeDoc(4, marker: 'P');
      final copy = Uint8List.fromList(doc);
      splitService.splitEvery(doc, 'original.pdf', 2);
      expect(doc, copy);
    });
  });

  group('parsePageRanges', () {
    test('parses numbers and ranges', () {
      expect(parsePageRanges('1-3, 5-7, 10'),
          [const PageRange(1, 3), const PageRange(5, 7), const PageRange(10, 10)]);
    });

    test('accepts a single page and whitespace separation', () {
      expect(parsePageRanges('4'), [const PageRange(4, 4)]);
      expect(parsePageRanges('1-2 4'),
          [const PageRange(1, 2), const PageRange(4, 4)]);
    });

    test('rejects a reversed range', () {
      expect(() => parsePageRanges('3-1'), throwsFormatException);
    });

    test('rejects a non-range token', () {
      expect(() => parsePageRanges('abc'), throwsFormatException);
      expect(() => parsePageRanges('1-a'), throwsFormatException);
    });

    test('rejects empty input', () {
      expect(() => parsePageRanges(''), throwsFormatException);
      expect(() => parsePageRanges('  , '), throwsFormatException);
    });

    test('rejects duplicate ranges', () {
      expect(() => parsePageRanges('1-3, 1-3'), throwsFormatException);
    });

    test('rejects page zero', () {
      expect(() => parsePageRanges('0-2'), throwsFormatException);
    });
  });
}
