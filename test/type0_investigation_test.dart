import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

/// Investigation of Type0 / composite / subset-font text editing.
///
/// Output lines are prefixed `TI |`. Fixtures include real Chrome-print PDFs
/// (English / Arabic / English+Arabic), a Type1 (Helvetica) PDF, and subset
/// TrueType Type0 PDFs that share the structural fingerprint Microsoft Word,
/// Google Docs and LibreOffice produce (Identity-H + CIDFontType2 +
/// Identity-CIDToGIDMap + ToUnicode), plus deliberately-broken variants that
/// probe the engine's eligibility gate.
///
/// The whole test runs in real-async (plain `test`, not `testWidgets`) so
/// page rendering (ui.Image) completes; the engine's editing controller is
/// pure Dart and needs no frame pumping.

class _FontInfo {
  _FontInfo(this.name, this.subtype, this.baseFont, this.encoding,
      this.cidSubtype, this.cidToGid, this.toUnicode, this.file);
  final String name;
  final String subtype;
  final String baseFont;
  final String? encoding;
  final String? cidSubtype;
  final String? cidToGid;
  final bool toUnicode;
  final String file;

  bool get predictedEditable {
    if (subtype == 'Type1' || subtype == 'TrueType') return true;
    if (subtype != 'Type0') return false;
    if (encoding != 'Identity-H') return false;
    if (cidSubtype != 'CIDFontType2') return false;
    if (cidToGid != null && cidToGid != 'Identity') return false;
    if (!toUnicode) return false;
    if (file.isEmpty || file == 'none') return false;
    return true;
  }

  String get rejectReason {
    if (predictedEditable) return '';
    final why = <String>[];
    if (subtype != 'Type0' && subtype != 'Type1' && subtype != 'TrueType') {
      why.add('subtype=$subtype');
    }
    if (subtype == 'Type0') {
      if (encoding != 'Identity-H') why.add('encoding=$encoding (need Identity-H)');
      if (cidSubtype != 'CIDFontType2') why.add('cidSubtype=$cidSubtype (need CIDFontType2)');
      if (cidToGid != null && cidToGid != 'Identity') why.add('CIDToGIDMap=$cidToGid (need Identity/absent)');
      if (!toUnicode) why.add('no /ToUnicode');
      if (file.isEmpty || file == 'none') why.add('no embedded program');
    }
    return why.join('; ');
  }

  @override
  String toString() => '$name:$subtype($baseFont) enc=$encoding '
      'cid=$cidSubtype c2g=$cidToGid toUni=$toUnicode file=$file';
}

const String _renderDir = '/tmp/pdfedit/renders';

Future<List<_FontInfo>> _fingerprint(PdfDocument doc, int pageIndex) async {
  final cos = doc.cos;
  final page = doc.page(pageIndex);
  final fonts = cos.resolve(page.resources['Font']);
  final out = <_FontInfo>[];
  if (fonts is! CosDictionary) return out;
  fonts.entries.forEach((name, obj) {
    final f = cos.resolve(obj);
    if (f is! CosDictionary) return;
    final subtype = _name(f['Subtype']) ?? '?';
    final base = _name(f['BaseFont']) ?? '?';
    final enc = _name(f['Encoding']);
    String? cidSubtype;
    String? c2g;
    final desc = cos.resolve(f['DescendantFonts']);
    if (desc is CosArray && desc.items.isNotEmpty) {
      final cid = cos.resolve(desc.items.first);
      if (cid is CosDictionary) {
        cidSubtype = _name(cid['Subtype']);
        final cg = cos.resolve(cid['CIDToGIDMap']);
        c2g = cg is CosName ? cg.value : (cg is CosStream ? 'stream' : '${cg.runtimeType}');
        final fd = cos.resolve(cid['FontDescriptor']);
        if (fd is CosDictionary) {
          out.add(_FontInfo(name, subtype, base, enc, cidSubtype, c2g,
              cos.resolve(f['ToUnicode']) is CosStream,
              _fileKind(cos, fd)));
          return;
        }
      }
    }
    out.add(_FontInfo(name, subtype, base, enc, cidSubtype, c2g,
        cos.resolve(f['ToUnicode']) is CosStream, 'none'));
  });
  return out;
}

String _fileKind(CosDocument cos, CosDictionary fd) {
  if (cos.resolve(fd['FontFile2']) is CosStream) return 'FontFile2(TrueType)';
  final f3 = cos.resolve(fd['FontFile3']);
  if (f3 is CosStream) {
    final sub = _name(f3.dictionary['Subtype']) ?? '';
    return 'FontFile3($sub)';
  }
  if (cos.resolve(fd['FontFile']) is CosStream) return 'FontFile(Type1)';
  return 'none';
}

String? _name(CosObject? o) => o is CosName ? o.value : null;

Future<Uint8List> _makeSubsetTtf({required bool noToUnicode}) async {
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
  final bytes = Uint8List.fromList(await doc.save());
  if (!noToUnicode) return bytes;

  final d = PdfDocument.open(bytes);
  final cos = d.cos;
  final updater = CosIncrementalUpdater(cos);
  final fonts = cos.resolve(d.page(0).resources['Font']);
  if (fonts is CosDictionary) {
    for (final obj in fonts.entries.values) {
      final f = cos.resolve(obj);
      if (f is CosDictionary && _name(f['Subtype']) == 'Type0') {
        f.entries.remove('ToUnicode');
        if (cos.referenceTo(f) != null) updater.markChanged(f);
      }
    }
  }
  return updater.save();
}

Future<Uint8List> _mutateType0({
  required void Function(CosDictionary f) mutate,
}) async {
  final base = await _makeSubsetTtf(noToUnicode: false);
  final d = PdfDocument.open(base);
  final cos = d.cos;
  final updater = CosIncrementalUpdater(cos);
  final fonts = cos.resolve(d.page(0).resources['Font']);
  if (fonts is CosDictionary) {
    for (final obj in fonts.entries.values) {
      final f = cos.resolve(obj);
      if (f is CosDictionary && _name(f['Subtype']) == 'Type0') {
        mutate(f);
        if (cos.referenceTo(f) != null) updater.markChanged(f);
      }
    }
  }
  return updater.save();
}

Future<Uint8List> _makeType1() async {
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: pdf.PdfPageFormat.a4,
    build: (_) => pw.Padding(
      padding: const pw.EdgeInsets.all(48),
      child: pw.Text('HELVETICA_PROBE simple Type1 text here.',
          style: pw.TextStyle(font: pw.Font.helvetica(), fontSize: 14)),
    ),
  ));
  return Uint8List.fromList(await doc.save());
}

String _tokenFrom(String text) {
  final words = text.split(RegExp(r'\s+')).where((w) => w.runes.length >= 3);
  for (final w in words) {
    if (w.runes.any((r) => r > 0x20)) return w;
  }
  return '';
}

String _buildFrom(String pool, int targetLen, int offset) {
  final chars = pool.runes.toList();
  if (chars.isEmpty) return 'X' * targetLen;
  final buf = StringBuffer();
  var i = offset;
  var len = 0;
  while (len < targetLen) {
    buf.writeCharCode(chars[i % chars.length]);
    i++;
    len++;
  }
  return buf.toString();
}

/// Builds a replacement of [targetLen] runes whose characters all come from
/// the document's own extracted text (so a subset font plausibly carries
/// them), that differs from [token] and - when long enough - is not already a
/// substring of the original [originalText] (which would make the edit's
/// effect indistinguishable in extraction).
String _buildReplacement(String token, String pool, int targetLen, String originalText) {
  for (var attempt = 0; attempt < 40; attempt++) {
    final s = _buildFrom(pool, targetLen, attempt * 7 + targetLen);
    if (s == token) continue;
    if (targetLen >= 2 && originalText.contains(s)) continue;
    return s;
  }
  return _buildFrom('abcdefghijklmnopqrstuvwxyz', targetLen, 0);
}

class _EditOutcome {
  _EditOutcome(this.replacements, this.editedBytes);
  final int replacements;
  final Uint8List editedBytes;
}

Future<_EditOutcome> _edit(
    Uint8List bytes, String find, String replace,
    {required List<PdfEmbeddedFont> fallbacks}) async {
  final editing = PdfEditingController(bytes);
  var n = 0;
  editing.apply((e) {
    n = e.replaceText(0, find, replace, fallbackFonts: fallbacks);
  });
  return _EditOutcome(n, Uint8List.fromList(editing.bytes));
}

Future<void> _renderPng(Uint8List bytes, String tag) async {
  try {
    final doc = PdfDocument.open(bytes);
    final img = await PdfPageRenderer.renderImage(doc.page(0),
        pixelRatio: 1.5, annotations: false);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('$_renderDir/$tag.png');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('TI | RENDER | $tag.png written (${data.lengthInBytes} bytes)');
    img.dispose();
  } catch (e) {
    // ignore: avoid_print
    print('TI | RENDER | $tag FAILED: $e');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerBundledEditorAssets();

  test('TYPE0 / composite / subset font editing investigation', () async {
    final fallbacks = await loadFallbackFonts();

    final fixtures = <String, Uint8List>{
      'helv_type1': await _makeType1(),
      'subset_ttf (Word/GDocs/LibreOffice-like)': await _makeSubsetTtf(noToUnicode: false),
      'subset_ttf_no_tounicode': await _makeSubsetTtf(noToUnicode: true),
      'subset_ttf_nonidentity_encoding': await _mutateType0(
          mutate: (f) => f['Encoding'] = CosName('UniGB-UCS2-H')),
      'subset_ttf_stream_cid2gid': await _mutateType0(mutate: (f) {
        final desc = f['DescendantFonts'];
        if (desc is CosArray && desc.items.isNotEmpty) {
          final cid = desc.items.first;
          if (cid is CosDictionary) {
            cid['CIDToGIDMap'] = CosStream(
                CosDictionary({'Length': CosInteger(0)}), Uint8List(0));
          }
        }
      }),
      'subset_ttf_cidfonttype0': await _mutateType0(
          mutate: (f) {
            final desc = f['DescendantFonts'];
            if (desc is CosArray && desc.items.isNotEmpty) {
              final cid = desc.items.first;
              if (cid is CosDictionary) cid['Subtype'] = CosName('CIDFontType0');
            }
          }),
      'chrome_en': File('/tmp/pdfedit/chrome_en.pdf').readAsBytesSync(),
      'chrome_ar': File('/tmp/pdfedit/chrome_ar.pdf').readAsBytesSync(),
      'chrome_en_ar': File('/tmp/pdfedit/chrome_en_ar.pdf').readAsBytesSync(),
    };

    for (final entry in fixtures.entries) {
      final name = entry.key;
      final bytes = entry.value;
      // ignore: avoid_print
      print('========== FIXTURE: $name ==========');

      final doc = PdfDocument.open(bytes);
      final fonts = await _fingerprint(doc, 0);
      for (final f in fonts) {
        // ignore: avoid_print
        print('TI | FONT | $f');
        // ignore: avoid_print
        print('TI | FONT-PREDICT | ${f.name} editable=${f.predictedEditable}'
            '${f.rejectReason.isEmpty ? '' : ' | ${f.rejectReason}'}');
      }

      final pageText = PdfTextExtractor.extract(doc, 0);
      final text = pageText.text;
      final token = _tokenFrom(text);
      if (token.isEmpty) {
        // ignore: avoid_print
        print('TI | SELECT | no extractable text (no usable /ToUnicode) '
            '-> edit cannot be driven from text');
        continue;
      }
      // ignore: avoid_print
      print('TI | SELECT | token="$token" present in extractable text');

      final pool = text.runes.map((r) => String.fromCharCode(r)).join();
      final len = token.runes.length;
      final shortLen = len <= 4 ? len - 1 : len - 3;
      final variants = <String, String>{
        'same-length': _buildReplacement(token, pool, len, text),
        'shorter': _buildReplacement(token, pool, shortLen, text),
        'longer': token + _buildReplacement(token, pool, 3, text),
        'identity': token,
      };
      // ignore: avoid_print
      print('TI | PLAN | ${variants.entries.map((e) => '${e.key}->"${e.value}"').join(' | ')}');

      await _renderPng(bytes, '${name}_before'.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_'));

      for (final variant in variants.entries) {
        final replace = variant.value;
        final variantTag = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

        for (final withFb in [true, false]) {
          final tag = '${variant.key}-${withFb ? 'fb' : 'nofb'}';
          _EditOutcome? out;
          Object? err;
          try {
            out = await _edit(bytes, token, replace, fallbacks: withFb ? fallbacks : const []);
          } catch (e, st) {
            err = '$e\n$st';
          }
          if (err != null) {
            // ignore: avoid_print
            print('TI | $tag | ERROR | $err');
            continue;
          }
          final n = out!.replacements;
          String verify;
          try {
            final reopened = PdfDocument.open(out.editedBytes);
            final t2 = PdfTextExtractor.extract(reopened, 0).text;
            verify = 'landed=${t2.contains(replace) && !text.contains(replace)} '
                'extract-still-original=${t2.contains(token)}';
          } catch (e) {
            verify = 'REOPEN-FAIL: $e';
          }
          // ignore: avoid_print
          print('TI | $tag | replacements=$n | saved=${out.editedBytes.length} | $verify');
          if (withFb && variant.key == 'longer') {
            await _renderPng(out.editedBytes, '${variantTag}_after_${variant.key}');
          }
        }
      }
    }

    // ignore: avoid_print
    print('========== INVESTIGATION COMPLETE ==========');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
