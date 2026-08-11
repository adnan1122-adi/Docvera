import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import '../models/recent_document.dart';
import 'recent_store.dart';
import 'platform/document_io_native.dart'
    if (dart.library.js_interop) 'platform/document_io_web.dart'
    as platform;

/// The result of choosing a PDF to open.
class PickedPdf {
  const PickedPdf({
    required this.name,
    required this.bytes,
  });

  final String name;
  final Uint8List bytes;

  int get sizeBytes => bytes.length;
}

/// Where a "Save As" / "Save a Copy" write landed.
class PdfSaveOutcome {
  const PdfSaveOutcome({required this.saved, this.path});

  /// False when the user cancelled (desktop save dialog).
  final bool saved;

  /// The absolute path of the file when the platform reports one (desktop
  /// save dialog); null on the web (browser download) and mobile (the caller
  /// persists into app storage).
  final String? path;
}

/// Opening a PDF: the native file picker (all platforms), reading a stored
/// recent copy, saving, and sharing.
abstract final class DocumentIo {
  static bool get isDesktopPlatform {
    final p = defaultTargetPlatform;
    return p == TargetPlatform.macOS ||
        p == TargetPlatform.windows ||
        p == TargetPlatform.linux;
  }

  static bool get isMobilePlatform {
    final p = defaultTargetPlatform;
    return p == TargetPlatform.iOS || p == TargetPlatform.android;
  }

  /// Opens the native file dialog filtered to PDFs and reads the chosen
  /// file. Returns null when the user cancels.
  static Future<PickedPdf?> pickAndRead() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    final bytes = await _bytesOf(file);
    if (bytes == null) return null;
    return PickedPdf(name: file.name, bytes: bytes);
  }

  static Future<Uint8List?> _bytesOf(PlatformFile file) async {
    final inMemory = file.bytes;
    if (inMemory != null && inMemory.isNotEmpty) return inMemory;
    final path = file.path;
    if (path != null && path.isNotEmpty && !kIsWeb) {
      return platform.PlatformDocumentIo.readPath(path);
    }
    return null;
  }

  /// Reads a recent document back into memory. Throws when the stored copy
  /// is gone (returned copy was deleted).
  static Future<PickedPdf> loadRecent(RecentDocument doc) async {
    if (doc.path != null && !kIsWeb) {
      final bytes = await platform.PlatformDocumentIo.readPath(doc.path!);
      return PickedPdf(name: doc.name, bytes: bytes);
    }
    if (doc.base64 != null) {
      return PickedPdf(
        name: doc.name,
        bytes: base64Decode(doc.base64!),
      );
    }
    throw StateError('Recent copy is not available.');
  }

  /// Makes an opened document available again later: a copy on disk on
  /// native, inline base64 on the web (capped to protect localStorage).
  static Future<RecentDocument> persistForRecents(
      PickedPdf pdf) async {
    if (kIsWeb) {
      final embedded = pdf.sizeBytes <= RecentStore.embeddedByteCap
          ? base64Encode(pdf.bytes)
          : null;
      return RecentDocument(
        name: pdf.name,
        sizeBytes: pdf.sizeBytes,
        lastOpened: DateTime.now(),
        base64: embedded,
      );
    }
    final path = await platform.PlatformDocumentIo.persistCopy(
        pdf.bytes, pdf.name);
    return RecentDocument(
      name: pdf.name,
      sizeBytes: pdf.sizeBytes,
      lastOpened: DateTime.now(),
      path: path,
    );
  }

  /// Exports [bytes]. On desktop and the web this shows a save dialog /
  /// triggers a download; on mobile it persists a copy and opens the share
  /// sheet. Returns false if the user cancels on desktop.
  static Future<bool> savePdf(Uint8List bytes, String suggestedName) async {
    if (!kIsWeb && isDesktopPlatform) {
      final path = await FilePicker.platform.saveFile(
        fileName: suggestedName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      return path != null && path.isNotEmpty;
    }
    if (kIsWeb) {
      await FilePicker.platform.saveFile(
        fileName: suggestedName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      return true;
    }
    // Mobile: no save dialog - share the file instead.
    await sharePdf(bytes, suggestedName);
    return true;
  }

  /// "Save As" / "Save a Copy": choose a filename and (where supported) a
  /// location. On desktop this is the native save dialog; on the web it
  /// triggers a browser download; on mobile there is no location picker, so
  /// the caller keeps the bytes in app storage under the chosen name.
  ///
  /// Returns [PdfSaveOutcome.saved] == false only when the user cancels the
  /// desktop dialog.
  static Future<PdfSaveOutcome> saveAsPdf(
      Uint8List bytes, String suggestedName) async {
    if (!kIsWeb && isDesktopPlatform) {
      final path = await FilePicker.platform.saveFile(
        fileName: suggestedName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (path == null || path.isEmpty) {
        return const PdfSaveOutcome(saved: false);
      }
      return PdfSaveOutcome(saved: true, path: path);
    }
    if (kIsWeb) {
      await FilePicker.platform.saveFile(
        fileName: suggestedName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      return const PdfSaveOutcome(saved: true);
    }
    return const PdfSaveOutcome(saved: true);
  }

  /// Overwrites [bytes] into an existing file at [path].
  static Future<void> saveToPath(String path, Uint8List bytes) =>
      platform.PlatformDocumentIo.writeToPath(path, bytes);

  /// Best-effort removal of a temporary file (native only).
  static Future<void> deleteTempFile(String path) async {
    if (kIsWeb) return;
    await platform.PlatformDocumentIo.deleteFile(path);
  }

  /// Shares [bytes] through the OS share sheet (native only). The temporary
  /// file handed to the OS is removed afterwards, best-effort.
  static Future<void> sharePdf(Uint8List bytes, String name) async {
    if (kIsWeb) return;
    final path = await platform.PlatformDocumentIo.writeTemp(bytes, name);
    try {
      await Share.shareXFiles([
        XFile(path, mimeType: 'application/pdf', name: name),
      ]);
    } finally {
      // Give the share sheet a moment to open the file before removing it;
      // failures are ignored.
      unawaited(Future.delayed(
        const Duration(seconds: 6),
        () => platform.PlatformDocumentIo.deleteFile(path),
      ));
    }
  }

  /// Picks an image for image annotations.
  static Future<Uint8List?> pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.single.bytes;
  }
}
