import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ads/ad_banner_view.dart';
import '../editor/editor_screen.dart';
import '../models/recent_document.dart';
import '../services/document_io.dart';
import '../services/recent_store.dart';
import '../theme/spacing.dart';
import '../tools/merge_pdf_screen.dart';
import '../tools/split_pdf_screen.dart';
import 'file_drop_stub.dart'
    if (dart.library.js_interop) 'file_drop_web.dart' as file_drop;

/// The landing screen: branding, open actions, drag-and-drop (web) and the
/// list of recent documents. Loading, error, and empty states included.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.darkMode,
    required this.onToggleTheme,
  });

  final bool darkMode;
  final VoidCallback onToggleTheme;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final RecentStore _store = RecentStore();
  List<RecentDocument> _recents = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadRecents();
    file_drop.setupWebFileDrop(_onDropped);
  }

  @override
  void dispose() {
    file_drop.disposeWebFileDrop();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    final list = await _store.load();
    if (!mounted) return;
    setState(() => _recents = list);
  }

  void _onDropped(Uint8List bytes, String name) {
    if (_busy) return;
    _openPdf(PickedPdf(name: name, bytes: bytes));
  }

  Future<void> _pickAndOpen() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final pdf = await DocumentIo.pickAndRead();
      if (pdf == null || !mounted) return;
      await _openPdf(pdf);
    } catch (e) {
      if (mounted) _showError('Could not open the file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPdf(PickedPdf pdf) async {
    final recent = await DocumentIo.persistForRecents(pdf);
    await _store.upsert(recent);
    if (!mounted) return;
    setState(() => _busy = false);
    await _loadRecents();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          title: pdf.name,
          bytes: pdf.bytes,
          recentStore: _store,
        ),
      ),
    );
    if (mounted) await _loadRecents();
  }

  Future<void> _openRecent(RecentDocument doc) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final pdf = await DocumentIo.loadRecent(doc);
      await _store.touch(doc);
      if (!mounted) return;
      setState(() => _busy = false);
      await _loadRecents();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EditorScreen(
            title: pdf.name,
            bytes: pdf.bytes,
            recent: doc,
            recentStore: _store,
          ),
        ),
      );
      if (mounted) await _loadRecents();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _showError('That recent copy is no longer available: $e');
        await _store.remove(doc);
        await _loadRecents();
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openMerge() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MergePdfScreen()),
    );
  }

  void _openSplit() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SplitPdfScreen()),
    );
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Docvera PDF Editor'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Docvera PDF Editor is a professional document-editing tool '
                'that lets you open, edit, annotate, and manage PDF files '
                'entirely on your device.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                'Features',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const _AboutBullet('Edit existing text and add new text, images, signatures, and stamps'),
              const _AboutBullet('Annotate with highlights, underlines, strikethroughs, shapes, and sticky notes'),
              const _AboutBullet('Measure distances, perimeters, areas, volumes, slopes, and angles'),
              const _AboutBullet('Manage pages, search the document, and jump to results instantly'),
              const _AboutBullet('Undo/redo every change and fine-tune properties as you edit'),
              const _AboutBullet('Save, export, or share your finished document'),
              const SizedBox(height: 16),
              Text(
                'Version 1.0.0',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pushNamed('/privacy'),
                    child: const Text('Privacy Policy'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushNamed('/terms'),
                    child: const Text('Terms of Service'),
                  ),
                ],
              ),
            ],
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: _Header(
                            darkMode: widget.darkMode,
                            onToggleTheme: widget.onToggleTheme,
                            onAbout: _showAbout,
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.all(20),
                        sliver: SliverToBoxAdapter(
                          child: _OpenPanel(
                            busy: _busy,
                            onOpen: _pickAndOpen,
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            'PDF Tools',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                        sliver: SliverToBoxAdapter(
                          child: Row(
                            children: [
                              Expanded(
                                child: _PdfToolCard(
                                  icon: Icons.merge_type,
                                  title: 'Merge PDF',
                                  subtitle: 'Combine PDFs into one file',
                                  onTap: _openMerge,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _PdfToolCard(
                                  icon: Icons.call_split,
                                  title: 'Split PDF',
                                  subtitle: 'Extract pages or split up',
                                  onTap: _openSplit,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        sliver: SliverToBoxAdapter(
                          child: Row(
                            children: [
                              Text(
                                'Recent documents',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Spacer(),
                              if (_recents.isNotEmpty)
                                TextButton(
                                  onPressed: () {
                                    for (final d in _recents) {
                                      _store.remove(d);
                                    }
                                    setState(() => _recents = const []);
                                  },
                                  child: const Text('Clear all'),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (_recents.isEmpty)
                        SliverPadding(
                          padding: const EdgeInsets.all(20),
                          sliver: SliverToBoxAdapter(child: _EmptyRecents()),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.all(20),
                          sliver: SliverLayoutBuilder(
                            builder: (context, constraints) {
                              final width = constraints.crossAxisExtent;
                              final columns = width < 620
                                  ? 1
                                  : width < 980
                                      ? 2
                                      : 3;
                              return SliverGrid(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: columns == 1 ? 4.2 : 1.35,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (context, i) => _RecentCard(
                                    doc: _recents[i],
                                    busy: _busy,
                                    onOpen: () => _openRecent(_recents[i]),
                                    onRemove: () async {
                                      await _store.remove(_recents[i]);
                                      await _loadRecents();
                                    },
                                  ),
                                  childCount: _recents.length,
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const AdBannerView(),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.darkMode,
    required this.onToggleTheme,
    required this.onAbout,
  });

  final bool darkMode;
  final VoidCallback onToggleTheme;
  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          ),
          child: const Icon(Icons.picture_as_pdf,
              color: Colors.white, size: 22),
        ),
        const SizedBox(width: AppSpacing.md),
        Flexible(
          child: Text(
            'Docvera PDF Editor',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton(
          icon: Icon(darkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          tooltip: darkMode ? 'Light theme' : 'Dark theme',
          onPressed: onToggleTheme,
        ),
        IconButton(
          icon: const Icon(Icons.info_outline),
          tooltip: 'About',
          onPressed: onAbout,
        ),
      ],
    );
  }
}

class _OpenPanel extends StatelessWidget {
  const _OpenPanel({
    required this.busy,
    required this.onOpen,
  });

  final bool busy;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Open a PDF to start editing',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Annotate, edit text, manage pages, search, and export.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: FilledButton.icon(
                  onPressed: busy ? null : onOpen,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(360, 52),
                  ),
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_outlined, size: 20),
                  label: Text(busy ? 'Opening…' : 'Open PDF'),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (kIsWeb)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_upload_outlined,
                      size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    'or drop a PDF anywhere on this page',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _PdfToolCard extends StatelessWidget {
  const _PdfToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                ),
                child: Icon(icon, color: scheme.primary, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.outline, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({
    required this.doc,
    required this.busy,
    required this.onOpen,
    required this.onRemove,
  });

  final RecentDocument doc;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  String _formatSize(int bytes) {
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  String _formatDate(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${t.day}/${t.month}/${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onOpen,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                ),
                child: Icon(Icons.picture_as_pdf,
                    color: scheme.primary, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      doc.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatSize(doc.sizeBytes)} · ${_formatDate(doc.lastOpened)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Remove from recents',
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyRecents extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.history, size: 30, color: scheme.outline),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'No recent documents yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Open a PDF above and it will show up here.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _AboutBullet extends StatelessWidget {
  const _AboutBullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.check_circle_outline,
              size: 16,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
