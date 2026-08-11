import 'dart:math' as math;

import 'package:dart_pdf_editor/dart_pdf_editor.dart'
    show PdfEditingController, PdfFormFieldKind, PdfInkSignature;
import 'package:pdf_document/pdf_document.dart'
    show PdfAnnotationEditing, PdfRect;

/// Pure placement operations for the Fill & Sign tools.
///
/// Every operation commits through [PdfEditingController.apply] so each
/// placement is a single undoable revision - move/resize/delete then behave
/// exactly like the rest of the editor's annotations (the existing Select
/// tool, the undo/redo stack, and Save all pick the objects up as ordinary
/// annotations or AcroForm widgets).
class FillSignService {
  /// The ink colour a drawn signature/initials keeps, or the active text
  /// colour otherwise.
  static int _colorOf(PdfEditingController editing) =>
      editing.color.toARGB32() & 0xFFFFFF;

  /// Clamps a box of [w]x[h] points centred on (cx, cy) inside [crop].
  static PdfRect _centered(PdfRect crop, double cx, double cy, double w, double h) {
    final x = cx.clamp(crop.left + w / 2, crop.right - w / 2);
    final y = cy.clamp(crop.bottom + h / 2, crop.top - h / 2);
    return PdfRect(x - w / 2, y - h / 2, x + w / 2, y + h / 2);
  }

  /// Places [text] (a date, typed signature, or typed initials) as a
  /// movable FreeText annotation centred on the tapped point, sized to the
  /// text at the current font preference. Styled with the active text
  /// colour / font / alignment so the Style controls affect it.
  static void placeText(
    PdfEditingController editing,
    int page,
    double x,
    double y,
    String text,
  ) {
    final crop = editing.document.page(page).cropBox;
    final prefs = editing.preferences;
    final size = prefs.fontSize.clamp(6.0, 72.0);
    final width = math.max(60.0, text.length * size * 0.62);
    final height = size * 1.6;
    final rect = _centered(crop, x, y, width, height);
    editing.apply(
      (e) => e.addFreeText(
        page,
        rect,
        text,
        fontSize: size,
        font: editing.fontFamily,
        align: prefs.textAlign,
        color: _colorOf(editing),
      ),
    );
  }

  /// Places a hand-drawn signature/initials as an Ink annotation centred on
  /// the tapped point, [width] points wide (clamped to the page, keeping the
  /// drawing's proportions and pen pressures - the same layout the engine's
  /// own signature tool uses).
  static void placeInk(
    PdfEditingController editing,
    int page,
    double x,
    double y,
    PdfInkSignature signature, {
    double width = 130,
  }) {
    final crop = editing.document.page(page).cropBox;
    final aspect = signature.aspect > 0 ? signature.aspect : 2.0;
    var w = width.clamp(8.0, crop.width * 0.9);
    var h = w / aspect;
    if (h > crop.height * 0.9) {
      h = crop.height * 0.9;
      w = h * aspect;
    }
    final cx = x.clamp(crop.left + w / 2, crop.right - w / 2);
    final cy = y.clamp(crop.bottom + h / 2, crop.top - h / 2);
    final left = cx - w / 2;
    final top = cy + h / 2;
    editing.apply(
      (e) => e.addInk(
        page,
        [
          // normalized pad space is y-down; page space is y-up
          for (final stroke in signature.strokes)
            [for (final (nx, ny) in stroke) (left + nx * w, top - ny * h)],
        ],
        color: signature.color,
        strokeWidth: w / 60,
        opacity: 1,
        pressures: signature.pressures,
      ),
    );
  }

  /// Places a real AcroForm check box (off by default) centred on the
  /// tapped point. It is a genuine widget field: it toggles on tap (the
  /// reader's form layer), moves/resizes/deletes under the form tool, and
  /// survives save/reopen natively.
  static void placeCheckbox(
    PdfEditingController editing,
    int page,
    double x,
    double y, {
    double size = 18,
  }) {
    final crop = editing.document.page(page).cropBox;
    final rect = _centered(crop, x, y, size, size);
    editing.addFormField(PdfFormFieldKind.checkBox, page, rect);
  }

  /// Places a bold "X" mark as a two-stroke Ink annotation centred on the
  /// tapped point - a movable, resizable, deletable annotation like any
  /// other drawing.
  static void placeXMark(
    PdfEditingController editing,
    int page,
    double x,
    double y, {
    double halfSize = 10,
    double strokeWidth = 3,
  }) {
    final crop = editing.document.page(page).cropBox;
    final cx = x.clamp(crop.left + halfSize, crop.right - halfSize);
    final cy = y.clamp(crop.bottom + halfSize, crop.top - halfSize);
    editing.apply(
      (e) => e.addInk(
        page,
        [
          [(cx - halfSize, cy - halfSize), (cx + halfSize, cy + halfSize)],
          [(cx - halfSize, cy + halfSize), (cx + halfSize, cy - halfSize)],
        ],
        strokeWidth: strokeWidth,
        color: _colorOf(editing),
      ),
    );
  }
}

/// The kind of object a Fill & Sign "place" mode is about to put down when
/// the user taps the page. Tools without a place step (Text, Signature,
/// Check) arm an engine tool instead.
enum FillSignPlaceKind { date, typedText, drawnInk, checkbox, xMark }

/// The armed place-mode payload: what to create at the tapped point.
class FillSignPlaceConfig {
  const FillSignPlaceConfig.drawnInk(PdfInkSignature this.signature)
      : kind = FillSignPlaceKind.drawnInk,
        text = null;

  const FillSignPlaceConfig.text(this.text)
      : kind = FillSignPlaceKind.typedText,
        signature = null;

  const FillSignPlaceConfig.date(this.text)
      : kind = FillSignPlaceKind.date,
        signature = null;

  const FillSignPlaceConfig.checkbox()
      : kind = FillSignPlaceKind.checkbox,
        text = null,
        signature = null;

  const FillSignPlaceConfig.xMark()
      : kind = FillSignPlaceKind.xMark,
        text = null,
        signature = null;

  final FillSignPlaceKind kind;
  final String? text;
  final PdfInkSignature? signature;

  /// A short caption shown while the mode is armed.
  String get hint => switch (kind) {
        FillSignPlaceKind.date => 'Tap the page to place the date',
        FillSignPlaceKind.typedText => 'Tap the page to place the text',
        FillSignPlaceKind.drawnInk => 'Tap the page to place it',
        FillSignPlaceKind.checkbox => 'Tap the page to add a checkbox',
        FillSignPlaceKind.xMark => 'Tap the page to add an X mark',
      };
}
