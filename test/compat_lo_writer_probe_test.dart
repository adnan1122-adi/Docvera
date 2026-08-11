import 'dart:io';

import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

// ignore_for_file: avoid_print

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerBundledEditorAssets();

  test('lo writer probe', () {
    for (final name in [
      'lo_writer_en',
      'lo_writer_ar',
      'lo_writer_en_ar',
    ]) {
      final bytes = File(
              '/tmp/pdfedit/compat_lo/$name.pdf')
          .readAsBytesSync();
      final doc = PdfDocument.open(bytes);
      final cos = doc.cos;
      final fonts = cos.resolve(doc.page(0).resources['Font']);
      final names = <String>[];
      if (fonts is CosDictionary) {
        fonts.entries.forEach((k, v) {
          final f = cos.resolve(v);
          if (f is CosDictionary) {
            final sub = f['Subtype'] is CosName
                ? (f['Subtype'] as CosName).value
                : '?';
            final base = f['BaseFont'] is CosName
                ? (f['BaseFont'] as CosName).value
                : '?';
            names.add('$k:$sub($base)');
          }
        });
      }
      final text = PdfTextExtractor.extract(doc, 0).text;
      print('CP | $name | fonts=${names.join(',')}');
      print('CP | $name | text=${text.replaceAll('\n', '⏎')}');
      print('CP | $name | size=${bytes.length}');
    }
  });
}
