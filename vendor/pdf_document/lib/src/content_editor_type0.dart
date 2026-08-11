part of 'editor.dart';

/// Composite (/Type0) text editing for [PdfContentEditing.replaceText].
///
/// The Type0 *font model* - decoding codes to text, measuring, re-encoding
/// replacements through the embedded program's own cmap, and merging new
/// glyphs into `/W` + `/ToUnicode` - lives in [Type0Font]. This class is the
/// thin editor-side wiring around it: it resolves the eligible font on a
/// page, drives the shared [TextRunRewriter] with a Type0 codec, and does
/// the document plumbing a font model can't (allocating a fallback-font page
/// resource, marking objects changed on the updater).
///
/// Where a simple-font run encodes one byte per character, a /Type0 run draws
/// 2-byte codes. For the Identity-H + CIDFontType2 + Identity-CIDToGIDMap
/// shape [Type0Font.forEditing] accepts, a content-stream code is the glyph
/// id directly, so:
///
///  * existing text is recovered from `/ToUnicode` (matched against `find`);
///  * a replacement character is re-encoded through the embedded program's
///    own `cmap`, so *any* glyph the program carries can be typed;
///  * new glyphs' advances and Unicode values are merged back into `/W` and
///    `/ToUnicode`, so the line re-measures and stays selectable/searchable.
///
/// When the document's own font has no glyph for a replacement character - a
/// *subsetted* embedded font physically lacks the outlines it dropped - the
/// replacement is drawn in a bundled **fallback font** ([fallbackFonts]):
/// embedded as a new page /Font resource and emitted between `Tf` switches,
/// so the edit still lands (in the fallback face) rather than failing.
///
/// A run is left untouched when the font is anything [Type0Font.forEditing]
/// rejects, or when a replacement character neither the document's font nor
/// any fallback can draw.
class _Type0RunEditor {
  _Type0RunEditor._(
    this._editor,
    this.page,
    this.resourceName,
    this._font,
    this._fallbacks,
  );

  final PdfEditor _editor;
  final PdfPage page;

  /// The /Font resource key this font is referenced by on [page] (e.g. `F0`)
  /// - emitted in the `Tf` that restores it after a fallback segment.
  final String resourceName;

  /// The parsed, editable composite font.
  final Type0Font _font;

  /// Bundled fallback fonts to draw characters the document font lacks.
  final List<PdfEmbeddedFont> _fallbacks;

  /// Fallback fonts actually used, mapped to the page /Font resource name
  /// allocated for each - registered by [commit].
  final Map<PdfEmbeddedFont, String> _usedFallbacks = {};
  final Set<String> _allocatedNames = {};
  CosDictionary? _fontResourcesCache;

  bool get isDirty => _font.isDirty || _usedFallbacks.isNotEmpty;

  /// Builds an editor for the font named [resourceName] ([fontDict]) on
  /// [page], or null when the font isn't an Identity-H / CIDFontType2 /
  /// Identity-CIDToGIDMap composite this path can safely rewrite.
  static _Type0RunEditor? tryCreate(PdfEditor editor, PdfPage page,
      String resourceName, CosDictionary fontDict,
      List<PdfEmbeddedFont> fallbacks) {
    final font = Type0Font.forEditing(editor.document.cos, fontDict);
    return font == null
        ? null
        : _Type0RunEditor._(editor, page, resourceName, font, fallbacks);
  }

  /// Rewrites one run of show operators (active font size [fontSize]),
  /// replacing [find] with [replace]. Returns the operations to emit and how
  /// many replacements were made (the originals, untouched, when nothing
  /// matched or the replacement can be drawn by neither the document font
  /// nor a fallback).
  (List<ContentOperation>, int) rewriteRun(List<ContentOperation> run,
      String find, String replace, double fontSize) {
    // pick the font that can draw the whole replacement: the document's own
    // font when it has every glyph, else a style-matched fallback. (An empty
    // replacement - deletion - needs no font.)
    final runes = replace.runes.toList();
    final origOk = runes.every(_font.canDraw);
    // A run with any non-show operator (a structured text object, e.g. the
    // per-glyph objects Chrome emits, often RTL inside /ReversedChars and
    // with /ActualText spans) must be rewritten in place: the codec flattens
    // every operator, keeps the surrounding structure, and tracks the logical
    // (ActualText) text per glyph so RTL replacements still match.
    final structured = _Type0TaggedRunCodec.isStructured(run);
    if (origOk || replace.isEmpty) {
      final codec = structured
          ? _Type0TaggedRunCodec(_font)
          : _Type0RunCodec(_font);
      return TextRunRewriter(codec).rewrite(run, find, replace);
    }
    final fallback = _font.pickFallback(runes, _fallbacks);
    if (fallback == null) return (run, 0); // nobody can draw it

    // Allocate the fallback page /Font resource and encode the replacement
    // lazily, on the first match: a run where [find] does not occur (or which
    // is skipped for an odd-length string) must reserve no resource, record no
    // glyphs, and leave the page unchanged.
    _FallbackDraw resolve(String text) {
      final fbName = _fallbackName(fallback);
      final fbBytes = _hexToBytes(fallback.encodeHex(text));
      var fbWidth = 0.0;
      for (final rune in text.runes) {
        fbWidth += fallback.advanceForGlyph(fallback.glyphForRune(rune));
      }
      return _FallbackDraw(fbName, fbBytes, fbWidth);
    }

    final codec = structured
        ? _Type0TaggedRunCodec(_font,
            resourceName: resourceName,
            fontSize: fontSize,
            resolve: resolve)
        : _Type0FallbackCodec(_font, resourceName, fontSize, resolve);
    return TextRunRewriter(codec).rewrite(run, find, replace);
  }

  /// The page /Font resource name for [fallback], allocating one (and
  /// starting a fresh glyph accumulation) on first use.
  String _fallbackName(PdfEmbeddedFont fallback) {
    final existing = _usedFallbacks[fallback];
    if (existing != null) return existing;
    fallback.resetUsage();
    final fonts = _fontResources();
    var i = 0;
    while (fonts.containsKey('Fbk$i') || _allocatedNames.contains('Fbk$i')) {
      i++;
    }
    final name = 'Fbk$i';
    _allocatedNames.add(name);
    _usedFallbacks[fallback] = name;
    return name;
  }

  /// The page's own (materialized) /Font resource dictionary.
  CosDictionary _fontResources() {
    if (_fontResourcesCache != null) return _fontResourcesCache!;
    final cos = _editor.document.cos;
    final res = _editor._ownResources(page);
    final existing = cos.resolve(res['Font']);
    final fonts = CosDictionary(
        {if (existing is CosDictionary) ...existing.entries});
    res['Font'] = fonts;
    return _fontResourcesCache = fonts;
  }

  /// Writes the document font's new glyphs into its `/W` and `/ToUnicode`,
  /// and registers every fallback font used as a page /Font resource. Call
  /// once, after all runs.
  void commit() {
    final updater = _editor._updater;
    _font.commitFontDict(updater);
    // embed each used fallback as a page /Font resource (the page's own
    // resources were materialized when the name was allocated, so the new
    // entries persist with the page rewrite).
    _usedFallbacks.forEach((font, name) {
      final built = font.buildResource(updater.addObject).entries.values.first;
      _fontResources()[name] = updater.addObject(built);
      PdfPerf.add(PdfPerfCount.fallbackFontEmbedded);
    });
  }

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i + 1 < hex.length; i += 2) {
      out[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return out;
  }
}

/// The in-the-document-font Type0 codec: replacement codes are the font's own
/// glyph ids, drawn as 2-byte Identity-H show strings.
class _Type0RunCodec extends RunCodec {
  _Type0RunCodec(this._font);
  final Type0Font _font;

  @override
  bool shouldSkip(List<ContentOperation> run) => type0RunHasOddString(run);

  @override
  List<RunItem> flatten(List<ContentOperation> run) =>
      [for (final c in type0RunCells(run)) CellItem(c)];

  // a code with no /ToUnicode entry gets a sentinel `find` can't contain, so
  // matches never span it.
  @override
  String glyphText(int glyph) => _font.codeToText[glyph] ?? '￿';

  @override
  double glyphWidth(int glyph) => _font.widthOf(glyph);

  @override
  void emitReplacement(
      List<Emit> out, String replace, double oldWidth, bool hasTrailing) {
    var newWidth = 0.0;
    for (final rune in _visualOrderFor(replace).runes) {
      if (rune == 0x20 &&
          _font.codeForRune(rune) == null &&
          _font.glyphForRune(rune) == 0) {
        // the font never draws a space - advance past it instead (its /ToUnicode
        // carries no space, so nothing to record). A negative kern moves the
        // pen right by [spaceWidth].
        final w = _font.spaceWidth();
        out.add(CellEmit((glyph: null, kern: -w)));
        newWidth += w;
        continue;
      }
      final gid = _font.codeFor(rune);
      out.add(CellEmit((glyph: gid, kern: null)));
      newWidth += _font.recordGlyph(gid, rune);
    }
    if (hasTrailing && (newWidth - oldWidth).abs() >= 0.001) {
      out.add(CellEmit((glyph: null, kern: newWidth - oldWidth)));
    }
  }

  @override
  List<ContentOperation> assemble(
          List<ContentOperation> run, List<Emit> out) =>
      RunCodec.coalesce(run, out,
          putGlyph: _putType0Glyph, makeString: _hexShowString);
}

/// The fallback-font Type0 codec: the replacement is drawn in a bundled
/// fallback face between `Tf` switches, with the unchanged surrounding text
/// staying in the document's own font.
class _Type0FallbackCodec extends RunCodec {
  _Type0FallbackCodec(
      this._font, this._resourceName, this._fontSize, this._resolve);

  final Type0Font _font;
  final String _resourceName; // base font, restored after a fallback segment
  final double _fontSize;

  /// Allocates the fallback resource + encodes the replacement, run once on
  /// the first match so a non-matching run reserves nothing.
  final _FallbackDraw Function(String) _resolve;
  _FallbackDraw? _draw;

  bool _inFallback = false;
  double? _pendingKern;

  @override
  bool shouldSkip(List<ContentOperation> run) => type0RunHasOddString(run);

  @override
  List<RunItem> flatten(List<ContentOperation> run) =>
      [for (final c in type0RunCells(run)) CellItem(c)];

  @override
  String glyphText(int glyph) => _font.codeToText[glyph] ?? '￿';

  @override
  double glyphWidth(int glyph) => _font.widthOf(glyph);

  /// Restores the base font (if a fallback segment is open) and flushes the
  /// pending compensation kern into the base-font context.
  void _restoreBase(List<Emit> out) {
    if (_inFallback) {
      out.add(OpEmit(PdfContentEditing._tfOp(_resourceName, _fontSize)));
      _inFallback = false;
    }
    if (_pendingKern != null) {
      out.add(CellEmit((glyph: null, kern: _pendingKern)));
      _pendingKern = null;
    }
  }

  @override
  void emitReplacement(
      List<Emit> out, String replace, double oldWidth, bool hasTrailing) {
    final draw = _draw ??= _resolve(_visualOrderFor(replace));
    _restoreBase(out);
    out
      ..add(OpEmit(PdfContentEditing._tfOp(draw.name, _fontSize)))
      ..add(OpEmit(
          ContentOperation('Tj', [CosString(draw.bytes, isHex: true)])));
    _inFallback = true;
    if (hasTrailing && (draw.width - oldWidth).abs() >= 0.001) {
      _pendingKern = draw.width - oldWidth;
    }
  }

  @override
  void beforePassthrough(List<Emit> out) => _restoreBase(out);

  @override
  void finish(List<Emit> out) => _restoreBase(out);

  @override
  List<ContentOperation> assemble(
          List<ContentOperation> run, List<Emit> out) =>
      RunCodec.coalesce(run, out,
          putGlyph: _putType0Glyph, makeString: _hexShowString);
}

/// A codec for structured Type0 runs - text objects with operators beyond
/// `Tj`/`TJ`, such as the per-glyph `BT`...`ET` objects Chrome emits. It
/// rewrites the run in place: every non-show operator (BT, Tf, Tm, Td, BDC,
/// EMC, ...) is preserved, only the glyph strings change. Inside such an
/// object the glyphs are the visual (often RTL, reversed) order, so the codec
/// also records the logical text - the `/ActualText` of the enclosing BDC, or
/// the glyph's own /ToUnicode - per glyph for matching.
class _Type0TaggedRunCodec extends RunCodec {
  _Type0TaggedRunCodec(this._font,
      {String? resourceName, double? fontSize, _FallbackDraw Function(String)? resolve})
      : _resourceName = resourceName,
        _fontSize = fontSize,
        _resolve = resolve;

  final Type0Font _font;

  /// Base font name/size, restored after a fallback segment (null when the
  /// document font can always draw the replacement).
  final String? _resourceName;
  final double? _fontSize;
  final _FallbackDraw Function(String)? _resolve;
  _FallbackDraw? _fallbackDraw;

  bool _inFallback = false;
  double? _pendingKern;

  bool _rtl = false; // inside /ReversedChars - glyphs are in visual order
  String? _pendingActual; // /ActualText of the next glyph
  final List<String?> _actuals = []; // logical text per glyph

  /// True when [run] contains operators beyond the flat `Tj`/`TJ` shows that
  /// the plain [Type0Font] codecs rewrite.
  static bool isStructured(List<ContentOperation> run) {
    for (final op in run) {
      if (op.operator != 'Tj' && op.operator != 'TJ') return true;
    }
    return false;
  }

  @override
  bool shouldSkip(List<ContentOperation> run) => type0RunHasOddString(run);

  @override
  bool get glyphsInVisualOrder => _rtl;

  @override
  List<RunItem> flatten(List<ContentOperation> run) {
    _rtl = false;
    _pendingActual = null;
    _actuals.clear();
    final items = <RunItem>[];
    void addGlyphs(Uint8List bytes) {
      for (var i = 0; i + 1 < bytes.length; i += 2) {
        final code = (bytes[i] << 8) | bytes[i + 1];
        _actuals.add(_pendingActual);
        _pendingActual = null;
        items.add(CellItem((glyph: code, kern: null)));
      }
    }

    for (final op in run) {
      if (op.operator == 'Tj' || op.operator == 'TJ') {
        if (op.operator == 'Tj') {
          if (op.operands.isNotEmpty && op.operands[0] is CosString) {
            addGlyphs((op.operands[0] as CosString).bytes);
          }
        } else if (op.operands.isNotEmpty && op.operands[0] is CosArray) {
          for (final item in (op.operands[0] as CosArray).items) {
            switch (item) {
              case CosString(:final bytes):
                addGlyphs(bytes);
              case CosInteger(:final value):
                items.add(CellItem((glyph: null, kern: value.toDouble())));
              case CosReal(:final value):
                items.add(CellItem((glyph: null, kern: value)));
              default:
                break;
            }
          }
        }
      } else if (op.operator == 'BMC' || op.operator == 'BDC') {
        if (op.operator == 'BMC' &&
            op.operands.isNotEmpty &&
            op.operands[0] is CosName &&
            (op.operands[0] as CosName).value == 'ReversedChars') {
          _rtl = true;
        }
        if (op.operator == 'BDC' && op.operands.length >= 2) {
          final props = op.operands[1];
          if (props is CosDictionary) {
            final actual = _actualTextOf(props);
            if (actual != null) _pendingActual = actual;
          }
        }
        items.add(OpItem(op));
      } else {
        items.add(OpItem(op));
      }
    }
    return items;
  }

  @override
  String glyphText(int glyph) => _font.codeToText[glyph] ?? '￿';

  /// The logical text of glyph [glyphIndex]: its /ToUnicode (what extraction
  /// and copying present) or, when the glyph has no /ToUnicode entry, its
  /// /ActualText. Used to match inside RTL runs, where glyphs are in visual
  /// order. The /ToUnicode stays authoritative - Chrome's /ActualText can
  /// spell a letter differently (a heh form) than its own /ToUnicode, and
  /// the user searches the /ToUnicode spelling.
  @override
  String logicalGlyphText(int glyphIndex, int glyph) {
    final code = _font.codeToText[glyph];
    if (code != null && code != '￿') return code;
    final actual = glyphIndex < _actuals.length ? _actuals[glyphIndex] : null;
    return actual ?? '￿';
  }

  @override
  double glyphWidth(int glyph) => _font.widthOf(glyph);

  /// Restores the base font (if a fallback segment is open) and flushes the
  /// pending compensation kern into the base-font context.
  void _restoreBase(List<Emit> out) {
    if (_inFallback) {
      out.add(OpEmit(PdfContentEditing._tfOp(_resourceName!, _fontSize!)));
      _inFallback = false;
    }
    if (_pendingKern != null) {
      out.add(CellEmit((glyph: null, kern: _pendingKern)));
      _pendingKern = null;
    }
  }

  @override
  void emitReplacement(
      List<Emit> out, String replace, double oldWidth, bool hasTrailing) {
    _restoreBase(out);
    // The extractor's BiDi pass reverses RTL spans in every context, so a
    // replacement must always be drawn in visual order to round-trip.
    final visual = _visualOrderFor(replace);
    final draw = _resolve != null && !visual.runes.every(_font.canDraw)
        ? (_fallbackDraw ??= _resolve(visual))
        : null;
    if (draw != null) {
      // the document font lacks a glyph - draw the whole replacement in the
      // fallback face, between Tf switches.
      out
        ..add(OpEmit(PdfContentEditing._tfOp(draw.name, _fontSize!)))
        ..add(OpEmit(
            ContentOperation('Tj', [CosString(draw.bytes, isHex: true)])));
      _inFallback = true;
      if (hasTrailing && (draw.width - oldWidth).abs() >= 0.001) {
        _pendingKern = draw.width - oldWidth;
      }
      return;
    }
    // draw the replacement in the document's own font.
    var newWidth = 0.0;
    for (final rune in visual.runes) {
      if (rune == 0x20 &&
          _font.codeForRune(rune) == null &&
          _font.glyphForRune(rune) == 0) {
        final w = _font.spaceWidth();
        out.add(CellEmit((glyph: null, kern: -w)));
        newWidth += w;
        continue;
      }
      final gid = _font.codeFor(rune);
      out.add(CellEmit((glyph: gid, kern: null)));
      newWidth += _font.recordGlyph(gid, rune);
    }
    if (hasTrailing && (newWidth - oldWidth).abs() >= 0.001) {
      out.add(CellEmit((glyph: null, kern: newWidth - oldWidth)));
    }
  }

  @override
  void beforePassthrough(List<Emit> out) => _restoreBase(out);

  @override
  void finish(List<Emit> out) => _restoreBase(out);

  @override
  List<ContentOperation> assemble(
          List<ContentOperation> run, List<Emit> out) =>
      RunCodec.coalesce(run, out,
          putGlyph: _putType0Glyph, makeString: _hexShowString);
}

enum _BidiKind { rtl, ltr, neutral }

/// The drawn glyph order that makes the extractor's BiDi pass recover
/// [logical] back. The extractor reverses RTL spans and, for an RTL line, the
/// span order; that pass is an involution, so the same grouping and reversal
/// applied to the logical text yields the visual text to draw.
String _visualOrderFor(String logical) {
  final runes = logical.runes.toList();
  var rtlCount = 0;
  var total = 0;
  var previous = _BidiKind.neutral;
  final groups = <(_BidiKind, List<int>)>[];
  for (final rune in runes) {
    total++;
    final kind = _kindOf(rune, previous);
    if (kind == _BidiKind.rtl) rtlCount++;
    if (groups.isNotEmpty && groups.last.$1 == kind) {
      groups.last.$2.add(rune);
    } else {
      groups.add((kind, [rune]));
    }
    previous = kind;
  }
  if (rtlCount == 0) return logical;
  final rightToLeft = rtlCount > total * 0.3;
  final out = <int>[];
  for (final group in rightToLeft ? groups.reversed : groups) {
    if (group.$1 == _BidiKind.rtl) {
      out.addAll(group.$2.reversed);
    } else {
      out.addAll(group.$2);
    }
  }
  return String.fromCharCodes(out);
}

_BidiKind _kindOf(int rune, _BidiKind previous) {
  if ((rune >= 0x10800 && rune <= 0x10FFF) ||
      (rune >= 0x1E800 && rune <= 0x1EDFF)) {
    return _BidiKind.rtl;
  }
  return switch (bidi.getCharacterType(rune)) {
    bidi.CharacterType.rtl ||
    bidi.CharacterType.al ||
    bidi.CharacterType.rle ||
    bidi.CharacterType.rlo ||
    bidi.CharacterType.rli =>
      _BidiKind.rtl,
    bidi.CharacterType.ltr ||
    bidi.CharacterType.lre ||
    bidi.CharacterType.lro ||
    bidi.CharacterType.lri ||
    bidi.CharacterType.en ||
    bidi.CharacterType.an =>
      _BidiKind.ltr,
    bidi.CharacterType.nonspacingMark => previous,
    _ => _BidiKind.neutral,
  };
}

/// The /ActualText of a BDC property dictionary: a UTF-16BE string (its BOM,
/// if any, is skipped) or null when untagged.
String? _actualTextOf(CosDictionary props) {
  final at = props['ActualText'];
  if (at is! CosString) return null;
  final bytes = at.bytes;
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add((bytes[i] << 8) | bytes[i + 1]);
  }
  if (units.isNotEmpty && units.first == 0xFEFF) units.removeAt(0);
  return String.fromCharCodes(units);
}

/// The resolved fallback draw for a [_Type0FallbackCodec]: the page /Font
/// resource name to draw the replacement in, the pre-encoded (hex) show bytes,
/// and the replacement's advance (thousandths of an em).
class _FallbackDraw {
  _FallbackDraw(this.name, this.bytes, this.width);
  final String name;
  final Uint8List bytes;
  final double width;
}

void _putType0Glyph(int glyph, List<int> buffer) => buffer
  ..add(glyph >> 8)
  ..add(glyph & 0xFF);

CosString _hexShowString(List<int> buffer) =>
    CosString(Uint8List.fromList(buffer), isHex: true);
