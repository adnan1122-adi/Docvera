import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

/// Verifies the edit on the RTL object structurally: the glyph strings around
/// the match are untouched, the replacement draws in a fallback `Tf`, and the
/// surrounding BT/Tm/Td/BDC/EMC/ET structure survives.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerBundledEditorAssets();

  test('dump edited RTL object ops', () async {
    final bytes = File('/tmp/pdfedit/chrome_ar.pdf').readAsBytesSync();

    final beforeDoc = PdfDocument.open(bytes);
    final beforeOps = ContentStreamParser.parse(beforeDoc.page(0).contentBytes());
    final beforeContents = beforeDoc.cos.resolve(beforeDoc.page(0).dict['Contents']);
    // ignore: avoid_print
    print('BEFORE | ops=${beforeOps.length} contents=${beforeContents.runtimeType} '
        'streams=${beforeContents is CosArray ? beforeContents.items.length : 1}');
    final beforeObj8 = _objectOps(beforeOps, 8);
    // ignore: avoid_print
    print('BEFORE OBJ#8 (original "ھذه"):');
    for (final o in beforeObj8) {
      final operands = o.operands.isEmpty
          ? ''
          : o.operands
              .map((op) => op is CosName
                  ? '/${op.value}'
                  : op is CosString
                      ? '<${op.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}>'
                      : '?')
              .join(' ');
      // ignore: avoid_print
      print('  ${o.operator} $operands');
    }

    final editing = PdfEditingController(bytes);
    final fallbacks = await loadFallbackFonts();
    editing.apply((e) => e.replaceText(0, 'ھذه', 'TESTX',
        fallbackFonts: fallbacks));

    final after = Uint8List.fromList(editing.bytes);
    final doc = PdfDocument.open(after);
    final cos = doc.cos;
    final page = doc.page(0);
    final ops = ContentStreamParser.parse(page.contentBytes());
    final afterContents = cos.resolve(page.dict['Contents']);
    // ignore: avoid_print
    print('AFTER  | ops=${ops.length} contents=${afterContents.runtimeType} '
        'streams=${afterContents is CosArray ? afterContents.items.length : 1}');

    // The first F5 (Arabic) object is the one that was "ھذه" - print its ops.
    String? fontName;
    final buf = StringBuffer();
    var obj = 0;
    var inText = false;
    final textObj = <ContentOperation>[];
    String labelOf(CosObject o) {
      if (o is CosName) return '/${o.value}';
      if (o is CosString) {
        return '<${o.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}>';
      }
      if (o is CosInteger) return '${o.value}';
      if (o is CosReal) return '${o.value}';
      if (o is CosDictionary) {
        final at = o['ActualText'];
        return at is CosString
            ? '{ActualText:<${at.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}>}'
            : '{dict}';
      }
      return '?';
    }

    void flush() {
      if (textObj.isEmpty) return;
      obj++;
      final isArabic = fontName == 'F5' || fontName == 'F6';
      final hasFallback = textObj.any((o) =>
          o.operator == 'Tf' &&
          o.operands.isNotEmpty &&
          o.operands[0] is CosName &&
          (o.operands[0] as CosName).value.startsWith('Fbk'));
      if (obj <= 3 || hasFallback) {
        buf.writeln(
            '--- object #$obj (font=$fontName) fallback=$hasFallback '
            'arabic=$isArabic ---');
        for (final o in textObj) {
          final operands = o.operands.isEmpty
              ? ''
              : o.operands.map(labelOf).join(' ');
          buf.writeln('  ${o.operator} $operands');
        }
      }
      textObj.clear();
    }

    for (final op in ops) {
      if (op.operator == 'Tf' && op.operands.isNotEmpty) {
        fontName = op.operands[0] is CosName
            ? (op.operands[0] as CosName).value
            : fontName;
      }
      if (op.operator == 'BT') inText = true;
      if (op.operator == 'ET') {
        if (inText) flush();
        inText = false;
        continue;
      }
      if (inText) textObj.add(op);
    }
    flush();
    // ignore: avoid_print
    print('DUMP\n$buf');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

List<ContentOperation> _objectOps(List<ContentOperation> ops, int which) {
  var obj = 0;
  var inText = false;
  final out = <ContentOperation>[];
  for (final op in ops) {
    if (op.operator == 'BT') {
      inText = true;
      out.clear();
    }
    if (op.operator == 'ET') {
      if (inText) {
        obj++;
        if (obj == which) return out;
      }
      inText = false;
    }
    if (inText) out.add(op);
  }
  return const [];
}
