import 'dart:typed_data';

import 'save_target_stub.dart'
    if (dart.library.io) 'save_target_io.dart' as impl;

/// Where a saved PDF lives after [persistPdf].
///
/// - Native: a real file; [path] is the absolute path and [loadPdf] re-reads
///   the bytes from disk (the strictest "reopen the saved file" check).
/// - Web: browsers cannot read files back from a download, so the bytes are
///   kept in memory in [bytes] and a download is triggered for the user.
class SavedTarget {
  const SavedTarget({required this.label, this.bytes, this.path});

  /// Human-readable description of where the file went.
  final String label;

  /// In-memory copy of the saved bytes (web).
  final Uint8List? bytes;

  /// Absolute file path (native).
  final String? path;
}

/// Persists [bytes] as a PDF, returning a [SavedTarget] describing where.
Future<SavedTarget> persistPdf(Uint8List bytes, String prefix) =>
    impl.persistPdf(bytes, prefix);

/// Loads back the bytes of a previously saved [target].
Future<Uint8List> loadPdf(SavedTarget target) => impl.loadPdf(target);