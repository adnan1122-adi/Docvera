import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'save_target.dart';

/// A minimal shell over the DartPDF engine's [PdfEditorView].
///
/// It only wires the pieces needed to exercise the workflow under test:
///  - import + render + interactive editing come from the engine's own
///    widget (its toolbar carries the content/text tool, highlight tool,
///    freehand ink tool, and a header Save button reported via [onSave]);
///  - the action bar below adds deterministic engine-level operations
///    (programmatic text rewrite, a Highlight annotation, an Ink/freehand
///    annotation) and the "save -> reopen -> verify" round trip.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.bytes, required this.title});

  final Uint8List bytes;
  final String title;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final PdfEditingController _editing;
  late final PdfViewerController _viewer;
  final List<String> _logLines = <String>[];
  SavedTarget? _saved;
  late String _baselineText;

  static const String _find = 'FIND_ME_PROGRAMMATIC';
  static const String _replace = 'AFTER_PROGRAMMATIC_EDIT';

  @override
  void initState() {
    super.initState();
    _editing = PdfEditingController(widget.bytes);
    _viewer = PdfViewerController();
    _baselineText = _editing.document.pageCount > 0
        ? PdfTextExtractor.extract(_editing.document, 0).text
        : '';
    _log('Loaded ${widget.bytes.length} bytes '
        '(${_editing.document.pageCount} page(s)): ${widget.title}');
  }

  @override
  void dispose() {
    _editing.dispose();
    _viewer.dispose();
    super.dispose();
  }

  void _log(String line) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    _logLines.insert(0, '[$stamp] $line');
    if (_logLines.length > 80) _logLines.removeRange(80, _logLines.length);
  }

  /// Rewrites an existing text run in place through the engine.
  Future<void> _testTextReplace() async {
    final fallbacks = await loadFallbackFonts();
    final harnessFonts = fallbacks;
    final ok = _editing.apply(
      (e) => e.replaceText(0, _find, _replace, fallbackFonts: harnessFonts),
    );
    _log(ok
        ? 'replaceText: rewrote "$_find" -> "$_replace" on page 0'
        : 'replaceText: no textual change registered on page 0');
    setState(() {});
  }

  /// Adds a Highlight annotation across a line using the engine.
  void _testAddHighlight() {
    final page = _viewer.currentPage;
    final box = _editing.document.page(page).mediaBox;
    if (box.width <= 0 || box.height <= 0) {
      _log('Cannot highlight page $page: bad media box');
      return;
    }
    final quad = PdfRect(
      box.left + box.width * 0.05,
      box.top - box.height * 0.33,
      box.left + box.width * 0.60,
      box.top - box.height * 0.30,
    );
    final ok = _editing.apply(
      (e) => e.addHighlight(page, [quad],
          color: 0xFFD100, opacity: 0.5, author: 'dartpdf harness'),
    );
    _log(ok ? 'Highlight annotation added on page $page at $quad'
        : 'Highlight annotation failed');
    setState(() {});
  }

  /// Adds a freehand (Ink) annotation stroke using the engine.
  void _testAddInk() {
    final page = _viewer.currentPage;
    final box = _editing.document.page(page).mediaBox;
    if (box.width <= 0 || box.height <= 0) {
      _log('Cannot ink page $page: bad media box');
      return;
    }
    final stroke = <(double, double)>[];
    for (var i = 0; i <= 60; i++) {
      final t = i / 60;
      final x = box.left + box.width * (0.12 + 0.76 * t);
      final y = box.top - box.height * (0.45 + 0.03 * math.sin(t * math.pi * 8));
      stroke.add((x, y));
    }
    final ok = _editing.apply(
      (e) => e.addInk(page, [stroke],
          color: 0x2070F0, strokeWidth: 2.0, author: 'dartpdf harness'),
    );
    _log(ok
        ? 'Freehand Ink annotation added on page $page '
            '(${stroke.length} control points)'
        : 'Ink annotation failed');
    setState(() {});
  }

  /// Saves the current revision, re-opens the saved PDF and extracts its text
  /// and lists its annotations, then reports the results.
  Future<void> _saveReopenVerify() async {
    final bytes = Uint8List.fromList(_editing.bytes);
    final target = await persistPdf(bytes, 'verified');
    _log('Saved ${bytes.length} bytes -> ${target.label} — reopening');
    await _reopenAndReport(target);
  }

  /// Reopens [target] (the saved PDF) and verifies the edits that were made
  /// in this session against what persisted.
  Future<void> _reopenAndReport(SavedTarget target) async {
    final onDisk = await loadPdf(target);
    final reopened = PdfDocument.open(onDisk);
    final buffer = StringBuffer()
      ..writeln('Reopened ${target.label}')

      ..writeln('saved bytes: ${onDisk.length}')
      ..writeln('pages: ${reopened.pageCount}');

    var highlightCount = 0;
    var inkCount = 0;
    var newPhrasePresent = false;
    var oldPhrasePresent = false;
    for (var i = 0; i < reopened.pageCount; i++) {
      final pageText = PdfTextExtractor.extract(reopened, i).text;
      if (i == 0) {
        oldPhrasePresent = pageText.contains(_find);
        newPhrasePresent = pageText.contains(_replace);
      }
      buffer
        ..writeln()
        ..writeln('==== Page ${i + 1} text ====')
        ..writeln(pageText.isEmpty ? '(no extractable text)' : pageText);
      for (final a in reopened.page(i).annotations) {
        buffer.writeln('  annotation ${a.subtype} color=0x'
            '${(a.color ?? 0).toRadixString(16).padLeft(6, '0')} rect=$a');
        if (a.subtype == 'Highlight') highlightCount++;
        if (a.subtype == 'Ink') inkCount++;
      }
    }

    final textWasEdited = _baselineText !=
        PdfTextExtractor.extract(reopened, 0).text;
    final textEditPersisted = newPhrasePresent || !oldPhrasePresent || textWasEdited;
    buffer
      ..writeln()
      ..writeln('--- verification result ---')
      ..writeln('text edited in this session        : $textWasEdited')
      ..writeln('original phrase still findable     : $oldPhrasePresent')
      ..writeln('replacement phrase present         : $newPhrasePresent')
      ..writeln('=> text modification persisted     : $textEditPersisted')
      ..writeln('highlight annotations on disk     : $highlightCount')
      ..writeln('highlight persisted               : ${highlightCount > 0}')
      ..writeln('ink (freehand) annotations on disk: $inkCount')
      ..writeln('freehand persisted                : ${inkCount > 0}');

    _log('Verify of ${target.label} complete: textPersisted=$textEditPersisted '
        'highlights=$highlightCount inks=$inkCount');
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save -> reopen -> verify'),
        content: SingleChildScrollView(
          child: SelectionArea(
            child: Text(buffer.toString(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Reopens the last PDF saved by the engine's own Save button.
  Future<void> _reopenSaved() async {
    final saved = _saved;
    if (saved == null) return;
    await _reopenAndReport(saved);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Event log',
            onPressed: _showLog,
            icon: const Icon(Icons.notes),
          ),
          IconButton(
            tooltip: 'Reopen last saved file & verify',
            onPressed: _reopenSaved,
            icon: const Icon(Icons.fact_check),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              _testButton('Edit text', Icons.find_replace, _testTextReplace),
              _testButton('Highlight', Icons.border_color, _testAddHighlight),
              _testButton('Freehand ink', Icons.gesture, _testAddInk),
              _testButton('Save→reopen→verify', Icons.verified_user,
                  _saveReopenVerify),
            ],
          ),
        ),
      ),
      body: PdfEditorView(
        controller: _editing,
        viewerController: _viewer,
        documentId: widget.title,
        onSave: _onEngineSave,
      ),
    );
  }

  Widget _testButton(String label, IconData icon, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  /// Called by the engine's own Save button in the header bar.
  Future<void> _onEngineSave(Uint8List bytes) async {
    final target = await persistPdf(bytes, 'saved');
    _saved = target;
    _log('Engine Save button wrote ${bytes.length} bytes -> ${target.label}');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved -> ${target.label}')),
    );
  }

  Future<void> _showLog() async {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Event log'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Text(_logLines.isEmpty ? "(nothing yet)" : _logLines.join('\n'),
                style: const TextStyle(fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}