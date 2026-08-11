import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

import '../ads/ad_banner_view.dart';
import '../services/document_io.dart';
import 'pdf_merge_service.dart';
import 'pdf_tool_util.dart';
import 'result_screens.dart';

/// Merge PDF screen: add multiple PDFs, drag to reorder, remove, and merge
/// them into one file in the displayed order.
class MergePdfScreen extends StatefulWidget {
  const MergePdfScreen({
    super.key,
    this.pickPdf,
    this.savePdf,
    this.sharePdf,
  });

  /// Test seams, defaulting to the real [DocumentIo] calls.
  final PickPdf? pickPdf;
  final SavePdf? savePdf;
  final SharePdf? sharePdf;

  @override
  State<MergePdfScreen> createState() => _MergePdfScreenState();
}

class _MergeEntry {
  _MergeEntry(this.id, this.pdf);

  final int id;
  final PickedPdf pdf;
  int? pageCount;
}

class _MergePdfScreenState extends State<MergePdfScreen> {
  final PdfMergeService _mergeService = const PdfMergeService();
  final List<_MergeEntry> _entries = [];
  int _nextId = 0;
  bool _merging = false;

  Future<void> _addPdf() async {
    if (_merging) return;
    final pdf = await (widget.pickPdf ?? DocumentIo.pickAndRead)();
    if (pdf == null || !mounted) return;
    final entry = _MergeEntry(_nextId++, pdf);
    setState(() => _entries.add(entry));
    await _loadPageCount(entry);
  }

  Future<void> _loadPageCount(_MergeEntry entry) async {
    try {
      final count = PdfDocument.open(entry.pdf.bytes).pageCount;
      if (!mounted) return;
      final live = _entries.where((e) => e.id == entry.id).toList();
      if (live.isEmpty) return;
      setState(() => live.first.pageCount = count);
    } catch (_) {
      // The merge itself will surface any real problem with the file.
    }
  }

  void _remove(int id) {
    setState(() => _entries.removeWhere((e) => e.id == id));
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final moved = _entries.removeAt(oldIndex);
      _entries.insert(newIndex, moved);
    });
  }

  /// Filenames are not guaranteed unique, so later duplicates get a "(2)"
  /// suffix while the first keeps its real name.
  List<String> _displayNames() {
    final counts = <String, int>{};
    for (final e in _entries) {
      counts[e.pdf.name] = (counts[e.pdf.name] ?? 0) + 1;
    }
    final seen = <String, int>{};
    return [
      for (final e in _entries)
        if (counts[e.pdf.name] == 1 ||
            (seen[e.pdf.name] = (seen[e.pdf.name] ?? 0) + 1) == 1)
          e.pdf.name
        else
          '${pdfStem(e.pdf.name)} (${seen[e.pdf.name]}).pdf',
    ];
  }

  Future<void> _merge() async {
    if (_entries.length < PdfMergeService.minimumSources || _merging) return;
    setState(() => _merging = true);
    try {
      final result = _mergeService.merge([for (final e in _entries) e.pdf]);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MergeResultScreen(
            bytes: result.bytes,
            pageCount: result.pageCount,
            savePdf: widget.savePdf ?? DocumentIo.savePdf,
            sharePdf: widget.sharePdf ?? DocumentIo.sharePdf,
          ),
        ),
      );
    } on PdfToolException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Could not merge the PDFs: $e');
    } finally {
      if (mounted) setState(() => _merging = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canMerge = _entries.length >= PdfMergeService.minimumSources;
    return Scaffold(
      appBar: AppBar(title: const Text('Merge PDF')),
      body: Column(
        children: [
          Expanded(
            child: _entries.isEmpty
                ? _buildEmpty(context)
                : _buildList(context),
          ),
          _buildBottomBar(context, scheme, canMerge),
          const AdBannerView(),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.merge_type, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              'Combine PDFs into one file',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Add at least two PDFs, then arrange and merge them.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _addPdf,
              icon: const Icon(Icons.add),
              label: const Text('Add PDF'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final names = _displayNames();
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: _entries.length + 1,
      onReorderItem: _onReorder,
      proxyDecorator: (child, index, animation) => Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        child: child,
      ),
      itemBuilder: (context, index) {
        if (index == _entries.length) {
          return _AddPdfTile(
            key: const ValueKey('add-pdf'),
            onAdd: _addPdf,
          );
        }
        final entry = _entries[index];
        return _MergeTile(
          key: ValueKey(entry.id),
          position: index + 1,
          displayName: names[index],
          pageCount: entry.pageCount,
          sizeBytes: entry.pdf.sizeBytes,
          onRemove: () => _remove(entry.id),
          dragHandle: ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.drag_handle, size: 20),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(
      BuildContext context, ColorScheme scheme, bool canMerge) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: FilledButton.icon(
          onPressed: canMerge && !_merging ? _merge : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: _merging
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.merge_type),
          label: Text(_merging ? 'Merging…' : 'Merge PDFs'),
        ),
      ),
    );
  }
}

class _MergeTile extends StatelessWidget {
  const _MergeTile({
    super.key,
    required this.position,
    required this.displayName,
    required this.pageCount,
    required this.sizeBytes,
    required this.onRemove,
    required this.dragHandle,
  });

  final int position;
  final String displayName;
  final int? pageCount;
  final int sizeBytes;
  final VoidCallback onRemove;
  final Widget dragHandle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$position',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pageCount != null
                        ? '$pageCount page${pageCount == 1 ? '' : 's'} · '
                            '${formatBytes(sizeBytes)}'
                        : formatBytes(sizeBytes),
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            dragHandle,
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPdfTile extends StatelessWidget {
  const _AddPdfTile({super.key, required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: OutlinedButton.icon(
        onPressed: onAdd,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add PDF'),
      ),
    );
  }
}
