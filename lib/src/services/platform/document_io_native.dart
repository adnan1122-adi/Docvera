import 'dart:io' as io;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Native (dart:io) file operations. Not part of the web build - see
/// [document_io_web.dart].
abstract final class PlatformDocumentIo {
  /// Copies [bytes] into the app documents directory under `pdfs/` and
  /// returns the absolute path, or null when the platform cannot store files
  /// (web keeps inline base64 instead).
  static Future<String?> persistCopy(Uint8List bytes, String name) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = io.Directory('${docs.path}/pdfs');
    await dir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = io.File('${dir.path}/$stamp-${safeName(name)}');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<Uint8List> readPath(String path) =>
      io.File(path).readAsBytes();

  /// Overwrites [bytes] into an existing file (used to save a document back
  /// to its current location, e.g. an in-app copy or a desktop file the user
  /// picked). Creates the parent directory if it is missing.
  static Future<void> writeToPath(String path, Uint8List bytes) async {
    final file = io.File(path);
    final parent = file.parent;
    if (!(await parent.exists())) {
      await parent.create(recursive: true);
    }
    await file.writeAsBytes(bytes, flush: true);
  }

  /// Best-effort removal of a temporary file (ignores failures).
  static Future<void> deleteFile(String path) async {
    try {
      final file = io.File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Nothing sensible to do - the OS will reap temp files eventually.
    }
  }

  /// Writes [bytes] to a temporary file and returns its path - used to hand
  /// the OS a real file for the share sheet.
  static Future<String> writeTemp(Uint8List bytes, String name) async {
    final dir = await getTemporaryDirectory();
    final file = io.File('${dir.path}/${safeName(name)}');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static String safeName(String name) =>
      name.replaceAll(RegExp(r'[^\w.\- ]'), '_');
}
