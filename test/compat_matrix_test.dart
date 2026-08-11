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

import 'package:pdf_editor/src/sample_pdf.dart';

// ignore_for_file: avoid_print

/// Real-world compatibility + visual-regression pass for the patched engine.
///
/// Generators:
///   - Chrome Print to PDF  (REAL, Type0 Identity-H, per-glyph RTL objects)
///   - LibreOffice Writer   (REAL, simple subset TrueType, Latin-1 encoded)
///   - Word / Google Docs   (STRUCTURAL PROXY: subset TrueType Type0 built by
///     the `pdf` package; same Identity-H + CIDFontType2 + CIDToGIDMap +
///     ToUnicode fingerprint Word and Google Docs emit)
///
/// Every edit is verified for: replacement count, reopen+extraction,
/// no-corruption (all non-target words preserved), unexpected font embedding,
/// and size delta. Representative before/after PNGs are rendered to
/// /tmp/pdfedit/compat/renders for visual inspection.
///
/// Output lines are prefixed `CM |`; a matrix summary is written to
/// /tmp/pdfedit/compat/matrix_results.txt.

const String _renderDir = '/tmp/pdfedit/compat/renders';

Set<String> _fontNames(PdfDocument doc, int page) {
  final cos = doc.cos;
  final fonts = cos.resolve(doc.page(page).resources['Font']);
  final out = <String>{};
  if (fonts is CosDictionary) {
    fonts.entries.forEach((k, v) => out.add(k));
  }
  return out;
}

String _extract(PdfDocument doc) => PdfTextExtractor.extract(doc, 0).text;

bool _isLetter(int r) => _isLatinLetter(r) || _isArabicLetter(r);

bool _isLatinLetter(int r) =>
    (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A);

bool _isArabicLetter(int r) => (r >= 0x0600 && r <= 0x06FF) ||
    (r >= 0x0750 && r <= 0x077F) ||
    (r >= 0x08A0 && r <= 0x08FF) ||
    (r >= 0xFB50 && r <= 0xFDFF) ||
    (r >= 0xFE70 && r <= 0xFEFF);

String _firstToken(String text, {int minLen = 3}) {
  for (final w in text.split(RegExp(r'\s+'))) {
    final letters = w.runes.where(_isLetter).toList();
    if (letters.length >= minLen && letters.length == w.runes.length) {
      return String.fromCharCodes(letters);
    }
  }
  return '';
}

String _firstTokenOf(String text, bool Function(int) isLang) {
  for (final w in text.split(RegExp(r'\s+'))) {
    final letters = w.runes.where(isLang).toList();
    if (letters.length >= 3 && letters.length == w.runes.length) {
      return String.fromCharCodes(letters);
    }
  }
  return '';
}

String _pool(String text) =>
    text.runes.where((r) => _isLetter(r)).map(String.fromCharCode).join();

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

String _buildReplacement(
    String token, String pool, int targetLen, String originalText) {
  for (var attempt = 0; attempt < 40; attempt++) {
    final s = _buildFrom(pool, targetLen, attempt * 7 + targetLen);
    if (s == token) continue;
    if (targetLen >= 2 && originalText.contains(s)) continue;
    return s;
  }
  return _buildFrom(
      'abcdefghijklmnopqrstuvwxyz', targetLen, 0);
}

/// The words (>=2 letters) in [text]; used for the corruption check.
Set<String> _words(String text) => {
      for (final w in text.split(RegExp(r'\s+')))
        if (w.runes.length >= 2 && w.runes.every(_isLetter)) w,
    };

Future<Uint8List?> _renderPng(Uint8List bytes, String tag,
    {bool annotations = false}) async {
  try {
    final doc = PdfDocument.open(bytes);
    final img = await PdfPageRenderer.renderImage(doc.page(0),
        pixelRatio: 1.5, annotations: annotations);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final png = data!.buffer.asUint8List();
    final f = File('$_renderDir/$tag.png');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(png);
    img.dispose();
    print('CM | RENDER | $tag.png written (${png.length} bytes)');
    return png;
  } catch (e) {
    print('CM | RENDER | $tag FAILED: $e');
    return null;
  }
}

/// Whether two rendered PNGs differ (byte-exact; the renderer is
/// deterministic, so identical content yields identical bytes).
bool _pngDiffers(Uint8List? a, Uint8List? b) {
  if (a == null || b == null) return false;
  if (a.length != b.length) return true;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return true;
  }
  return false;
}

class _Result {
  _Result(this.fixture, this.caseName, this.n, this.pass, this.note);
  final String fixture;
  final String caseName;
  final int n;
  final bool pass;
  final String note;
}

List<String> _matrix = [];

void _report(String line) {
  print('CM | $line');
  _matrix.add(line);
}

String _boolMark(bool v) => v ? 'PASS' : 'FAIL';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerBundledEditorAssets();

  test('real-world compatibility matrix', () async {
    final fallbacks = await loadFallbackFonts();
    final proxyEn = await _makeSubsetTtf();

    final fixtures = <String, Uint8List>{
      'chrome_en (real)': File('/tmp/pdfedit/compat/chrome_en.pdf').readAsBytesSync(),
      'chrome_ar (real)': File('/tmp/pdfedit/compat/chrome_ar.pdf').readAsBytesSync(),
      'chrome_en_ar (real)': File('/tmp/pdfedit/compat/chrome_en_ar.pdf').readAsBytesSync(),
      'chrome_ar_num (real)': File('/tmp/pdfedit/compat/chrome_ar_num.pdf').readAsBytesSync(),
      'chrome_ar_punct (real)': File('/tmp/pdfedit/compat/chrome_ar_punct.pdf').readAsBytesSync(),
      'libreoffice_writer_en (real)':
          File('/tmp/pdfedit/compat_lo/lo_writer_en.pdf').readAsBytesSync(),
      'libreoffice_writer_ar (real)':
          File('/tmp/pdfedit/compat_lo/lo_writer_ar.pdf').readAsBytesSync(),
      'word/gdocs subset-ttf proxy': proxyEn,
    };

    final results = <_Result>[];

    for (final fixture in fixtures.entries) {
      final name = fixture.key;
      final bytes = fixture.value;
      _report('===== FIXTURE: $name =====');
      final doc = PdfDocument.open(bytes);
      final text = _extract(doc);
      final fontsBefore = _fontNames(doc, 0);
      _report('text=${text.replaceAll('\n', '⏎')}');
      _report('fonts=${fontsBefore.join(',')} size=${bytes.length}');
      await _renderPng(bytes, '${_tag(name)}_before');

      final hasArabic = text.runes.any(_isArabicLetter);
      final hasEnglish = text.runes.any(_isLatinLetter);
      final pool = _pool(text);

      // Plan: per content type we exercise the requested replacement classes.
      String? englishToken;
      String? arabicToken;
      if (hasEnglish) {
        englishToken = _firstTokenOf(text, _isLatinLetter);
      }
      if (hasArabic) {
        arabicToken = _firstTokenOf(text, _isArabicLetter);
      }

      final plans = <(String, String, String)>[];

      void planFor(String? token, String prefix) {
        if (token == null || token.isEmpty) return;
        final len = token.runes.length;
        final shortLen = len <= 4 ? len - 1 : len - 3;
        if (shortLen >= 2) {
          plans.add(('$prefix-shorter', token, _buildReplacement(token, pool, shortLen, text)));
        }
        plans.add(
            ('$prefix-same', token, _buildReplacement(token, pool, len, text)));
        plans.add(('$prefix-longer', token,
            token + _buildReplacement(token, pool, 2, text)));
      }

      if (arabicToken != null) {
        plans.add(('ar-to-en', arabicToken, 'English'));
      }
      if (englishToken != null) {
        plans.add(('en-to-ar', englishToken, 'عربي'));
      }

      planFor(arabicToken, 'ar');
      planFor(englishToken, 'en');

      for (final p in plans) {
        final (label, find, replace) = p;
        final usesFallback = replace.runes.any((r) => !_isLetter(r) || r > 0xFF);
        Object? err;
        int n = 0;
        Uint8List edited;
        try {
          final editing = PdfEditingController(bytes);
          editing.apply((e) {
            n = e.replaceText(0, find, replace, fallbackFonts: fallbacks);
          });
          edited = Uint8List.fromList(editing.bytes);
        } catch (e, st) {
          err = '$e\n$st';
          edited = bytes;
        }
        if (err != null) {
          results.add(_Result(name, label, 0, false, 'EDIT-ERROR: $err'));
          _report('$label | find="$find" replace="$replace" | ERROR $err');
          continue;
        }

        final ok = <String>[];
        String? reopenFailure;
        String afterText = '';
        try {
          final reopened = PdfDocument.open(edited);
          afterText = _extract(reopened);
          final fontsAfter = _fontNames(reopened, 0);
          final unexpectedFonts =
              fontsAfter.difference(fontsBefore).where((f) => !f.startsWith('Fbk'));
          ok.add('extract=${afterText.contains(replace)}');
          final tokenGone = !afterText.contains(find) || replace.contains(find);
          ok.add('token-gone=$tokenGone');
          ok.add('usesFallback=$usesFallback');
          final wordsBefore = _words(text)..remove(find);
          // A word may re-attach adjacent punctuation after a bidi reorder of
          // the line, so require every original word to still appear as a
          // substring rather than as an isolated whitespace-delimited token.
          final lost = wordsBefore.where((w) => !afterText.contains(w)).toSet();
          ok.add('no-corruption=${lost.isEmpty ? 'clean' : 'LOST:${lost.join(',')}'}');
          ok.add('fonts=${unexpectedFonts.isEmpty ? 'ok' : 'UNEXPECTED:${unexpectedFonts.join(',')}'}');
          if (!afterText.contains(replace) || lost.isNotEmpty) {
            reopenFailure = 'extract mismatch';
          }
        } catch (e) {
          reopenFailure = 'REOPEN-FAIL: $e';
          ok.add(reopenFailure);
        }
        final delta = edited.length - bytes.length;
        ok.add('size=$delta');
        final pass = n > 0 && reopenFailure == null;
        results.add(_Result(name, label, n, pass,
            ok.join(' | ') + (reopenFailure != null ? ' | $reopenFailure' : '')));
        _report(
            '$label | find="$find" replace="$replace" | n=$n | ${ok.join(' | ')}');
        if (label == 'ar-longer' || label == 'en-to-ar') {
          final after = await _renderPng(edited, '${_tag(name)}_after_$label');
          final before =
              File('$_renderDir/${_tag(name)}_before.png').readAsBytesSync();
          _report('visual-changed=${_pngDiffers(after, before)} '
              '(before ${before.length}b, after ${after?.length ?? 0}b)');
        }
      }
    }

    _report('===== SAVE/CLOSE/REOPEN + UNDO/REDO (chrome_ar) =====');
    {
      final bytes = File('/tmp/pdfedit/compat/chrome_ar.pdf').readAsBytesSync();
      final text0 = _extract(PdfDocument.open(bytes));
      final token = _firstToken(text0);
      final replace = token + _buildReplacement(token, _pool(text0), 2, text0);
      final editing = PdfEditingController(bytes);
      var n = 0;
      editing.apply((e) => n = e.replaceText(0, token, replace, fallbackFonts: fallbacks));
      final saved = Uint8List.fromList(editing.bytes);
      final tmp = File('/tmp/pdfedit/compat/reopen_check.pdf')
        ..writeAsBytesSync(saved);
      final reopenedFromFile =
          PdfDocument.open(tmp.readAsBytesSync());
      final t1 = _extract(reopenedFromFile);
      final saveReopenOk = t1.contains(replace);
      _report('save-close-reopen | n=$n | extract-ok=$saveReopenOk');
      expect(saveReopenOk, isTrue);

      // undo -> back to original
      expect(editing.canUndo, isTrue);
      editing.undo();
      final tUndo = _extract(PdfDocument.open(editing.bytes));
      final undoOk = tUndo.contains(token) && !tUndo.contains(replace);
      _report('undo | text-restored=$undoOk | canRedo=${editing.canRedo}');
      expect(undoOk, isTrue);
      expect(editing.canRedo, isTrue);

      // redo -> edit again
      editing.redo();
      final tRedo = _extract(PdfDocument.open(editing.bytes));
      final redoOk = tRedo.contains(replace);
      _report('redo | edit-reapplied=$redoOk | canUndo=${editing.canUndo}');
      expect(redoOk, isTrue);
      await _renderPng(editing.bytes, 'chrome_ar_after_redo');
    }

    _report('===== UNDO/REDO (libreoffice_writer_en, simple font) =====');
    {
      final bytes =
          File('/tmp/pdfedit/compat_lo/lo_writer_en.pdf').readAsBytesSync();
      final text0 = _extract(PdfDocument.open(bytes));
      final token = _firstToken(text0);
      final editing = PdfEditingController(bytes);
      final applied = editing.apply(
          (e) => e.replaceText(0, token, '${token}xy', fallbackFonts: fallbacks));
      // LibreOffice simple-TrueType runs are byte-level Latin-1; this edit is
      // a no-op (n=0), so undo/redo are exercised as safe no-ops.
      expect(applied, isFalse);
      expect(editing.canUndo, isFalse);
      editing.undo();
      editing.redo();
      final t = _extract(PdfDocument.open(editing.bytes));
      expect(t, text0);
      _report('no-op-undo-redo | applied=$applied text-unchanged=${t == text0}');
    }

    _report('===== ANNOTATIONS SURVIVE A TEXT EDIT =====');
    {
      final base = await createSamplePdf();
      final editing = PdfEditingController(base);
      editing.apply((e) {
        e.addHighlight(0, [const PdfRect(48, 460, 360, 478)], author: 'compat');
        e.addUnderline(0, [const PdfRect(48, 440, 360, 458)], author: 'compat');
        e.addStrikeOut(0, [const PdfRect(48, 420, 360, 438)], author: 'compat');
      });
      editing.apply((e) {
        e.replaceText(0, 'FIND_ME_PROGRAMMATIC', 'EDITED_AFTER_ANNOTATION',
            fallbackFonts: fallbacks);
      });
      final saved = Uint8List.fromList(editing.bytes);
      final reopened = PdfDocument.open(saved);
      final text = _extract(reopened);
      final subtypes = reopened.page(0).annotations.map((a) => a.subtype).toSet();
      final textOk = text.contains('EDITED_AFTER_ANNOTATION') &&
          !text.contains('FIND_ME_PROGRAMMATIC');
      final annotOk = subtypes.containsAll(
          {'Highlight', 'Underline', 'StrikeOut'});
      _report('annotations-after-edit | text-ok=$textOk '
          'annotations=${subtypes.toList()..sort()}');
      expect(textOk && annotOk, isTrue);
      await _renderPng(saved, 'annotations_after_edit', annotations: true);
    }

    _report('===== ENGLISH NO-REGRESSION (chrome_en quick checks) =====');
    {
      final bytes = File('/tmp/pdfedit/compat/chrome_en.pdf').readAsBytesSync();
      final doc = PdfDocument.open(bytes);
      final text = _extract(doc);
      final token = _firstToken(text);
      final pool = _pool(text);
      final len = token.runes.length;
      final variants = {
        'shorter': _buildReplacement(token, pool, len <= 4 ? len - 1 : len - 3, text),
        'same': _buildReplacement(token, pool, len, text),
        'longer': token + _buildReplacement(token, pool, 2, text),
      };
      for (final v in variants.entries) {
        final editing = PdfEditingController(bytes);
        var n = 0;
        editing.apply(
            (e) => n = e.replaceText(0, token, v.value, fallbackFonts: fallbacks));
        final t = _extract(PdfDocument.open(editing.bytes));
        final roundtrip = n > 0 &&
            t.contains(v.value) &&
            (!t.contains(token) || v.value.contains(token));
        _report('en-regression-${v.key} | n=$n | roundtrip=$roundtrip');
        expect(roundtrip, isTrue);
      }
    }

    // Summarize.
    _report('');
    _report('===== MATRIX SUMMARY =====');
    final byFixture = <String, List<_Result>>{};
    for (final r in results) {
      byFixture.putIfAbsent(r.fixture, () => []).add(r);
    }
    byFixture.forEach((fixture, list) {
      for (final r in list) {
        _report('RESULT | ${r.fixture} | ${r.caseName} | n=${r.n} | '
            '${_boolMark(r.pass)} | ${r.note}');
      }
    });

    File('/tmp/pdfedit/compat/matrix_results.txt')
        .writeAsStringSync(_matrix.join('\n'));
    _report('wrote /tmp/pdfedit/compat/matrix_results.txt '
        '(${results.length} edit cells)');
  }, timeout: const Timeout(Duration(minutes: 15)));
}

String _tag(String name) =>
    name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_').toLowerCase();

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
