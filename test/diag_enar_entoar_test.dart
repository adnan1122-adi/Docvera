import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

// ignore_for_file: avoid_print

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerBundledEditorAssets();

  test('chrome_en_ar en-to-ar diagnose', () async {
    final fallbacks = await loadFallbackFonts();
    final bytes = File('/tmp/pdfedit/compat/chrome_en_ar.pdf').readAsBytesSync();
    final before = PdfTextExtractor.extract(PdfDocument.open(bytes), 0).text;
    print('DX | BEFORE=${before.replaceAll('\n', '⏎')}');

    final editing = PdfEditingController(bytes);
    var n = 0;
    editing.apply((e) {
      n = e.replaceText(0, 'English', 'عربي', fallbackFonts: fallbacks);
    });
    print('DX | n=$n');
    final edited = Uint8List.fromList(editing.bytes);
    final after = PdfTextExtractor.extract(PdfDocument.open(edited), 0).text;
    print('DX | AFTER=${after.replaceAll('\n', '⏎')}');

    // dump ops of each text object in the edited page
    final d = PdfDocument.open(edited);
    final ops = PdfPageElements.of(d, 0).operations;
    final showIdx = <int>[];
    for (var i = 0; i < ops.length; i++) {
      if (ops[i].operator == 'Tj' || ops[i].operator == 'TJ') showIdx.add(i);
    }
    print('DX | show-ops=${showIdx.length}');
    for (var i = 0; i < ops.length; i++) {
      final op = ops[i];
      if (op.operator == 'BT') {
        print('DX | ---- BT at $i ----');
      }
      if (op.operator == 'Tf') {
        print('DX | $i: Tf ${op.operands.map((o) => o.toString()).join(' ')}');
      }
      if (op.operator == 'Tj' || op.operator == 'TJ') {
        print('DX | $i: ${op.operator} ${op.operands.map((o) => o.toString()).join(' ')}');
      }
      if (op.operator == 'Td' || op.operator == 'Tm') {
        print('DX | $i: ${op.operator}');
      }
    }
  });
}
