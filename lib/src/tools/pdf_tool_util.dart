import 'dart:typed_data';

import '../services/document_io.dart';

/// File-picking seam for widget tests: mirrors [DocumentIo.pickAndRead].
typedef PickPdf = Future<PickedPdf?> Function();

/// Save seam: mirrors [DocumentIo.savePdf] (returns false when cancelled).
typedef SavePdf = Future<bool> Function(Uint8List bytes, String name);

/// Share seam: mirrors [DocumentIo.sharePdf] (a no-op on the web).
typedef SharePdf = Future<void> Function(Uint8List bytes, String name);

/// A problem that prevented a document-tool operation. [message] is safe to
/// show directly to the user.
class PdfToolException implements Exception {
  PdfToolException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// The base name without a trailing ".pdf" extension (case-insensitive).
String pdfStem(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.pdf') ? name.substring(0, name.length - 4) : name;
}

/// Makes [name] safe to use as a file name on every platform.
String sanitizeFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
  return cleaned.trim().isEmpty ? 'document' : cleaned.trim();
}

/// Ensures [name] is a sanitized name ending in ".pdf".
String ensurePdfExtension(String name) {
  final trimmed = sanitizeFileName(name);
  return trimmed.toLowerCase().endsWith('.pdf') ? trimmed : '$trimmed.pdf';
}

/// Human-readable byte size.
String formatBytes(int bytes) {
  if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}
