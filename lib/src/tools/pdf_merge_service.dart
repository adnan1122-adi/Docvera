import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';

import '../services/document_io.dart';
import 'pdf_tool_util.dart';

/// The result of a successful merge: the new PDF's bytes.
class PdfMergeResult {
  const PdfMergeResult({required this.bytes, required this.pageCount});

  final Uint8List bytes;
  final int pageCount;
}

/// Merges multiple PDFs into a single PDF without modifying the sources.
///
/// The engine deep-copies every page (content streams, resources, fonts,
/// images, annotations) into the destination document, so the source files
/// are never touched and are not rasterized. Processing stays entirely on
/// the device.
class PdfMergeService {
  const PdfMergeService();

  /// A merge needs at least this many PDFs.
  static const int minimumSources = 2;

  /// Merges [sources] in list order. The output follows exactly that order.
  ///
  /// Throws [PdfToolException] with a user-friendly message when fewer than
  /// two PDFs are given, a file cannot be read (damaged, empty, or
  /// password-protected), or the engine cannot perform the merge.
  PdfMergeResult merge(List<PickedPdf> sources) {
    if (sources.length < minimumSources) {
      throw PdfToolException('Select at least $minimumSources PDFs to merge.');
    }
    final docs = <PdfDocument>[];
    try {
      for (final source in sources) {
        final doc = _open(source);
        if (doc.pageCount == 0) {
          throw PdfToolException('"${source.name}" contains no pages.');
        }
        docs.add(doc);
      }
      final destination = docs.first;
      final editor = PdfEditor(destination);
      for (var i = 1; i < docs.length; i++) {
        editor.appendPagesFrom(docs[i]);
      }
      final bytes = Uint8List.fromList(editor.save());
      return PdfMergeResult(bytes: bytes, pageCount: editor.document.pageCount);
    } on PdfToolException {
      rethrow;
    } catch (e) {
      throw PdfToolException('Could not merge the PDFs: $e', cause: e);
    }
  }

  PdfDocument _open(PickedPdf source) {
    try {
      return PdfDocument.open(source.bytes);
    } catch (e) {
      throw PdfToolException(
        'Could not read "${source.name}". It may be damaged, empty, or '
        'password-protected.',
        cause: e,
      );
    }
  }
}
