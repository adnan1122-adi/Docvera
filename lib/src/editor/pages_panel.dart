import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';

import '../services/document_io.dart';

/// Full-screen page manager. The engine's thumbnail grid provides the
/// selection / drag-reorder / rendering core; this screen layers the
/// professional chrome on top: undo/redo, a contextual action bar, and
/// dialogs for add-blank-page (position + size), insert-PDF (position) and
/// destructive delete confirmation.
Future<void> showPagesPanel(
  BuildContext context, {
  required PdfEditingController editing,
  required PdfViewerController viewer,
  String documentName = '',
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PagesPanel(
        editing: editing,
        viewer: viewer,
        documentName: documentName,
      ),
    ),
  );
}

/// Where a new or imported page is inserted.
enum _InsertPosition { end, afterSelected, beforeSelected }

/// A page-size choice for blank pages. Null dimensions mean "match the
/// neighbouring page" (the engine's default), i.e. the document's own size.
class _PageSizePreset {
  const _PageSizePreset(this.label, this.width, this.height);

  const _PageSizePreset.sameAsDocument()
      : label = 'Same as document',
        width = null,
        height = null;

  final String label;
  final double? width;
  final double? height;

  static const _a4 = _PageSizePreset('A4', 595.28, 841.89);
  static const _letter = _PageSizePreset('Letter', 612, 792);
  static const _legal = _PageSizePreset('Legal', 612, 1008);
  static const _a3 = _PageSizePreset('A3', 841.89, 1191.58);

  static const all = <_PageSizePreset>[
    _PageSizePreset.sameAsDocument(),
    _a4,
    _letter,
    _legal,
    _a3,
  ];
}

class PagesPanel extends StatefulWidget {
  const PagesPanel({
    super.key,
    required this.editing,
    required this.viewer,
    this.documentName = '',
    this.pickPdf,
    this.savePdf,
  });

  final PdfEditingController editing;
  final PdfViewerController viewer;
  final String documentName;

  /// Test seam over [DocumentIo.pickAndRead] (file picker is a platform
  /// channel that widget tests cannot drive).
  final Future<PickedPdf?> Function()? pickPdf;

  /// Test seam over [DocumentIo.savePdf] (save dialog is a platform
  /// channel that widget tests cannot drive).
  final Future<bool> Function(Uint8List bytes, String suggestedName)? savePdf;

  @override
  State<PagesPanel> createState() => _PagesPanelState();
}

class _PagesPanelState extends State<PagesPanel> {
  PdfEditingController get editing => widget.editing;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.editing.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.editing.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        // Float above the action bar so it never covers the page actions.
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
      ));
  }

  // ------------------------------------------------------------- operations

  void _selectAll() => editing.selectAllPages();

  void _clearSelection() => editing.clearPageSelection();

  Future<void> _showAddPageDialog() async {
    final size = editing.document.pageCount > 0
        ? editing.pageAt(0).mediaBox
        : null;
    final sizeHint = size == null
        ? ''
        : ' (${size.width.toStringAsFixed(0)} × '
            '${size.height.toStringAsFixed(0)} pt)';
    final result = await showDialog<({_InsertPosition position, _PageSizePreset size})>(
      context: context,
      builder: (context) => _AddPageDialog(
        hasSelection: editing.hasPageSelection,
        sizeHint: sizeHint,
      ),
    );
    if (result == null || !mounted) return;
    editing.addBlankPage(
      width: result.size.width,
      height: result.size.height,
      at: _insertionIndex(result.position),
    );
    _snack('Blank page added.');
  }

  int _insertionIndex(_InsertPosition position) {
    switch (position) {
      case _InsertPosition.end:
        return editing.document.pageCount;
      case _InsertPosition.beforeSelected:
        return editing.selectedPages.first;
      case _InsertPosition.afterSelected:
        return editing.selectedPages.last + 1;
    }
  }

  Future<void> _insertPdf() async {
    if (_busy) return;
    final picked = await (widget.pickPdf ?? DocumentIo.pickAndRead)();
    if (picked == null || !mounted) return; // user cancelled
    try {
      final source = PdfDocument.open(picked.bytes);
      final imported = source.pageCount;
      if (imported == 0) {
        _snack('That file contains no pages.');
        return;
      }
      final position = await _chooseInsertPosition();
      if (position == null || !mounted) return;
      setState(() => _busy = true);
      editing.insertPagesFromBytes(picked.bytes, at: _insertionIndex(position));
      _snack('Imported $imported page${imported == 1 ? '' : 's'}.');
    } catch (_) {
      _snack('Could not import that file. Please choose a valid PDF.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_InsertPosition?> _chooseInsertPosition() {
    return showDialog<_InsertPosition>(
      context: context,
      builder: (context) => _InsertPositionDialog(
        hasSelection: editing.hasPageSelection,
      ),
    );
  }

  void _duplicateSelection() {
    if (!editing.hasPageSelection) return;
    final pages = List<int>.from(editing.selectedPages);
    editing.duplicatePages(pages);
    _snack('Duplicated ${pages.length} page${pages.length == 1 ? '' : 's'}.');
  }

  void _rotateSelection(int degrees) {
    if (!editing.hasPageSelection) return;
    final count = editing.selectedPageCount;
    editing.rotateSelectedPages(degrees);
    _snack('Rotated $count page${count == 1 ? '' : 's'}.');
  }

  Future<void> _deleteSelection() async {
    if (!editing.hasPageSelection) return;
    final count = editing.selectedPageCount;
    if (editing.document.pageCount - count < 1) {
      _snack('A PDF must contain at least one page, so this page cannot be '
          'deleted.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(count == 1 ? 'Delete page?' : 'Delete pages?'),
        content: Text(
          count == 1
              ? 'This will remove the selected page. You can undo this.'
              : 'This will remove the $count selected pages. You can undo '
                  'this.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    editing.removeSelectedPages();
    _snack('Deleted $count page${count == 1 ? '' : 's'}.');
  }

  Future<void> _exportSelection() async {
    if (!editing.hasPageSelection || _busy) return;
    final pages = List<int>.from(editing.selectedPages);
    setState(() => _busy = true);
    try {
      final bytes = editing.exportPages(pages);
      final ok = await (widget.savePdf ?? DocumentIo.savePdf)(
          bytes, _exportFilename(pages));
      if (ok && mounted) {
        _snack('Exported ${pages.length} page${pages.length == 1 ? '' : 's'}.');
      }
    } catch (_) {
      if (mounted) _snack('Could not export the pages.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _exportFilename(List<int> pages) {
    var base = widget.documentName.trim();
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    if (base.isEmpty) base = 'document';
    final numbered = pages.map((p) => p + 1).join('-');
    return '${base}_pages_$numbered.pdf';
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final total = editing.document.pageCount;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text('Pages · $total'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
            onPressed: editing.canUndo ? editing.undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: 'Redo',
            onPressed: editing.canRedo ? editing.redo : null,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PdfThumbnailView(
              controller: editing,
              viewerController: widget.viewer,
              allowPageEditing: true,
              onOpenPage: (_) => Navigator.of(context).maybePop(),
              onPickPdfToInsert: null,
              onExportPages: null,
              minTileWidth: 80,
              maxTileWidth: 360,
              defaultTileWidth: MediaQuery.sizeOf(context).width < 600
                  ? 120
                  : 168,
            ),
          ),
          _buildActionBar(context),
        ],
      ),
    );
  }

  Widget _buildActionBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < 560;
    final hasSelection = editing.hasPageSelection;
    final selected = editing.selectedPageCount;

    final items = <Widget>[];
    void add({
      required Key key,
      required IconData icon,
      required String label,
      VoidCallback? onPressed,
      bool enabled = true,
      bool destructive = false,
    }) {
      items.add(_BarButton(
        key: key,
        icon: icon,
        label: label,
        onPressed: enabled ? onPressed : null,
        color: destructive ? scheme.error : null,
        compact: narrow,
      ));
    }

    if (!hasSelection) {
      add(
        key: const ValueKey('pages-action-select-all'),
        icon: Icons.select_all_outlined,
        label: 'Select all',
        onPressed: _selectAll,
      );
      add(
        key: const ValueKey('pages-action-add'),
        icon: Icons.note_add_outlined,
        label: 'Add page',
        onPressed: _showAddPageDialog,
      );
      add(
        key: const ValueKey('pages-action-insert'),
        icon: Icons.insert_drive_file_outlined,
        label: 'Insert PDF',
        onPressed: _busy ? null : _insertPdf,
      );
    } else {
      add(
        key: const ValueKey('pages-action-clear'),
        icon: Icons.deselect_outlined,
        label: 'Clear',
        onPressed: _clearSelection,
      );
      add(
        key: const ValueKey('pages-action-add'),
        icon: Icons.note_add_outlined,
        label: 'Add page',
        onPressed: _showAddPageDialog,
      );
      add(
        key: const ValueKey('pages-action-insert'),
        icon: Icons.insert_drive_file_outlined,
        label: 'Insert PDF',
        onPressed: _busy ? null : _insertPdf,
      );
      add(
        key: const ValueKey('pages-action-duplicate'),
        icon: Icons.content_copy_outlined,
        label: 'Duplicate',
        onPressed: _duplicateSelection,
      );
      add(
        key: const ValueKey('pages-action-rotate-left'),
        icon: Icons.rotate_left_outlined,
        label: 'Rotate left',
        onPressed: () => _rotateSelection(-90),
      );
      add(
        key: const ValueKey('pages-action-rotate-right'),
        icon: Icons.rotate_right_outlined,
        label: 'Rotate right',
        onPressed: () => _rotateSelection(90),
      );
      add(
        key: const ValueKey('pages-action-delete'),
        icon: Icons.delete_outline_rounded,
        label: 'Delete',
        onPressed: _deleteSelection,
        destructive: true,
      );
      add(
        key: const ValueKey('pages-action-export'),
        icon: Icons.file_download_outlined,
        label: 'Export',
        onPressed: _busy ? null : _exportSelection,
      );
    }

    return Material(
      elevation: 3,
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: narrow ? 60 : 68,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: _SelectionSummary(
                  hasSelection: hasSelection,
                  selected: selected,
                  total: editing.document.pageCount,
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                indent: 12,
                endIndent: 12,
                color: scheme.outlineVariant,
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(children: items),
                ),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({
    required this.hasSelection,
    required this.selected,
    required this.total,
  });

  final bool hasSelection;
  final int selected;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!hasSelection) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.pages_outlined, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            '$total page${total == 1 ? '' : 's'}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '$selected selected',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.compact,
    this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: color),
        tooltip: label,
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: color),
      icon: Icon(icon, size: 20),
      label: Text(label),
    );
  }
}

class _AddPageDialog extends StatefulWidget {
  const _AddPageDialog({
    required this.hasSelection,
    required this.sizeHint,
  });

  final bool hasSelection;
  final String sizeHint;

  @override
  State<_AddPageDialog> createState() => _AddPageDialogState();
}

class _AddPageDialogState extends State<_AddPageDialog> {
  _InsertPosition _position = _InsertPosition.end;
  _PageSizePreset _size = const _PageSizePreset.sameAsDocument();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add blank page'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Position',
                style: Theme.of(context).textTheme.titleSmall),
            RadioGroup<_InsertPosition>(
              groupValue: _position,
              onChanged: (v) => setState(() => _position = v!),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const RadioListTile<_InsertPosition>(
                    value: _InsertPosition.end,
                    title: Text('End of document'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<_InsertPosition>(
                    value: _InsertPosition.afterSelected,
                    enabled: widget.hasSelection,
                    title: const Text('After selected page'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<_InsertPosition>(
                    value: _InsertPosition.beforeSelected,
                    enabled: widget.hasSelection,
                    title: const Text('Before selected page'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('Page size', style: Theme.of(context).textTheme.titleSmall),
            RadioGroup<_PageSizePreset>(
              groupValue: _size,
              onChanged: (v) => setState(() => _size = v!),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final preset in _PageSizePreset.all)
                    RadioListTile<_PageSizePreset>(
                      value: preset,
                      title: Text(preset == _PageSizePreset.all.first
                          ? '${preset.label}${widget.sizeHint}'
                          : preset.label),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            (position: _position, size: _size),
          ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _InsertPositionDialog extends StatefulWidget {
  const _InsertPositionDialog({required this.hasSelection});

  final bool hasSelection;

  @override
  State<_InsertPositionDialog> createState() => _InsertPositionDialogState();
}

class _InsertPositionDialogState extends State<_InsertPositionDialog> {
  _InsertPosition _position = _InsertPosition.end;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Insert pages'),
      content: RadioGroup<_InsertPosition>(
        groupValue: _position,
        onChanged: (v) => setState(() => _position = v!),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RadioListTile<_InsertPosition>(
              value: _InsertPosition.end,
              title: Text('End of document'),
              dense: true,
            ),
            RadioListTile<_InsertPosition>(
              value: _InsertPosition.afterSelected,
              enabled: widget.hasSelection,
              title: const Text('After selected page'),
              dense: true,
            ),
            RadioListTile<_InsertPosition>(
              value: _InsertPosition.beforeSelected,
              enabled: widget.hasSelection,
              title: const Text('Before selected page'),
              dense: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_position),
          child: const Text('Import'),
        ),
      ],
    );
  }
}
