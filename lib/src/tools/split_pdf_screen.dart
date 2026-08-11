import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart' show PdfPageRenderer;
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

import '../ads/ad_banner_view.dart';
import '../services/document_io.dart';
import 'page_range.dart';
import 'pdf_split_service.dart';
import 'pdf_tool_util.dart';
import 'result_screens.dart';

enum _SplitMethod { pages, ranges, everyN }

/// Split PDF screen: pick one PDF, choose a method (extract pages, split by
/// ranges, or split every N pages), preview, then split into new files.
class SplitPdfScreen extends StatefulWidget {
  const SplitPdfScreen({
    super.key,
    this.pickPdf,
    this.savePdf,
    this.sharePdf,
    this.showThumbnails = true,
  });

  /// Test seams, defaulting to the real [DocumentIo] calls.
  final PickPdf? pickPdf;
  final SavePdf? savePdf;
  final SharePdf? sharePdf;

  /// Renders real page thumbnails in the page grid. Disabled in widget tests
  /// where rasterization is out of scope; also skipped for large documents.
  final bool showThumbnails;

  @override
  State<SplitPdfScreen> createState() => _SplitPdfScreenState();
}

class _SplitPdfScreenState extends State<SplitPdfScreen> {
  static const int _thumbnailPageCap = 40;

  final PdfSplitService _splitService = const PdfSplitService();

  PickedPdf? _source;
  PdfDocument? _doc;
  int? _pageCount;
  _SplitMethod _method = _SplitMethod.pages;
  final List<int> _selected = <int>[];
  final TextEditingController _ranges = TextEditingController();
  final TextEditingController _every = TextEditingController(text: '2');
  bool _splitting = false;

  @override
  void dispose() {
    _ranges.dispose();
    _every.dispose();
    super.dispose();
  }

  Future<void> _pickSource() async {
    if (_splitting) return;
    final pdf = await (widget.pickPdf ?? DocumentIo.pickAndRead)();
    if (pdf == null || !mounted) return;
    try {
      final doc = PdfDocument.open(pdf.bytes);
      setState(() {
        _source = pdf;
        _doc = doc;
        _pageCount = doc.pageCount;
        _selected.clear();
      });
      if (_pageCount == 0) {
        _snack('That file contains no pages.');
      }
    } catch (_) {
      _snack('Could not read "${pdf.name}". It may be damaged or '
          'password-protected.');
    }
  }

  void _changeSource() {
    _doc = null;
    _pickSource();
  }

  void _togglePage(int page) {
    setState(() {
      if (_selected.contains(page)) {
        _selected.remove(page);
      } else {
        _selected.add(page);
      }
    });
  }

  void _clearSelection() => setState(_selected.clear);

  Future<void> _split() async {
    final source = _source;
    if (source == null || _splitting) return;
    setState(() => _splitting = true);
    try {
      final List<SplitPart> parts;
      switch (_method) {
        case _SplitMethod.pages:
          if (_selected.isEmpty) {
            _snack('Select at least one page to extract.');
            return;
          }
          parts = [
            _splitService.extractPages(source.bytes, source.name, List.of(_selected)),
          ];
        case _SplitMethod.ranges:
          final ranges = parsePageRanges(_ranges.text);
          parts = _splitService.splitByRanges(source.bytes, source.name, ranges);
        case _SplitMethod.everyN:
          final n = int.tryParse(_every.text.trim());
          if (n == null) {
            _snack('Enter a number of pages per part.');
            return;
          }
          parts = _splitService.splitEvery(source.bytes, source.name, n);
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SplitResultScreen(
            parts: parts,
            savePdf: widget.savePdf ?? DocumentIo.savePdf,
            sharePdf: widget.sharePdf ?? DocumentIo.sharePdf,
          ),
        ),
      );
    } on FormatException catch (e) {
      _snack(e.message);
    } on PdfToolException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Could not split the PDF: $e');
    } finally {
      if (mounted) setState(() => _splitting = false);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Split PDF')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSourceCard(context, scheme),
                if (_source != null && _pageCount != null) ...[
                  const SizedBox(height: 20),
                  _buildMethodSelector(context),
                  const SizedBox(height: 16),
                  _buildMethodPanel(context, scheme),
                ],
              ],
            ),
          ),
          _buildBottomBar(context, scheme),
          const AdBannerView(),
        ],
      ),
    );
  }

  Widget _buildSourceCard(BuildContext context, ColorScheme scheme) {
    final source = _source;
    if (source == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.picture_as_pdf, size: 44, color: scheme.outline),
              const SizedBox(height: 10),
              Text(
                'Select a PDF to split',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Split pages into new PDFs. The original file stays unchanged.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _pickSource,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Select PDF'),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.picture_as_pdf,
                  color: scheme.onPrimaryContainer, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$_pageCount page${_pageCount == 1 ? '' : 's'} · '
                    '${formatBytes(source.sizeBytes)}',
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: _changeSource, child: const Text('Change')),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodSelector(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Split method',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<_SplitMethod>(
            segments: const [
              ButtonSegment(
                value: _SplitMethod.pages,
                label: Text('Pages'),
              ),
              ButtonSegment(
                value: _SplitMethod.ranges,
                label: Text('Ranges'),
              ),
              ButtonSegment(
                value: _SplitMethod.everyN,
                label: Text('Every N'),
              ),
            ],
            selected: {_method},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => _method = selection.first),
          ),
        ),
      ],
    );
  }

  Widget _buildMethodPanel(BuildContext context, ColorScheme scheme) {
    switch (_method) {
      case _SplitMethod.pages:
        return _buildPagesPanel(context, scheme);
      case _SplitMethod.ranges:
        return _buildRangesPanel(context, scheme);
      case _SplitMethod.everyN:
        return _buildEveryNPanel(context, scheme);
    }
  }

  Widget _buildPagesPanel(BuildContext context, ColorScheme scheme) {
    final count = _pageCount!;
    final canThumb = widget.showThumbnails &&
        _doc != null &&
        count <= _thumbnailPageCap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _selected.isEmpty
                    ? 'Tap pages to extract'
                    : 'Extracting: ${_selected.join(', ')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
            if (_selected.isNotEmpty)
              TextButton(
                onPressed: _clearSelection,
                child: const Text('Clear'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 78,
            childAspectRatio: 0.62,
          ),
          itemCount: count,
          itemBuilder: (context, i) {
            final page = i + 1;
            final order = _selected.indexOf(page);
            return _PageTile(
              page: page,
              selected: order >= 0,
              order: order >= 0 ? order + 1 : 0,
              thumbnail: canThumb
                  ? _PageThumb(doc: _doc!, index: i)
                  : null,
              onTap: () => _togglePage(page),
            );
          },
        ),
      ],
    );
  }

  Widget _buildRangesPanel(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Split into separate PDFs by page ranges.',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _ranges,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Ranges',
            hintText: 'e.g. 1-3, 5-7, 10',
            prefixIcon: Icon(Icons.tag_outlined),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        _buildRangesPreview(context, scheme),
      ],
    );
  }

  Widget _buildRangesPreview(BuildContext context, ColorScheme scheme) {
    final text = _ranges.text.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    try {
      final ranges = parsePageRanges(text);
      final total = ranges.fold<int>(0, (sum, r) => sum + r.length);
      return Text(
        '$total page${total == 1 ? '' : 's'} across '
        '${ranges.length} part${ranges.length == 1 ? '' : 's'}',
        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
      );
    } on FormatException catch (e) {
      return Text(
        e.message,
        style: TextStyle(fontSize: 12.5, color: scheme.error),
      );
    }
  }

  Widget _buildEveryNPanel(BuildContext context, ColorScheme scheme) {
    final count = _pageCount!;
    final n = int.tryParse(_every.text.trim());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Split the document into consecutive parts of N pages each.',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _every,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Pages per part',
            hintText: '2',
            prefixIcon: Icon(Icons.filter_none_outlined),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        if (n != null && n >= 1 && n <= count)
          Text(
            _partsSummary(count, n),
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          )
        else if (n != null)
          Text(
            'Split size must be between 1 and $count.',
            style: TextStyle(fontSize: 12.5, color: scheme.error),
          ),
      ],
    );
  }

  String _partsSummary(int count, int n) {
    final parts = (count + n - 1) ~/ n;
    final ranges = <String>[];
    for (var i = 0; i < parts; i++) {
      final start = i * n + 1;
      final end = (start + n - 1) > count ? count : start + n - 1;
      ranges.add(start == end ? '$start' : '$start-$end');
    }
    return '$parts part${parts == 1 ? '' : 's'}: ${ranges.join(', ')}';
  }

  Widget _buildBottomBar(BuildContext context, ColorScheme scheme) {
    final enabled = _source != null && !_splitting;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: FilledButton.icon(
          onPressed: enabled ? _split : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: _splitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.call_split),
          label: Text(_splitting ? 'Splitting…' : 'Split PDF'),
        ),
      ),
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    required this.page,
    required this.selected,
    required this.order,
    required this.thumbnail,
    required this.onTap,
  });

  final int page;
  final bool selected;
  final int order;
  final Widget? thumbnail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey('split-page-$page'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.35)
              : scheme.surfaceContainerLow,
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.topRight,
              children: [
                Container(
                  width: 52,
                  height: 66,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: Icon(Icons.description_outlined,
                            size: 18, color: scheme.outline),
                      ),
                      ?thumbnail,
                    ],
                  ),
                ),
                if (selected)
                  Container(
                    margin: const EdgeInsets.all(3),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '$order',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$page',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lazily renders a low-resolution thumbnail for one page. Falls back to the
/// numbered placeholder behind it when rendering fails.
class _PageThumb extends StatefulWidget {
  const _PageThumb({required this.doc, required this.index});

  final PdfDocument doc;
  final int index;

  @override
  State<_PageThumb> createState() => _PageThumbState();
}

class _PageThumbState extends State<_PageThumb> {
  ui.Image? _image;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _render();
  }

  Future<void> _render() async {
    try {
      final image = await PdfPageRenderer.renderImage(
        widget.doc.page(widget.index),
        pixelRatio: 0.4,
        annotations: true,
      );
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image != null) {
      return RawImage(image: image, fit: BoxFit.contain);
    }
    if (_failed) return const SizedBox.shrink();
    return Center(
      child: SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}
