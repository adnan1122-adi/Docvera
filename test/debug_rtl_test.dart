import 'dart:io';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

String? _name(CosObject? o) => o is CosName ? o.value : null;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerBundledEditorAssets();

  test('fingerprint chrome_ar fonts', () async {
    final bytes = File('/tmp/pdfedit/chrome_ar.pdf').readAsBytesSync();
    final doc = PdfDocument.open(bytes);
    final cos = doc.cos;
    final page = doc.page(0);
    final fonts = cos.resolve(page.resources['Font']);
    if (fonts is CosDictionary) {
      fonts.entries.forEach((name, obj) {
        final f = cos.resolve(obj);
        if (f is! CosDictionary) return;
        final subtype = _name(f['Subtype']) ?? '?';
        final enc = _name(f['Encoding']);
        final desc = cos.resolve(f['DescendantFonts']);
        var cidSub = '?', c2g = '?', fd = '?';
        if (desc is CosArray && desc.items.isNotEmpty) {
          final cid = cos.resolve(desc.items.first);
          if (cid is CosDictionary) {
            cidSub = _name(cid['Subtype']) ?? '?';
            final cg = cos.resolve(cid['CIDToGIDMap']);
            c2g = cg is CosName
                ? cg.value
                : (cg is CosStream ? 'stream' : '${cg.runtimeType}');
            final fdesc = cos.resolve(cid['FontDescriptor']);
            if (fdesc is CosDictionary) {
              fd = cos.resolve(fdesc['FontFile2']) is CosStream
                  ? 'FontFile2'
                  : 'none';
            }
          }
        }
        final toUni = cos.resolve(f['ToUnicode']) is CosStream;
        // ignore: avoid_print
        print('DBG | FONT $name subtype=$subtype enc=$enc cid=$cidSub '
            'c2g=$c2g toUni=$toUni file=$fd');
      });
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
