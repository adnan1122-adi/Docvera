import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import 'save_target.dart';

/// Web: the browser can only hand the bytes back via a download, so the
/// bytes are kept in memory and a PDF download is triggered for the user.
Future<SavedTarget> persistPdf(Uint8List bytes, String prefix) async {
  final name = '$prefix.pdf';
  await XFile.fromData(bytes, mimeType: 'application/pdf', name: name)
      .saveTo(name);
  return SavedTarget(label: 'browser download ($name)', bytes: bytes);
}

Future<Uint8List> loadPdf(SavedTarget target) async => target.bytes!;