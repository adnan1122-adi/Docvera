import 'dart:async';
import 'dart:math' as math;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf_cos/pdf_cos.dart' show CosInteger, CosObject, CosReal;
import 'package:pdf_document/pdf_document.dart'
    show
        PdfAnnotationEditing,
        PdfContentElement,
        PdfElementKind,
        PdfRect,
        PdfTextStyle;
import 'package:pdf_graphics/pdf_graphics.dart'
    show PdfExtractedRun, PdfTextExtractor;
import 'package:shared_preferences/shared_preferences.dart';

import '../fill_sign/fill_sign_dialogs.dart';
import '../fill_sign/fill_sign_overlay.dart';
import '../fill_sign/fill_sign_picker.dart';
import '../fill_sign/fill_sign_service.dart';
import '../fill_sign/fill_sign_store.dart';
import '../fill_sign/fill_sign_toolbar.dart';
import '../models/recent_document.dart';
import '../services/document_io.dart';
import '../services/recent_store.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../tools/pdf_tool_util.dart';
import 'pages_panel.dart';
import 'style_popover.dart';

/// The full-screen editor. The engine's own chrome drives editing: the
/// header bar (search, page number, zoom, panel toggles), the toolbar with
/// every tool group (select, markup, draw, shapes, text/insert, measure
/// with all its tools, edit text & style, form, link, redact, snapshot),
/// and the resizable dockable panels (thumbnails, bookmarks, annotations,
/// properties, search results). A slim custom app bar supplies back
/// navigation, the document name, save state, and the save/export/share
/// actions.
class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.title,
    required this.bytes,
    this.controller,
    this.recent,
    this.recentStore,
    this.saveToPath,
    this.saveAsPdf,
    this.persistForRecents,
    this.sharePdf,
  });

  final String title;
  final Uint8List bytes;

  /// Optional pre-built controller (used by tests to select elements and
  /// inspect the committed document). When null the screen builds and owns
  /// one from [bytes].
  final PdfEditingController? controller;

  /// The recent entry this document was opened from (if any). Save then
  /// writes back over this copy so the recent document stays current.
  final RecentDocument? recent;

  /// Persistence for the recent-documents list. When null the screen uses
  /// its own [RecentStore]. Tests inject one to observe saved entries.
  final RecentStore? recentStore;

  // I/O seams for tests, defaulting to the real [DocumentIo] calls.
  final Future<void> Function(String path, Uint8List bytes)? saveToPath;
  final Future<PdfSaveOutcome> Function(Uint8List bytes, String suggestedName)?
      saveAsPdf;
  final Future<RecentDocument> Function(PickedPdf pdf)? persistForRecents;
  final Future<void> Function(Uint8List bytes, String name)? sharePdf;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

/// What to do with unsaved changes when leaving the editor.
enum _SaveChoice { save, discard, cancel }

class _EditorScreenState extends State<EditorScreen> {
  // Every feature on - the engine provides the complete editor surface.
  static const PdfEditorFeatures _features = PdfEditorFeatures();

  late PdfEditingController? _editing;
  bool _error = false;

  /// The viewer shared with [PdfEditorView] and the full-screen page
  /// manager, so page operations and navigation stay in sync.
  final PdfViewerController _viewer = PdfViewerController();

  // An active in-place text edit: while set, the page overlay reports the
  // selected text's on-screen box (in this screen's Stack coordinates) and a
  // Positioned editor floats above the engine's editing layer so it can
  // actually receive pointer and keyboard input.
  _PdfInPlaceEdit? _inPlaceEdit;

  /// The editor box in this screen's Stack coordinates; null until the page
  /// overlay has measured the selected text run.
  Rect? _editRect;

  /// The edit box's position in page space (y-up), anchored to the selected
  /// run and adjustable by nudging/dragging. The commit places the text here.
  PdfRect? _editPageRect;

  /// Whether the user nudged/dragged the box off its original spot - after
  /// that the page overlay stops re-anchoring to the element bounds.
  bool _editMoved = false;

  /// Page-space -> this screen's Stack coordinates (used to keep the box
  /// glued to [_editPageRect] and to convert nudge deltas).
  Matrix4? _pageToBodyMatrix;

  /// This screen's Stack -> page-space (used to convert drag deltas).
  Matrix4? _bodyToPageMatrix;

  /// Key for the editor's own Stack so the page overlay can convert page
  /// geometry into this screen's coordinates.
  final GlobalKey _bodyKey = GlobalKey();

  /// Whether the dedicated Fill & Sign mode is active (its contextual
  /// toolbar replaces the full editor toolbar).
  bool _fillSignActive = false;

  /// The armed Fill & Sign "place" mode: while set, the page overlay turns a
  /// tap into one of the custom Fill & Sign objects. Null otherwise.
  FillSignPlaceConfig? _placeConfig;

  /// Local on-device library of saved signatures/initials (SharedPreferences).
  FillSignStore? _fillSignStore;

  // -------------------------------------------------- document save state

  /// The name shown in the title bar; changes when the user uses Save As.
  late String _displayName = widget.title;

  /// The bytes of the last persisted revision, or the opened bytes before
  /// anything is saved. Dirty = current bytes differ from this snapshot.
  Uint8List? _savedBytes;

  /// The recent entry the document is currently saved under (path on native,
  /// base64 on web), or null before the first save.
  RecentDocument? _saveTarget;

  bool _dirty = false;
  bool _saving = false;
  bool _sharing = false;
  bool _forceClose = false;

  /// Cache key for the (cheap) byte comparison that drives [_dirty], so a
  /// full compare only runs when the edit history actually moved.
  int _dirtyKeyRevision = -1;
  bool _dirtyKeyModified = false;
  bool _dirtyKeyCanUndo = false;
  bool _dirtyKeyCanRedo = false;

  late final RecentStore _recentStore = widget.recentStore ?? RecentStore();

  bool get hasUnsavedChanges => _dirty;

  PdfEditingController get editing => _editing!;

  @override
  void initState() {
    super.initState();
    _editing = widget.controller;
    if (_editing == null) {
      try {
        _editing = PdfEditingController(widget.bytes);
      } catch (_) {
        _error = true;
      }
    }
    _editing?.addListener(_onChanged);
    // The opened bytes are the last-persisted state, so the document starts
    // clean.
    _savedBytes = _editing?.bytes;
    _saveTarget = widget.recent?.canOpen ?? false ? widget.recent : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureFillSignStore();
    });
  }

  @override
  void dispose() {
    _editing?.removeListener(_onChanged);
    _viewer.dispose();
    if (widget.controller == null) {
      _editing?.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    _dirty = _refreshDirty();
    // The engine may notify synchronously while the tree is still building
    // (e.g. PdfEditorView's initState), so never call setState directly
    // here - defer to the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  /// Recomputes whether the current bytes differ from the last persisted
  /// snapshot. Only runs the byte comparison when the edit history moved
  /// (a commit, an undo/redo, or a hard reset like redaction).
  bool _refreshDirty() {
    final editing = _editing;
    if (editing == null) return _dirty;
    final rev = editing.revisionId;
    final modified = editing.isModified;
    final canUndo = editing.canUndo;
    final canRedo = editing.canRedo;
    if (rev == _dirtyKeyRevision &&
        modified == _dirtyKeyModified &&
        canUndo == _dirtyKeyCanUndo &&
        canRedo == _dirtyKeyCanRedo) {
      return _dirty;
    }
    _dirtyKeyRevision = rev;
    _dirtyKeyModified = modified;
    _dirtyKeyCanUndo = canUndo;
    _dirtyKeyCanRedo = canRedo;
    final saved = _savedBytes;
    if (saved == null) {
      return modified;
    }
    return !listEquals(saved, editing.bytes);
  }

  // ------------------------------------------------------- Fill & Sign mode

  Future<void> _ensureFillSignStore() async {
    if (_fillSignStore != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) setState(() => _fillSignStore = FillSignStore(prefs));
    } catch (_) {
      // No persisted library (storage unavailable) - the mode still works,
      // it just cannot remember saved signatures/initials.
    }
  }

  void _toggleFillSign(BuildContext context, PdfEditingController? controller) {
    setState(() {
      _fillSignActive = !_fillSignActive;
      if (!_fillSignActive) _placeConfig = null;
    });
    if (_fillSignActive && controller != null) {
      controller.clearAnnotationSelection();
      controller.tool = PdfEditTool.select;
    }
  }

  /// Arms an engine tool and clears any armed place-mode.
  void _armEngineTool(
    PdfEditingController controller,
    PdfEditTool tool, {
    bool clearPlacing = true,
  }) {
    if (!mounted) return;
    if (clearPlacing) setState(() => _placeConfig = null);
    controller.clearAnnotationSelection();
    controller.tool = tool;
  }

  /// Arms a place-mode: taps on the page create the object.
  void _armPlace(PdfEditingController controller, FillSignPlaceConfig config) {
    if (!mounted) return;
    setState(() => _placeConfig = config);
    controller.clearAnnotationSelection();
    controller.tool = null;
  }

  /// Creates the armed Fill & Sign object at ([x], [y]) in page space.
  void _placeAt(int page, double x, double y) {
    final cfg = _placeConfig;
    final editing = _editing;
    if (cfg == null || editing == null) return;
    try {
      switch (cfg.kind) {
        case FillSignPlaceKind.date:
          final text = cfg.text ?? _defaultDate();
          if (text.trim().isNotEmpty) {
            FillSignService.placeText(editing, page, x, y, text);
          }
        case FillSignPlaceKind.typedText:
          final text = cfg.text ?? '';
          if (text.trim().isNotEmpty) {
            FillSignService.placeText(editing, page, x, y, text);
          }
        case FillSignPlaceKind.drawnInk:
          final sig = cfg.signature;
          if (sig != null) {
            FillSignService.placeInk(editing, page, x, y, sig);
          }
        case FillSignPlaceKind.checkbox:
          FillSignService.placeCheckbox(editing, page, x, y);
        case FillSignPlaceKind.xMark:
          FillSignService.placeXMark(editing, page, x, y);
      }
    } catch (_) {
      // A corrupt page must never crash the editor.
    }
  }

  String _defaultDate() {
    final d = DateTime.now();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  Future<void> _signatureFlow(
    BuildContext context,
    PdfEditingController controller,
  ) async {
    final choice = await showFillSignLibrarySheet(
      context,
      title: 'Signature',
      load: () => _fillSignStore?.savedSignatures() ?? const [],
      remove: (entry) async => await _fillSignStore?.removeSignature(entry.name),
    );
    if (choice == null) return;
    if (!context.mounted) return;
    switch (choice.action) {
      case FillSignLibraryAction.drawNew:
        final sig = await showFillSignInkPad(
          context,
          title: 'Draw your signature',
          saveLabel: 'Save',
        );
        if (sig == null) return;
        if (!context.mounted) return;
        final name = await showFillSignNameDialog(context,
            title: 'Save signature', placeholder: 'My Signature');
        if (name != null) {
          await _fillSignStore?.saveSignature(SavedInk(
            name: name.isEmpty ? 'My Signature' : name,
            kind: SavedInkKind.drawn,
            signature: sig,
          ));
        }
        // Activate the engine's signature tool so the drawn signature can be
        // stamped onto the page with its native tap-to-place preview.
        controller.preferences.signature = sig;
        controller.color = Color(0xFF000000 | sig.color);
        _armEngineTool(controller, PdfEditTool.signature);
      case FillSignLibraryAction.typeNew:
        final text = await showFillSignTypeDialog(
          context,
          title: 'Type your signature',
          hint: 'Type your name (e.g. John Smith)',
        );
        if (text == null || text.isEmpty) return;
        await _fillSignStore?.saveSignature(SavedInk(
          name: 'My Signed Name',
          kind: SavedInkKind.typed,
          text: text,
        ));
        _armPlace(controller, FillSignPlaceConfig.text(text));
      case FillSignLibraryAction.saved:
        final entry = choice.entry;
        if (entry == null) return;
        final sig = entry.signature;
        if (entry.kind == SavedInkKind.drawn && sig != null) {
          controller.preferences.signature = sig;
          controller.color = Color(0xFF000000 | sig.color);
          _armEngineTool(controller, PdfEditTool.signature);
        } else if (entry.text != null) {
          _armPlace(controller, FillSignPlaceConfig.text(entry.text!));
        }
    }
  }

  Future<void> _initialsFlow(
    BuildContext context,
    PdfEditingController controller,
  ) async {
    final choice = await showFillSignLibrarySheet(
      context,
      title: 'Initials',
      load: () => _fillSignStore?.savedInitials() ?? const [],
      remove: (entry) async => await _fillSignStore?.removeInitials(entry.name),
    );
    if (choice == null) return;
    if (!context.mounted) return;
    switch (choice.action) {
      case FillSignLibraryAction.drawNew:
        final sig = await showFillSignInkPad(
          context,
          title: 'Draw your initials',
          saveLabel: 'Save',
        );
        if (sig == null) return;
        if (!context.mounted) return;
        final name = await showFillSignNameDialog(context,
            title: 'Save initials', placeholder: 'My Initials');
        if (name != null) {
          await _fillSignStore?.saveInitials(SavedInk(
            name: name.isEmpty ? 'My Initials' : name,
            kind: SavedInkKind.drawn,
            signature: sig,
          ));
        }
        _armPlace(controller, FillSignPlaceConfig.drawnInk(sig));
      case FillSignLibraryAction.typeNew:
        final text = await showFillSignTypeDialog(
          context,
          title: 'Type your initials',
          hint: 'e.g. JS',
        );
        if (text == null || text.isEmpty) return;
        await _fillSignStore?.saveInitials(SavedInk(
          name: 'My Initials',
          kind: SavedInkKind.typed,
          text: text,
        ));
        _armPlace(controller, FillSignPlaceConfig.text(text));
      case FillSignLibraryAction.saved:
        final entry = choice.entry;
        if (entry == null) return;
        final sig = entry.signature;
        if (entry.kind == SavedInkKind.drawn && sig != null) {
          _armPlace(controller, FillSignPlaceConfig.drawnInk(sig));
        } else if (entry.text != null) {
          _armPlace(controller, FillSignPlaceConfig.text(entry.text!));
        }
    }
  }

  Future<void> _dateFlow(
    BuildContext context,
    PdfEditingController controller,
  ) async {
    final date = await showFillSignDateDialog(context);
    if (date == null || date.trim().isEmpty) return;
    _armPlace(controller, FillSignPlaceConfig.date(date.trim()));
  }

  Widget _fillSignToolbarBuild(
    BuildContext context,
    PdfEditingController controller,
    PdfViewerController viewer,
  ) {
    return FillSignToolbar(
      controller: controller,
      viewerController: viewer,
      activeTool: controller.tool,
      placing: _placeConfig,
      hasFormFields: controller.acroForm?.fields.isNotEmpty ?? false,
      onSelect: () => _armEngineTool(controller, PdfEditTool.select),
      onText: () => _armEngineTool(controller, PdfEditTool.freeText),
      onSignature: () => _signatureFlow(context, controller),
      onInitials: () => _initialsFlow(context, controller),
      onDate: () => _dateFlow(context, controller),
      onCheckbox: () => _armPlace(
          controller, const FillSignPlaceConfig.checkbox()),
      onCheck: () => _armEngineTool(controller, PdfEditTool.count),
      onX: () => _armPlace(controller, const FillSignPlaceConfig.xMark()),
      onFields: () => _armEngineTool(controller, PdfEditTool.form),
      onStyle: () =>
          showPdfStylePopover(context, editing: controller, viewer: viewer),
      onUndo: controller.undo,
      onRedo: controller.redo,
      onDone: () => _toggleFillSign(context, controller),
    );
  }

  Widget _fillSignEntryButton(
    BuildContext context,
    PdfEditingController controller,
    PdfViewerController viewerController,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(
        _fillSignActive ? Icons.edit_note : Icons.edit_note_outlined,
        color: _fillSignActive ? scheme.primary : null,
      ),
      tooltip: 'Fill & Sign',
      onPressed: () => _toggleFillSign(context, controller),
    );
  }

  // ------------------------------------------------- in-place text editing

  /// Replaces the engine's plain text prompt: when a page-content text run is
  /// selected, edit it in place on the page instead of in a dialog.
  ///
  /// Built-in text runs can have exotic encodings (`PdfContentElement.text`
  /// is Latin-1-decoded, so it shows up garbled) that the engine's byte-level
  /// replacement cannot rewrite. A commit is therefore applied as a movable
  /// /FreeText overlay (see [_commitInPlaceEdit]) rather than in the content
  /// stream, and the engine's own global `replaceText` is skipped by
  /// returning null.
  Future<String?> _inPlaceTextPrompt(
    BuildContext context, {
    required String title,
    String initial = '',
    bool multiline = false,
  }) async {
    final anchor = selectedTextAnchor();
    if (anchor == null) {
      return showPdfTextPrompt(
        context,
        title: title,
        initial: initial,
        multiline: multiline,
      );
    }
    return _startInPlaceEdit(
      page: anchor.$1,
      elementId: anchor.$2,
      initial: initial,
      multiline: multiline,
    );
  }

  /// Replaces the engine's "Edit text & style" prompt: edit the selected
  /// page-content text run in place, returning a plain (style-preserving)
  /// replacement - the engine is passed null because single-run commits are
  /// applied as a movable /FreeText overlay (see [_commitInPlaceEdit]).
  Future<PdfStyledTextEdit?> _inPlaceStyledTextPrompt(
    BuildContext context, {
    required String initial,
    List<Color> palette = const [],
    PdfStyledFontPicker? pickFont,
  }) async {
    final anchor = selectedTextAnchor();
    if (anchor == null) {
      return showPdfStyledTextPrompt(
        context,
        initial: initial,
        palette: palette,
        pickFont: pickFont,
      );
    }
    return _startInPlaceEdit(
      page: anchor.$1,
      elementId: anchor.$2,
      initial: initial,
      multiline: false,
    ).then((text) {
      if (text == null || text == initial) return null;
      return PdfStyledTextEdit(text, const PdfTextStyle());
    });
  }

  /// The font size and nonstroking fill colour active for a page-content text
  /// run, recovered from the content operations leading up to its first op.
  /// Falls back to 12pt black when the stream carries no style markers.
  (double fontSize, int color) _elementTextStyle(int page, int elementId) {
    const fallback = (12.0, 0x000000);
    final editing = _editing;
    final element = _elementById(page, elementId);
    if (editing == null || element == null) return fallback;
    final ops = editing.elementsOn(page).operations;
    var fontSize = 12.0;
    var color = 0x000000;

    double channel(CosObject o) {
      final v = switch (o) {
        CosInteger(:final value) => value.toDouble(),
        CosReal(:final value) => value,
        _ => 0.0,
      };
      return v.clamp(0.0, 1.0);
    }

    // Font sizes are point values (typically 10-30), NOT 0-1 color channels.
    // Read the raw number and only sanity-clamp so a malformed stream can't
    // explode the committed FreeText box.
    double points(CosObject o) {
      final v = switch (o) {
        CosInteger(:final value) => value.toDouble(),
        CosReal(:final value) => value,
        _ => 0.0,
      };
      return v.clamp(1.0, 500.0);
    }

    int rgb(double r, double g, double b) =>
        ((r * 255).round() << 16) |
        ((g * 255).round() << 8) |
        (b * 255).round();

    for (var i = 0; i < ops.length && i < element.start; i++) {
      final op = ops[i];
      switch (op.operator) {
        case 'Tf':
          if (op.operands.length >= 2) {
            fontSize = points(op.operands[1]);
          }
        case 'rg':
          if (op.operands.length >= 3) {
            color = rgb(
              channel(op.operands[0]),
              channel(op.operands[1]),
              channel(op.operands[2]),
            );
          }
        case 'g':
          if (op.operands.isNotEmpty) {
            final v = (channel(op.operands[0]) * 255).round();
            color = (v << 16) | (v << 8) | v;
          }
        case 'k':
          if (op.operands.length >= 4) {
            final c = channel(op.operands[0]);
            final m = channel(op.operands[1]);
            final y = channel(op.operands[2]);
            final k = channel(op.operands[3]);
            color = rgb((1 - c) * (1 - k), (1 - m) * (1 - k), (1 - y) * (1 - k));
          }
        default:
          break;
      }
    }
    // The content-stream Tf size is exact for unscaled text, but pages that
    // draw text under a scale matrix (cm/Tm) render larger than the raw
    // size. The element's bounds already reflect the rendered line box (the
    // parser spans -0.2em..+1em, so height == 1.2*em), so prefer that.
    final bounds = element.bounds;
    if (bounds != null && bounds.height > 0) {
      final em = bounds.height / 1.2;
      if (em > 0) {
        fontSize = em.clamp(1.0, 500.0);
      }
    }
    return (fontSize, color);
  }

  PdfContentElement? _elementById(int page, int elementId) {
    final editing = _editing;
    if (editing == null) return null;
    final elements = editing.elementsOn(page).elements;
    return elementId >= 0 && elementId < elements.length
        ? elements[elementId]
        : null;
  }

  /// The readable text of a page-content text run, decoded via the page's
  /// text layer (ToUnicode). Falls back to null when extraction fails so the
  /// caller can keep the engine's Latin-1 [PdfContentElement.text].
  String? _realElementText(int page, int elementId) {
    final editing = _editing;
    final element = _elementById(page, elementId);
    if (editing == null || element == null) return null;
    final bounds = element.bounds;
    if (bounds == null || bounds.width <= 0 || bounds.height <= 0) return null;
    try {
      final pageText = PdfTextExtractor.extract(editing.document, page);
      final runs = <PdfExtractedRun>[];
      for (final run in pageText.runs) {
        final rb = run.bounds;
        // Overlap in page space (y-up). Build a reading-order buffer from the
        // runs sharing the element's box, then join them.
        final overlaps = !(rb.left >= bounds.right ||
            rb.right <= bounds.left ||
            rb.bottom >= bounds.top ||
            rb.top <= bounds.bottom);
        if (overlaps) runs.add(run);
      }
      if (runs.length == 1) return runs.first.text;
      if (runs.isEmpty) return null;
      runs.sort((a, b) {
        final dy = b.bounds.top.compareTo(a.bounds.top);
        return dy != 0 ? dy : a.bounds.left.compareTo(b.bounds.left);
      });
      return runs.map((r) => r.text).join();
    } catch (_) {
      return null;
    }
  }

  /// The selected page-content text run, if any - the anchor for in-place
  /// editing. Returns (page index, element id).
  (int, int)? selectedTextAnchor() {
    final editing = _editing;
    if (editing == null) return null;
    final element = editing.selectedElement;
    if (element == null || element.kind != PdfElementKind.text) return null;
    final page = editing.selectedElementPage;
    if (page == null) return null;
    return (page, element.id);
  }

  PdfRect? _elementBounds(int page, int elementId) {
    final editing = _editing;
    if (editing == null) return null;
    for (final element in editing.elementsOn(page).elements) {
      if (element.id == elementId) return element.bounds;
    }
    return null;
  }

  Future<String?> _startInPlaceEdit({
    required int page,
    required int elementId,
    required String initial,
    required bool multiline,
  }) async {
    // Show the readable ToUnicode text (the engine's Latin-1 decode of a
    // symbolic/composite run is garbled), falling back to what was offered.
    final real = _realElementText(page, elementId);
    final shown = (real == null || real.trim().isEmpty) ? initial : real;
    final completer = Completer<String?>();
    setState(() {
      _inPlaceEdit = _PdfInPlaceEdit(
        page: page,
        elementId: elementId,
        initial: shown,
        multiline: multiline,
        completer: completer,
      );
      _editRect = null;
      _editPageRect = null;
      _editMoved = false;
      _pageToBodyMatrix = null;
      _bodyToPageMatrix = null;
    });
    final result = await completer.future;
    if (mounted) {
      setState(() {
        _inPlaceEdit = null;
        _editRect = null;
        _editPageRect = null;
      });
    }
    return result;
  }

  /// Commits an in-place edit. Text edits are applied to the page as a
  /// movable /FreeText overlay: the original baked-in run is deleted (so the
  /// garbled original never shows through) and the new text is placed at the
  /// (possibly nudged) page-space box. The engine then never sees a changed
  /// result (the completer resolves null), so its own global replace is
  /// skipped. Multi-line (paragraph reflow) edits keep the engine's flow.
  void _commitInPlaceEdit(String? result) {
    final edit = _inPlaceEdit;
    if (edit == null) return;
    if (edit.multiline) {
      edit.completer.complete(result);
      return;
    }
    var rect = _editPageRect;
    final changed = result != null && result != edit.initial;
    final moved = _editMoved && rect != null;
    if (!changed && !moved) {
      edit.completer.complete(null);
      return;
    }
    // Resolve placement and style BEFORE mutating the page: once the element
    // is deleted its bounds/id are gone, and if the overlay never measured a
    // box we should keep the original text rather than delete it into
    // nothing.
    rect ??= _elementBounds(edit.page, edit.elementId);
    final box = rect;
    final (fontSize, color) = _elementTextStyle(edit.page, edit.elementId);
    if (changed && box == null) {
      edit.completer.complete(null);
      return;
    }
    try {
      // The run is still the engine's selection while the box is open.
      _editing?.deleteSelectedElement();
      if (result != null && result.isNotEmpty && box != null) {
        // Match the original run's size and colour unless the user styled
        // it differently; the FreeText lands plain Helvetica in those
        // colours, so the page keeps looking the same after the edit.
        _editing?.apply(
          (e) => e.addFreeText(
            edit.page,
            box,
            result,
            fontSize: fontSize,
            color: color,
          ),
        );
        // Select the committed box so it can be re-edited in place: with the
        // run deleted the page-content selection is gone, and without a
        // selection the annotation would need the Select tool to be reached.
        _editing?.selectAnnotationAt(
          edit.page,
          (box.left + box.right) / 2,
          (box.top + box.bottom) / 2,
        );
      }
    } catch (_) {
      // Leave the original text in place on failure.
    }
    edit.completer.complete(null);
  }

  void _nudgeInPlaceEdit(double dxPage, double dyPage) {
    final edit = _inPlaceEdit;
    final rect = _editPageRect;
    if (edit == null || rect == null) return;
    setState(() {
      _editMoved = true;
      _editPageRect = PdfRect(
        rect.left + dxPage,
        rect.bottom + dyPage,
        rect.right + dxPage,
        rect.top + dyPage,
      );
    });
    final matrix = _pageToBodyMatrix;
    final bodyRect = _editRect;
    if (matrix != null && bodyRect != null) {
      final delta = MatrixUtils.transformPoint(
            matrix,
            Offset(dxPage, dyPage),
          ) -
          MatrixUtils.transformPoint(matrix, Offset.zero);
      setState(() {
        _editRect = bodyRect.translate(delta.dx, delta.dy);
      });
    }
  }

  void _dragInPlaceEdit(Offset bodyDelta) {
    final edit = _inPlaceEdit;
    final rect = _editPageRect;
    final matrix = _bodyToPageMatrix;
    if (edit == null || rect == null || matrix == null) return;
    final pageDelta = MatrixUtils.transformPoint(matrix, bodyDelta) -
        MatrixUtils.transformPoint(matrix, Offset.zero);
    setState(() {
      _editMoved = true;
      _editPageRect = PdfRect(
        rect.left + pageDelta.dx,
        rect.bottom + pageDelta.dy,
        rect.right + pageDelta.dx,
        rect.top + pageDelta.dy,
      );
    });
    final bodyRect = _editRect;
    if (bodyRect != null) {
      setState(() {
        _editRect = bodyRect.translate(bodyDelta.dx, bodyDelta.dy);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty || _forceClose,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && mounted) _confirmSaveChanges(context);
      },
      child: Scaffold(
        appBar: _buildTopBar(context),
        body: _error ? _buildError(context) : _buildEditor(context),
      ),
    );
  }

  PreferredSizeWidget _buildTopBar(BuildContext context) {
    final editing = _editing;
    return AppBar(
      leadingWidth: 56,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Back',
        onPressed: () => _requestClose(context),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              _displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?_statePill(context),
        ],
      ),
      actions: [
        if (editing != null) ...[
          IconButton(
            key: const ValueKey('editor-save'),
            tooltip: _saving ? 'Saving…' : 'Save',
            onPressed: _saving ? null : () => _savePdf(editing.bytes),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : Icon(_dirty ? Icons.save : Icons.save_outlined),
          ),
          IconButton(
            icon: const Icon(Icons.grid_view_outlined),
            tooltip: 'Pages',
            onPressed: () => showPagesPanel(
                  context,
                  editing: editing,
                  viewer: _viewer,
                  documentName: _displayName,
                ),
          ),
          IconButton(
            icon: _fillSignActive
                ? const Icon(Icons.edit_note)
                : const Icon(Icons.edit_note_outlined),
            tooltip: 'Fill and Sign',
            onPressed: () => _toggleFillSign(context, editing),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('editor-more'),
            tooltip: 'More',
            enabled: !_saving,
            onSelected: (value) => _onMoreSelected(value, context),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'saveAs',
                child: _MenuRow(
                  icon: Icons.save_alt,
                  label: 'Save As',
                ),
              ),
              PopupMenuItem(
                value: 'saveCopy',
                child: _MenuRow(
                  icon: Icons.file_copy_outlined,
                  label: 'Save a Copy',
                ),
              ),
              PopupMenuItem(
                value: 'share',
                child: _MenuRow(
                  icon: Icons.share_outlined,
                  label: 'Share',
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ],
    );
  }

  void _onMoreSelected(String value, BuildContext context) {
    final editing = _editing;
    if (editing == null) return;
    switch (value) {
      case 'saveAs':
        _saveAsPdf(editing.bytes);
      case 'saveCopy':
        _saveCopyPdf(editing.bytes);
      case 'share':
        _share(context);
    }
  }

  /// A subtle live indicator of the document's save state.
  Widget? _statePill(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_saving) {
      return Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              'Saving…',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    if (_dirty) {
      return Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'Unsaved changes',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: scheme.onTertiaryContainer,
          ),
        ),
      );
    }
    if (_savedBytes != null && _saveTarget != null) {
      return Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, size: 12, color: scheme.primary),
            const SizedBox(width: 4),
            Text(
              'Saved',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    return null;
  }

  Widget _buildEditor(BuildContext context) {
    return Stack(
      key: _bodyKey,
      children: [
        Positioned.fill(
          child: PdfEditorView(
            controller: editing,
            viewerController: _viewer,
            documentId: widget.title,
            features: _features,
            viewerTheme: _viewerTheme(context),
            alwaysAllowSave: true,
            onSave: (bytes) => _savePdf(bytes),
            onSaveAs: (bytes) => _saveAsPdf(bytes),
            textPrompt: _inPlaceTextPrompt,
            styledTextPrompt: _inPlaceStyledTextPrompt,
            imagePicker: (_) => DocumentIo.pickImage(),
            onPickPdfToInsert: () async =>
                (await DocumentIo.pickAndRead())?.bytes,
            toolbarTrailing: _fillSignActive
                ? const []
                : [
                    _fillSignEntryButton,
                  ],
            toolbarBuilder: _fillSignActive ? _fillSignToolbarBuild : null,
            pageOverlayBuilder: _pageOverlays,
          ),
        ),
        if (_inPlaceEdit != null && _editRect != null)
          Positioned.fromRect(
            rect: _editRect!,
            child: _InPlaceTextEditor(
              key: ValueKey(
                'inplace-${_inPlaceEdit!.page}-${_inPlaceEdit!.elementId}',
              ),
              size: _editRect!.size,
              initial: _inPlaceEdit!.initial,
              multiline: _inPlaceEdit!.multiline,
              onDone: _commitInPlaceEdit,
              onNudge: _nudgeInPlaceEdit,
              onDrag: _dragInPlaceEdit,
            ),
          ),
      ],
    );
  }

  /// Viewer colours for the engine chrome: a neutral canvas behind the
  /// pages, Docvera-blue selection and annotation chrome, amber search
  /// matches, and a matching scrollbar.
  PdfViewerThemeData _viewerTheme(BuildContext context) {
    final dark = AppTheme.isDark(context);
    final scheme = Theme.of(context).colorScheme;
    final chrome = dark ? AppColors.chromeDark : AppColors.chromeLight;
    return PdfViewerThemeData(
      canvasColor: AppTheme.canvasColor(context),
      selectionColor: dark ? AppColors.selectionDark : AppColors.selectionLight,
      selectionHandleColor: chrome,
      searchMatchColor:
          dark ? AppColors.searchMatchDark : AppColors.searchMatchLight,
      currentSearchMatchColor:
          dark ? AppColors.searchCurrentDark : AppColors.searchCurrentLight,
      annotationChromeColor: chrome,
      elementChromeColor: chrome,
      flashColor: scheme.primary.withValues(alpha: 0.35),
      formFieldHighlightColor:
          dark ? const Color(0x663D7BFF) : const Color(0x3320A4FF),
      scrollbar: AppTheme.scrollbarTheme(dark),
    );
  }

  Rect _clampEditRect(Rect rect) {
    final r = rect.inflate(8);
    final width = math.max(r.width, 180.0);
    final height = math.max(r.height, 136.0);
    return Rect.fromCenter(center: r.center, width: width, height: height);
  }

  /// The per-page overlay stack: the in-place text editor anchor (original
  /// behaviour) plus, while a Fill & Sign place-mode is armed, the
  /// tap-to-place target.
  List<Widget> _pageOverlays(
    BuildContext context,
    int pageIndex,
    PdfPageGeometry geometry,
  ) {
    // Skip thumbnail renders in the side panel (tiny page boxes): their
    // geometry is meaningless here.
    if (geometry.viewSize.width < 160 || geometry.viewSize.height < 84) {
      return const [];
    }
    final overlays = <Widget>[];

    final place = _placeConfig;
    if (place != null) {
      overlays.add(
        FillSignPlaceTarget(
          geometry: geometry,
          config: place,
          onPlace: (x, y) => _placeAt(pageIndex, x, y),
        ),
      );
    }

    final edit = _inPlaceEdit;
    if (edit != null && edit.page == pageIndex) {
      // Anchor the box to the selected run until the user nudges or drags
      // it; afterwards it follows [_editPageRect] only.
      if (!_editMoved) {
        final bounds = _elementBounds(edit.page, edit.elementId);
        if (bounds != null && _editPageRect != bounds) {
          _editPageRect = bounds;
        }
      }
      final pageRect = _editPageRect;
      if (pageRect != null) {
        // Rect in the page overlay's local coordinates, then convert to this
        // screen's Stack coordinates so the editor can be Positioned above
        // the engine's editing layer.
        final local = _clampEditRect(geometry.toViewRect(pageRect));
        final pageBox = context.findRenderObject() as RenderBox?;
        final bodyBox =
            _bodyKey.currentContext?.findRenderObject() as RenderBox?;
        if (pageBox != null && bodyBox != null) {
          try {
            final pageToBody = pageBox.getTransformTo(bodyBox);
            final topLeft = MatrixUtils.transformPoint(
                pageToBody, local.topLeft);
            final bottomRight = MatrixUtils.transformPoint(
                pageToBody, local.bottomRight);
            final bodyRect = Rect.fromPoints(topLeft, bottomRight);
            // Keep the inverse handy so drag deltas convert back to page
            // space, and the forward matrix for nudge deltas.
            _pageToBodyMatrix = pageToBody;
            try {
              _bodyToPageMatrix = bodyBox.getTransformTo(pageBox);
            } catch (_) {
              _bodyToPageMatrix = null;
            }
            // The overlay builds while this screen's Stack has already been
            // built this frame, so a change only shows next frame - schedule
            // one so the box appears the moment we have a rect.
            if (_editRect != bodyRect) {
              _editRect = bodyRect;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {});
              });
            }
          } catch (_) {
            // Layout not ready yet (first frame) - try again next build.
          }
        }
      }
    }

    return overlays;
  }

  // -------------------------------------------------- save / export / share

  /// Primary Save: writes the current revision to the document's current
  /// location. On a document opened from Recents (or one already saved in
  /// this session) this overwrites that copy in place and is silent; for a
  /// freshly picked file on desktop/web it falls back to the Save As flow, on
  /// mobile it keeps a copy in the app's library. Returns true only when the
  /// bytes were written.
  Future<bool> _savePdf(Uint8List bytes) async {
    if (_saving) return false;
    final editing = _editing;
    if (editing == null) return false;
    final target = _saveTarget;
    // Desktop / web with no saved location yet: the Save As flow manages the
    // busy state itself.
    if (target == null && !DocumentIo.isMobilePlatform) {
      return _saveAsPdf(bytes);
    }
    setState(() => _saving = true);
    try {
      if (target != null && target.path != null && !kIsWeb) {
        await (widget.saveToPath ?? DocumentIo.saveToPath)(
            target.path!, bytes);
        await _persistRecent(target.copyWith(
          sizeBytes: bytes.length,
          lastOpened: DateTime.now(),
        ));
      } else {
        // Mobile: no location picker - keep a copy in the app's library.
        final recent =
            await (widget.persistForRecents ?? DocumentIo.persistForRecents)
                .call(PickedPdf(name: _displayName, bytes: bytes));
        _saveTarget = recent;
        await _persistRecent(recent);
      }
      _markSaved(bytes);
      _notifySaved('Saved $_displayName');
      return true;
    } catch (_) {
      if (mounted) _notifyError("Couldn't save the PDF. Please try again.");
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Save As: choose a filename (and location where supported). The document
  /// is renamed to the new file and subsequent Save writes there. Returns
  /// false on cancel.
  Future<bool> _saveAsPdf(Uint8List bytes) async {
    if (_saving) return false;
    final editing = _editing;
    if (editing == null) return false;
    setState(() => _saving = true);
    try {
      final suggested = _saveAsFileName(_displayName);
      if (DocumentIo.isMobilePlatform) {
        final name = await _promptSaveName(context, suggested);
        if (name == null) return false; // cancelled
        final recent = await (widget.persistForRecents ?? DocumentIo.persistForRecents)
            .call(PickedPdf(name: name, bytes: bytes));
        await _persistRecent(recent);
        setState(() => _displayName = name);
        _saveTarget = recent;
        _markSaved(bytes);
        _notifySaved('Saved $name');
        return true;
      }
      final outcome = await (widget.saveAsPdf ?? DocumentIo.saveAsPdf)
          .call(bytes, suggested);
      if (!outcome.saved) return false; // desktop dialog cancelled
      final name = outcome.path == null
          ? suggested
          : _fileNameFromPath(outcome.path!);
      RecentDocument recent;
      if (outcome.path != null) {
        recent = RecentDocument(
          name: name,
          sizeBytes: bytes.length,
          lastOpened: DateTime.now(),
          path: outcome.path,
        );
      } else {
        recent = await (widget.persistForRecents ?? DocumentIo.persistForRecents)
            .call(PickedPdf(name: name, bytes: bytes));
      }
      await _persistRecent(recent);
      setState(() => _displayName = name);
      _saveTarget = recent;
      _markSaved(bytes);
      _notifySaved('Saved $name');
      return true;
    } catch (_) {
      if (mounted) _notifyError("Couldn't save the PDF. Please try again.");
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Save a Copy: writes a new file but keeps the current document (and its
  /// title/location) unchanged. The copy is added to Recents so it can be
  /// reopened.
  Future<bool> _saveCopyPdf(Uint8List bytes) async {
    if (_saving) return false;
    final editing = _editing;
    if (editing == null) return false;
    setState(() => _saving = true);
    try {
      final suggested = _copyFileName(_displayName);
      if (DocumentIo.isMobilePlatform) {
        final name = await _promptSaveName(context, suggested);
        if (name == null) return false; // cancelled
        final recent = await (widget.persistForRecents ?? DocumentIo.persistForRecents)
            .call(PickedPdf(name: name, bytes: bytes));
        await _persistRecent(recent);
        _markSaved(bytes);
        _notifySaved('Saved a copy as $name');
        return true;
      }
      final outcome = await (widget.saveAsPdf ?? DocumentIo.saveAsPdf)
          .call(bytes, suggested);
      if (!outcome.saved) return false; // desktop dialog cancelled
      final name = outcome.path == null
          ? suggested
          : _fileNameFromPath(outcome.path!);
      final recent = outcome.path != null
          ? RecentDocument(
              name: name,
              sizeBytes: bytes.length,
              lastOpened: DateTime.now(),
              path: outcome.path,
            )
          : await (widget.persistForRecents ?? DocumentIo.persistForRecents)
              .call(PickedPdf(name: name, bytes: bytes));
      await _persistRecent(recent);
      _markSaved(bytes);
      _notifySaved('Saved a copy as $name');
      return true;
    } catch (_) {
      if (mounted) _notifyError("Couldn't save the PDF. Please try again.");
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share(BuildContext context) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await (widget.sharePdf ?? DocumentIo.sharePdf)
          .call(editing.bytes, _displayName);
    } catch (_) {
      if (context.mounted) _notifyError("Couldn't share the PDF. Please try again.");
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _markSaved(Uint8List bytes) {
    _savedBytes = bytes;
    _dirty = false;
    _dirtyKeyRevision = -1; // force the next _refreshDirty to re-check
  }

  Future<void> _persistRecent(RecentDocument doc) async {
    try {
      await _recentStore.upsert(doc);
    } catch (_) {
      // Recents are best-effort; a failed write must not fail the save.
    }
  }

  void _notifySaved(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  void _notifyError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ));
  }

  // --------------------------------------------------- leave-guard dialog

  /// Back affordance: if there are unsaved changes, ask the user what to do.
  void _requestClose(BuildContext context) {
    if (_dirty) {
      _confirmSaveChanges(context);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _confirmSaveChanges(BuildContext context) async {
    final choice = await showDialog<_SaveChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save changes?'),
        content: Text(
          'You have unsaved changes to $_displayName. '
          'Save them before leaving?',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_SaveChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_SaveChoice.discard),
            child: const Text("Don't Save"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(_SaveChoice.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == _SaveChoice.cancel) return;
    if (choice == _SaveChoice.discard) {
      _forceClose = true;
      // Hard pop: bypasses PopScope, which still reports canPop=false until
      // the next rebuild with _forceClose set.
      Navigator.of(this.context).pop();
      return;
    }
    final editing = _editing;
    if (editing == null) return;
    final ok = await _savePdf(editing.bytes);
    if (ok && mounted) {
      Navigator.of(this.context).pop();
    }
  }

  // ------------------------------------------------------- filename helpers

  static String _stem(String name) {
    final base = pdfStem(name);
    return base.isEmpty ? 'document' : base;
  }

  static String _saveAsFileName(String currentName) {
    final stem = _stem(currentName);
    return ensurePdfExtension(stem.endsWith('-edited') ||
            stem.endsWith('_edited')
        ? stem
        : '$stem-edited');
  }

  static String _copyFileName(String currentName) {
    return ensurePdfExtension('${_stem(currentName)}-copy');
  }

  static String _fileNameFromPath(String path) {
    final segments = path.split(RegExp(r'[/\\]'));
    final name = segments.where((s) => s.isNotEmpty).lastOrNull ?? path;
    return ensurePdfExtension(name);
  }

  Future<String?> _promptSaveName(BuildContext context, String initial) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save As'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Filename',
            hintText: 'report-edited.pdf',
            prefixIcon: Icon(Icons.description_outlined),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) =>
              Navigator.of(dialogContext).pop(controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return null;
    final name = ensurePdfExtension(result.trim());
    return name.isEmpty ? null : name;
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Could not open this PDF',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'The file appears to be damaged or not a valid PDF.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfInPlaceEdit {
  _PdfInPlaceEdit({
    required this.page,
    required this.elementId,
    required this.initial,
    required this.multiline,
    required this.completer,
  });

  final int page;
  final int elementId;
  final String initial;
  final bool multiline;
  final Completer<String?> completer;
}

class _InPlaceTextEditor extends StatefulWidget {
  const _InPlaceTextEditor({
    super.key,
    required this.size,
    required this.initial,
    required this.multiline,
    required this.onDone,
    required this.onNudge,
    required this.onDrag,
  });

  final Size size;
  final String initial;
  final bool multiline;
  final ValueChanged<String?> onDone;
  final void Function(double dxPage, double dyPage) onNudge;
  final void Function(Offset bodyDelta) onDrag;

  @override
  State<_InPlaceTextEditor> createState() => _InPlaceTextEditorState();
}

class _InPlaceTextEditorState extends State<_InPlaceTextEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  final FocusNode _focus = FocusNode(debugLabel: 'in-place-text-editor');

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    _focus.unfocus();
    widget.onDone(_controller.text);
  }

  void _cancel() {
    _focus.unfocus();
    widget.onDone(null);
  }

  Widget _nudgeIcon(IconData icon, String tooltip, double dx, double dy) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: () => widget.onNudge(dx, dy),
        radius: 18,
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(icon, size: 15, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: widget.size.width,
      height: widget.size.height,
      child: Material(
        elevation: 4,
        color: scheme.surface,
        shadowColor: Colors.black38,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 30,
              color: scheme.surfaceContainerHighest,
              child: Row(
                children: [
                  // Drag handle: grabbing shifts the box (and the committed
                  // text) in any direction.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) =>
                        widget.onDrag(details.delta),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.move,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8, right: 8),
                        child: Icon(
                          Icons.drag_indicator,
                          size: 17,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  _nudgeIcon(
                    Icons.keyboard_arrow_left,
                    'Move left',
                    -2,
                    0,
                  ),
                  _nudgeIcon(Icons.keyboard_arrow_up, 'Move up', 0, 2),
                  _nudgeIcon(Icons.keyboard_arrow_down, 'Move down', 0, -2),
                  _nudgeIcon(
                    Icons.keyboard_arrow_right,
                    'Move right',
                    2,
                    0,
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      'Drag or use arrows to move the text',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Focus(
                focusNode: _focus,
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    _cancel();
                    return KeyEventResult.handled;
                  }
                  if (widget.multiline &&
                      event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter &&
                      (HardwareKeyboard.instance.isControlPressed ||
                          HardwareKeyboard.instance.isMetaPressed)) {
                    _commit();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _controller,
                  maxLines: widget.multiline ? null : 1,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Type text…',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  style: TextStyle(fontSize: 14, color: scheme.onSurface),
                  cursorColor: scheme.primary,
                  textInputAction: widget.multiline
                      ? TextInputAction.newline
                      : TextInputAction.done,
                  onSubmitted: widget.multiline ? null : (_) => _commit(),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  tooltip: 'Cancel',
                  visualDensity: VisualDensity.compact,
                  color: scheme.onSurfaceVariant,
                  onPressed: _cancel,
                ),
                IconButton(
                  icon: const Icon(Icons.check, size: 16),
                  tooltip: 'Done',
                  visualDensity: VisualDensity.compact,
                  color: scheme.primary,
                  onPressed: _commit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled menu row for the editor's "more" actions.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}
