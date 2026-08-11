import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'save_target.dart';

/// Native: writes the PDF into the app documents directory and keeps the
/// absolute path, so "reopen the saved file" can re-read it from disk.
Future<SavedTarget> persistPdf(Uint8List bytes, String prefix) async {
  final dir = await getApplicationDocumentsDirectory();
  final path =
      '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.pdf';
  await File(path).writeAsBytes(bytes);
  return SavedTarget(label: path, path: path);
}

Future<Uint8List> loadPdf(SavedTarget target) async =>
    File(target.path!).readAsBytes();