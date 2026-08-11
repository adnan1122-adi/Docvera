import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

Future<Uint8List> _makeSubsetTtf() async {
  final data = File('/Users/muhammadadnan/.pub-cache/hosted/pub.dev/'
          'dart_pdf_editor_assets-3.4.0/assets/fonts/DejaVuSans.ttf')
      .readAsBytesSync();
  final font = pw.Font.ttf(ByteData.sublistView(data));
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: pdf.PdfPageFormat.a4,
    build: (_) => pw.Padding(
      padding: const pw.EdgeInsets.all(48),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('SUBSET_TTF_PROBE line with several words here.',
              style: pw.TextStyle(font: font, fontSize: 14)),
          pw.SizedBox(height: 12),
          pw.Text('A second line for the same subset font.',
              style: pw.TextStyle(font: font, fontSize: 14)),
        ],
      ),
    ),
  ));
  return Uint8List.fromList(await doc.save());
}

String _decodeCmap(Uint8List bytes) {
  final buf = StringBuffer();
  buf.writeln('--- raw (first 200) hex ---');
  buf.writeln(bytes.take(200).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' '));
  var s = latin1.decode(bytes);
  buf.writeln('--- raw as text ---');
  buf.writeln(s);
  final filter = zlib.decode(bytes);
  buf.writeln('--- zlib decoded ---');
  buf.writeln(latin1.decode(filter));
  return buf.toString();
}

int _u16(Uint8List b, int o) => (b[o] << 8) | b[o + 1];
int _u32(Uint8List b, int o) => ((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]) & 0xFFFFFFFF;

String _dumpTtf(Uint8List ttf) {
  final buf = StringBuffer();
  if (ttf.length < 12) return 'too small';
  final numTables = _u16(ttf, 4);
  final headOffset = 12;
  var cmapOff = -1, hmtxOff = -1, maxpOff = -1, numGlyphs = 0;
  for (var i = 0; i < numTables; i++) {
    final o = headOffset + i * 16;
    final tag = String.fromCharCodes(ttf.sublist(o, o + 4));
    final off = _u32(ttf, o + 8);
    if (tag == 'cmap') cmapOff = off;
    if (tag == 'hmtx') hmtxOff = off;
    if (tag == 'maxp') maxpOff = off;
  }
  if (maxpOff >= 0) numGlyphs = _u16(ttf, maxpOff + 4);
  buf.writeln('numGlyphs=$numGlyphs hmtx@$hmtxOff cmap@$cmapOff');

  if (cmapOff >= 0) {
    final nTables = _u16(ttf, cmapOff + 2);
    for (var i = 0; i < nTables; i++) {
      final o = cmapOff + 4 + i * 8;
      final platform = _u16(ttf, o);
      final enc = _u16(ttf, o + 2);
      final subOff = cmapOff + _u32(ttf, o + 4);
      final fmt = _u16(ttf, subOff);
      if (fmt == 4) {
        final segCount = _u16(ttf, subOff + 6) ~/ 2;
        final endCodes = subOff + 14;
        final startCodes = endCodes + segCount * 2 + 2;
        for (var s = 0; s < segCount; s++) {
          final start = _u16(ttf, startCodes + s * 2);
          final end = _u16(ttf, endCodes + s * 2);
          if (start == 0 && end == 0) continue;
          if (start <= 0x20 && 0x20 <= end) {
            buf.writeln('cmap$platform/$enc format4 segment covers U+0020: [$start,$end]');
          }
          if (start <= 0x61 && 0x61 <= end) {
            buf.writeln('cmap$platform/$enc format4 covers lowercase a: [$start,$end]');
          }
        }
      }
    }
  }
  return buf.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerBundledEditorAssets();

  test('DEBUG chrome_ar content', () async {
    final bytes = File('/tmp/pdfedit/chrome_ar.pdf').readAsBytesSync();
    final doc = PdfDocument.open(bytes);
    final cos = doc.cos;
    final page = doc.page(0);
    final contents = cos.resolve(page.dict['Contents']);
    Uint8List data;
    if (contents is CosArray) {
      final parts = <int>[];
      for (final item in contents.items) {
        final s = cos.resolve(item);
        if (s is CosStream) {
          var d = s.rawBytes;
          final filter = s.dictionary['Filter'];
          final isFlate = filter is CosName
              ? filter.value.contains('FlateDecode')
              : (filter is CosArray
                  ? filter.items.any((f) =>
                      f is CosName && f.value.contains('FlateDecode'))
                  : false);
          if (isFlate) d = Uint8List.fromList(zlib.decode(d));
          parts.addAll(d);
        }
      }
      data = Uint8List.fromList(parts);
    } else if (contents is CosStream) {
      var d = contents.rawBytes;
      final filter = contents.dictionary['Filter'];
      final isFlate = filter is CosName
          ? filter.value.contains('FlateDecode')
          : (filter is CosArray
              ? filter.items.any((f) =>
                  f is CosName && f.value.contains('FlateDecode'))
              : false);
      if (isFlate) d = Uint8List.fromList(zlib.decode(d));
      data = d;
    } else {
      data = Uint8List(0);
    }
    // ignore: avoid_print
    print('--- chrome_ar content stream ---');
    // ignore: avoid_print
    print(String.fromCharCodes(data));
  });

  test('DEBUG subset_ttf type0', () async {
    final bytes = await _makeSubsetTtf();
    final doc = PdfDocument.open(bytes);
    final cos = doc.cos;
    final page = doc.page(0);
    final text = PdfTextExtractor.extract(doc, 0).text;
    // ignore: avoid_print
    print('DEBUG | extracted: ${text.replaceAll('\n', '\\n')}');

    final fonts = cos.resolve(page.resources['Font']);
    if (fonts is CosDictionary) {
      fonts.entries.forEach((name, obj) {
        final f = cos.resolve(obj);
        if (f is CosDictionary) {
          final sub = f['Subtype'];
          if (sub is CosName && sub.value == 'Type0') {
            final tu = cos.resolve(f['ToUnicode']);
            if (tu is CosStream) {
              // ignore: avoid_print
              print('DEBUG | $name ToUnicode stream (${tu.rawBytes.length} bytes)');
              // ignore: avoid_print
              print(_decodeCmap(tu.rawBytes));
            }
          }
        }
      });
    }

    // Dump the FontFile2 TTF.
    if (fonts is CosDictionary) {
      fonts.entries.forEach((name, obj) {
        final f = cos.resolve(obj);
        if (f is CosDictionary) {
          final sub = f['Subtype'];
          if (sub is CosName && sub.value == 'Type0') {
            final desc = cos.resolve(f['DescendantFonts']);
            if (desc is CosArray && desc.items.isNotEmpty) {
              final cid = cos.resolve(desc.items.first);
              if (cid is CosDictionary) {
                // ignore: avoid_print
                print('--- CIDFont /DW and /W ---');
                // ignore: avoid_print
                print('DW = ${cid['DW']}');
                final w = cos.resolve(cid['W']);
                if (w is CosArray) {
                  final items = [
                    for (final it in w.items)
                      if (it is CosReference) cos.resolve(it) else it,
                  ];
                  // ignore: avoid_print
                  print('W = $items');
                }
                final fd = cos.resolve(cid['FontDescriptor']);
                if (fd is CosDictionary) {
                  final ff2 = cos.resolve(fd['FontFile2']);
                  if (ff2 is CosStream) {
                    var ttf = ff2.rawBytes;
                    final filter = ff2.dictionary['Filter'];
                    final isFlate = filter is CosName
                        ? filter.value.contains('FlateDecode')
                        : false;
                    if (isFlate) ttf = Uint8List.fromList(zlib.decode(ttf));
                    // ignore: avoid_print
                    print('--- FontFile2 TTF ---');
                    // ignore: avoid_print
                    print(_dumpTtf(ttf));
                  }
                }
              }
            }
          }
        }
      });
    }

    // Dump the page content stream.
    final contents = cos.resolve(page.dict['Contents']);
    if (contents is CosStream) {
      var data = contents.rawBytes;
      var s = latin1.decode(data);
      final filter = contents.dictionary['Filter'];
      final isFlate = filter is CosName
          ? filter.value.contains('FlateDecode')
          : (filter is CosArray
              ? filter.items.any((f) =>
                  f is CosName && f.value.contains('FlateDecode'))
              : false);
      if (isFlate) {
        data = Uint8List.fromList(zlib.decode(data));
        s = latin1.decode(data);
      }
      // ignore: avoid_print
      print('--- content stream ---');
      // ignore: avoid_print
      print(s.replaceAll(')', ')\n').substring(0, s.length));
    }

    // Compare each replacement rune against the extracted text's rune set.
    final poolChars = <int>{
      for (final r in text.runes) r,
    };
    for (final repl in ['e subset font.SU', 'bset font.SUB', 'SUBSET_TTF_PROBE.SU']) {
      final missing = <String>[];
      for (final r in repl.runes) {
        if (!poolChars.contains(r)) {
          missing.add('U+${r.toRadixString(16)} ${String.fromCharCode(r)}');
        }
      }
      // ignore: avoid_print
      print('DEBUG | "$repl" runes not in extracted pool: $missing');
    }
  });
}
