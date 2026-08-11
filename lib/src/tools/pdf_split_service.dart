import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';

import 'page_range.dart';
import 'pdf_tool_util.dart';

/// One output file produced by a split operation.
class SplitPart {
  const SplitPart({
    required this.name,
    required this.bytes,
    required this.pageCount,
    required this.label,
  });

  final String name;
  final Uint8List bytes;
  final int pageCount;

  /// Human label like "pages 1-3" or "part 2 of 5".
  final String label;
}

/// Splits a PDF into one or more standalone PDFs without modifying the
/// original. Uses the engine's page extraction (a deep copy), so text,
/// images, page dimensions/orientation, and existing annotations are kept.
/// Everything runs locally on the device.
class PdfSplitService {
  const PdfSplitService();

  /// Extracts the given 1-based page numbers, in [pages] order, into a single
  /// new PDF named `original_pages_2-4-6.pdf`.
  SplitPart extractPages(Uint8List bytes, String baseName, List<int> pages) {
    if (pages.isEmpty) {
      throw PdfToolException('Select at least one page to extract.');
    }
    return _run(bytes, baseName, (doc) {
      final pageCount = doc.pageCount;
      final indices = pages.map((p) => _indexOf(p, pageCount)).toList();
      final out = doc.extractPages(indices);
      final key = pages.join('-');
      return SplitPart(
        name: '${pdfStem(baseName)}_pages_$key.pdf',
        bytes: Uint8List.fromList(out),
        pageCount: pages.length,
        label: 'pages $key',
      );
    });
  }

  /// Splits into one PDF per range, e.g. `original_pages_1-3.pdf`.
  List<SplitPart> splitByRanges(
      Uint8List bytes, String baseName, List<PageRange> ranges) {
    if (ranges.isEmpty) {
      throw PdfToolException('Enter at least one page or range.');
    }
    return _run(bytes, baseName, (doc) {
      final pageCount = doc.pageCount;
      final parts = <SplitPart>[];
      for (final range in ranges) {
        if (range.end > pageCount) {
          throw PdfToolException('Range $range is beyond this document '
              '($pageCount page${pageCount == 1 ? '' : 's'}).');
        }
        final out = doc.extractPageRange(range.start - 1, range.end - 1);
        parts.add(SplitPart(
          name: '${pdfStem(baseName)}_pages_$range.pdf',
          bytes: Uint8List.fromList(out),
          pageCount: range.length,
          label: 'pages $range',
        ));
      }
      return parts;
    });
  }

  /// Splits into consecutive parts of [every] pages, e.g.
  /// `original_part_1.pdf`, `original_part_2.pdf`.
  List<SplitPart> splitEvery(Uint8List bytes, String baseName, int every) {
    return _run(bytes, baseName, (doc) {
      final pageCount = doc.pageCount;
      if (every < 1 || every > pageCount) {
        throw PdfToolException(
            'Split size must be between 1 and $pageCount pages.');
      }
      final parts = <SplitPart>[];
      var start = 1;
      var part = 1;
      while (start <= pageCount) {
        final end = (start + every - 1) > pageCount
            ? pageCount
            : (start + every - 1);
        final out = doc.extractPageRange(start - 1, end - 1);
        parts.add(SplitPart(
          name: '${pdfStem(baseName)}_part_$part.pdf',
          bytes: Uint8List.fromList(out),
          pageCount: end - start + 1,
          label: 'pages $start-$end',
        ));
        start = end + 1;
        part += 1;
      }
      return parts;
    });
  }

  int _indexOf(int page, int pageCount) {
    if (page < 1 || page > pageCount) {
      throw PdfToolException('Page $page is out of range '
          '(this document has $pageCount page${pageCount == 1 ? '' : 's'}).');
    }
    return page - 1;
  }

  T _run<T>(
      Uint8List bytes, String baseName, T Function(PdfDocument doc) action) {
    try {
      return action(PdfDocument.open(bytes));
    } on PdfToolException {
      rethrow;
    } catch (e) {
      throw PdfToolException(
        'Could not open "$baseName". It may be damaged, empty, or '
        'password-protected.',
        cause: e,
      );
    }
  }
}
