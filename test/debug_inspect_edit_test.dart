import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerBundledEditorAssets();

  test('inspect identity & longer extraction after RTL edit', () async {
    final bytes = File('/tmp/pdfedit/chrome_ar.pdf').readAsBytesSync();
    final fallbacks = await loadFallbackFonts();
    final before = PdfTextExtractor.extract(PdfDocument.open(bytes), 0).text;
    // ignore: avoid_print
    print('BEFORE token="ھذه" contains=${before.contains('ھذه')} '
        'index=${before.indexOf('ھذه')}');

    for (final entry in {'identity': 'ھذه', 'longer': 'ھذهabc'}.entries) {
      final editing = PdfEditingController(bytes);
      var n = 0;
      editing.apply((e) => n = e.replaceText(0, 'ھذه', entry.value,
          fallbackFonts: fallbacks));
      final afterBytes = Uint8List.fromList(editing.bytes);
      final after = PdfTextExtractor.extract(PdfDocument.open(afterBytes), 0).text;
      // ignore: avoid_print
      print('${entry.key}: n=$n bytes=${afterBytes.length}');
      // ignore: avoid_print
      print('  after.text = "${after.replaceAll('\n', '\\n')}"');
      // ignore: avoid_print
      print('  contains("${entry.value}")=${after.contains(entry.value)} '
          'contains(ھذه)=${after.contains('ھذه')}');
      // ignore: avoid_print
      print('  first token = "${after.split(RegExp(r'\s+')).first}"');
      // code points of the first token
      final t = after.split(RegExp(r'\s+')).first;
      // ignore: avoid_print
      print('  first token runes = ${t.runes.map((r) => r.toRadixString(16).padLeft(4, '0')).toList()}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
