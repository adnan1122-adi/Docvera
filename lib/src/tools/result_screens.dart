import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../editor/editor_screen.dart';
import '../services/document_io.dart';
import 'pdf_split_service.dart';
import 'pdf_tool_util.dart';

/// Shared "Merge Complete" screen: filename (editable), Save, Share, and
/// Open in Docvera. Save/Share go through the injected seams so tests can
/// capture the bytes/name without platform channels.
class MergeResultScreen extends StatefulWidget {
  const MergeResultScreen({
    super.key,
    required this.bytes,
    required this.pageCount,
    this.savePdf,
    this.sharePdf,
  });

  final Uint8List bytes;
  final int pageCount;
  final SavePdf? savePdf;
  final SharePdf? sharePdf;

  @override
  State<MergeResultScreen> createState() => _MergeResultScreenState();
}

class _MergeResultScreenState extends State<MergeResultScreen> {
  late final TextEditingController _name =
      TextEditingController(text: 'Merged_Document.pdf');
  bool _saving = false;
  bool _sharing = false;

  String get _fileName => ensurePdfExtension(_name.text);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final ok =
          await (widget.savePdf ?? DocumentIo.savePdf)(widget.bytes, _fileName);
      if (mounted) _snack(ok ? 'Saved $_fileName' : 'Save cancelled.');
    } catch (e) {
      if (mounted) _snack('Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await (widget.sharePdf ?? DocumentIo.sharePdf)(widget.bytes, _fileName);
    } catch (e) {
      if (mounted) _snack('Could not share: $e');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _openInDocvera() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EditorScreen(title: _fileName, bytes: widget.bytes),
    ));
  }

  void _done() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Merge Complete')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 12),
            Icon(Icons.check_circle_outline, size: 56, color: scheme.primary),
            const SizedBox(height: 12),
            Text(
              'Merge Complete',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.pageCount} page${widget.pageCount == 1 ? '' : 's'} · '
              '${formatBytes(widget.bytes.length)}',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Filename',
                hintText: 'Merged_Document.pdf',
                prefixIcon: Icon(Icons.description_outlined),
              ),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              label: Text(_saving ? 'Saving…' : 'Save'),
            ),
            if (!kIsWeb) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _sharing ? null : _share,
                style:
                    OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: _sharing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.share_outlined),
                label: Text(_sharing ? 'Sharing…' : 'Share'),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _openInDocvera,
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.auto_stories_outlined),
              label: const Text('Open in Docvera'),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _done,
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared "Split Complete" screen: one card per output file with per-file
/// Save / Share / Open, plus a "Save all" primary action.
class SplitResultScreen extends StatelessWidget {
  const SplitResultScreen({
    super.key,
    required this.parts,
    this.savePdf,
    this.sharePdf,
  });

  final List<SplitPart> parts;
  final SavePdf? savePdf;
  final SharePdf? sharePdf;

  Future<void> _saveOne(BuildContext context, SplitPart part) async {
    try {
      final ok = await (savePdf ?? DocumentIo.savePdf)(part.bytes, part.name);
      if (context.mounted) {
        _snack(context, ok ? 'Saved ${part.name}' : 'Save cancelled.');
      }
    } catch (e) {
      if (context.mounted) _snack(context, 'Could not save: $e');
    }
  }

  Future<void> _saveAll(BuildContext context) async {
    for (final part in parts) {
      await _saveOne(context, part);
    }
  }

  Future<void> _shareOne(BuildContext context, SplitPart part) async {
    try {
      await (sharePdf ?? DocumentIo.sharePdf)(part.bytes, part.name);
    } catch (e) {
      if (context.mounted) _snack(context, 'Could not share: $e');
    }
  }

  void _openOne(BuildContext context, SplitPart part) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EditorScreen(title: part.name, bytes: part.bytes),
    ));
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Split Complete')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const SizedBox(height: 8),
                  Icon(Icons.check_circle_outline, size: 48, color: scheme.primary),
                  const SizedBox(height: 8),
                  Text(
                    'Split Complete',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${parts.length} file${parts.length == 1 ? '' : 's'} created',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  for (final part in parts)
                    _PartCard(
                      part: part,
                      onSave: () => _saveOne(context, part),
                      onShare: () => _shareOne(context, part),
                      onOpen: () => _openOne(context, part),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _saveAll(context),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Save all'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.of(context).popUntil((route) => route.isFirst),
                      icon: const Icon(Icons.check),
                      label: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartCard extends StatelessWidget {
  const _PartCard({
    required this.part,
    required this.onSave,
    required this.onShare,
    required this.onOpen,
  });

  final SplitPart part;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.picture_as_pdf,
                      size: 20, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        part.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${part.label} · ${part.pageCount} page${part.pageCount == 1 ? '' : 's'} · '
                        '${formatBytes(part.bytes.length)}',
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSave,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Save'),
                  ),
                ),
                if (!kIsWeb) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onShare,
                      icon: const Icon(Icons.share_outlined, size: 18),
                      label: const Text('Share'),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Open'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
