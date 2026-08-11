import 'package:dart_pdf_editor/dart_pdf_editor.dart'
    show PdfEditTool, PdfEditingController, PdfViewerController;
import 'package:flutter/material.dart';

import 'fill_sign_service.dart';

/// The clean contextual toolbar shown while Fill & Sign mode is active.
///
/// It replaces the full editor toolbar for the mode: the currently relevant
/// tools only - Select (move/resize the placed objects), the seven Fill &
/// Sign tools (Text, Signature, Initials, Date, Checkbox, Check, X), the
/// AcroForm "Fields" tool for interacting with existing form widgets, a
/// Style popover for text colour/size/alignment, undo/redo, and Done to
/// return to the full toolbar. On phones the strip scrolls horizontally.
class FillSignToolbar extends StatelessWidget {
  const FillSignToolbar({
    super.key,
    required this.controller,
    required this.viewerController,
    required this.activeTool,
    this.placing,
    required this.hasFormFields,
    required this.onSelect,
    required this.onText,
    required this.onSignature,
    required this.onInitials,
    required this.onDate,
    required this.onCheckbox,
    required this.onCheck,
    required this.onX,
    required this.onFields,
    required this.onStyle,
    required this.onUndo,
    required this.onRedo,
    required this.onDone,
  });

  final PdfEditingController controller;
  final PdfViewerController viewerController;
  final PdfEditTool? activeTool;

  /// The armed place-mode (non-null while a tool is waiting for a page tap).
  final FillSignPlaceConfig? placing;

  /// Whether the document already carries AcroForm fields.
  final bool hasFormFields;

  final VoidCallback? onSelect;
  final VoidCallback? onText;
  final VoidCallback? onSignature;
  final VoidCallback? onInitials;
  final VoidCallback? onDate;
  final VoidCallback? onCheckbox;
  final VoidCallback? onCheck;
  final VoidCallback? onX;
  final VoidCallback? onFields;
  final VoidCallback? onStyle;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < 640;

    final items = <Widget>[
      _FillSignToolButton(
        icon: Icons.near_me_outlined,
        label: 'Select',
        selected: activeTool == PdfEditTool.select && placing == null,
        onTap: onSelect,
        tooltip: 'Select / move / resize',
      ),
      const _Divider(),
      _FillSignToolButton(
        icon: Icons.text_fields,
        label: 'Text',
        selected: activeTool == PdfEditTool.freeText,
        onTap: onText,
        tooltip: 'Add text (a movable text box)',
      ),
      _FillSignToolButton(
        icon: Icons.history_edu,
        label: 'Signature',
        selected: activeTool == PdfEditTool.signature ||
            placing?.kind == FillSignPlaceKind.drawnInk,
        onTap: onSignature,
        tooltip: 'Draw or type a signature',
      ),
      _FillSignToolButton(
        icon: Icons.short_text,
        label: 'Initials',
        selected: placing?.kind == FillSignPlaceKind.drawnInk ||
            placing?.kind == FillSignPlaceKind.typedText,
        onTap: onInitials,
        tooltip: 'Draw or type initials',
      ),
      _FillSignToolButton(
        icon: Icons.event_outlined,
        label: 'Date',
        selected: placing?.kind == FillSignPlaceKind.date,
        onTap: onDate,
        tooltip: 'Insert today’s date',
      ),
      _FillSignToolButton(
        icon: Icons.check_box_outline_blank,
        label: 'Checkbox',
        selected: placing?.kind == FillSignPlaceKind.checkbox,
        onTap: onCheckbox,
        tooltip: 'Add a checkbox',
      ),
      _FillSignToolButton(
        icon: Icons.check_circle_outline,
        label: 'Check',
        selected: activeTool == PdfEditTool.count,
        onTap: onCheck,
        tooltip: 'Add a ✓ mark',
      ),
      _FillSignToolButton(
        icon: Icons.close,
        label: 'X',
        selected: placing?.kind == FillSignPlaceKind.xMark,
        onTap: onX,
        tooltip: 'Add an ✕ mark',
      ),
      const _Divider(),
      _FillSignToolButton(
        icon: Icons.ballot_outlined,
        label: 'Fields',
        selected: activeTool == PdfEditTool.form,
        onTap: onFields,
        tooltip: hasFormFields
            ? 'Interactive form fields are available'
            : 'Fill interactive form fields',
        dot: hasFormFields,
      ),
      _FillSignToolButton(
        icon: Icons.palette_outlined,
        label: 'Style',
        onTap: onStyle,
        tooltip: 'Text colour, size and alignment',
      ),
    ];

    final leading = _LeadingTitle(narrow: narrow);
    final trailing = <Widget>[
      _RoundIconButton(
        icon: Icons.undo,
        tooltip: 'Undo',
        enabled: controller.canUndo,
        onTap: onUndo,
      ),
      _RoundIconButton(
        icon: Icons.redo,
        tooltip: 'Redo',
        enabled: controller.canRedo,
        onTap: onRedo,
      ),
      const SizedBox(width: 4),
      _DoneButton(onTap: onDone),
      const SizedBox(width: 8),
    ];

    return Material(
      elevation: 3,
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (placing != null)
              Container(
                color: scheme.primaryContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Text(
                  placing!.hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            SizedBox(
              height: narrow ? 60 : 64,
              child: Row(
                children: [
                  leading,
                  const VerticalDivider(width: 1, indent: 8, endIndent: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(children: items),
                    ),
                  ),
                  ...trailing,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeadingTitle extends StatelessWidget {
  const _LeadingTitle({required this.narrow});

  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_note, size: 20, color: scheme.primary),
          if (!narrow) ...[
            const SizedBox(width: 6),
            Text(
              'Fill & Sign',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _FillSignToolButton extends StatelessWidget {
  const _FillSignToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.tooltip,
    this.selected = false,
    this.dot = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String tooltip;
  final bool selected;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onPrimary : scheme.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Container(
          width: 58,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 20, color: fg),
                  if (dot)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: scheme.error,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: scheme.surface,
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: enabled
            ? scheme.onSurfaceVariant
            : scheme.onSurface.withValues(alpha: 0.3),
        visualDensity: VisualDensity.compact,
        onPressed: enabled ? onTap : null,
      ),
    );
  }
}

class _DoneButton extends StatelessWidget {
  const _DoneButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: const Icon(Icons.check, size: 18),
      label: const Text('Done'),
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
    );
  }
}