import 'package:flutter/material.dart';

import 'fill_sign_store.dart';

/// What the user chose from the Fill & Sign library sheet.
enum FillSignLibraryAction { drawNew, typeNew, saved }

class FillSignLibraryChoice {
  const FillSignLibraryChoice(this.action, {this.entry});

  const FillSignLibraryChoice.drawNew()
      : this(FillSignLibraryAction.drawNew);

  const FillSignLibraryChoice.typeNew()
      : this(FillSignLibraryAction.typeNew);

  const FillSignLibraryChoice.saved(SavedInk entry)
      : this(FillSignLibraryAction.saved, entry: entry);

  final FillSignLibraryAction action;

  /// The chosen saved entry (non-null only for [FillSignLibraryAction.saved]).
  final SavedInk? entry;
}

/// A bottom sheet to pick (or create) a signature/initials: draws new, types
/// new, or reuses a previously saved on-device entry. The entry is shown with
/// a delete control; removal stays local.
///
/// Resolves to a [FillSignLibraryChoice], or null when dismissed.
Future<FillSignLibraryChoice?> showFillSignLibrarySheet(
  BuildContext context, {
  required String title,
  required List<SavedInk> Function() load,
  required Future<void> Function(SavedInk entry) remove,
}) {
  return showModalBottomSheet<FillSignLibraryChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _FillSignLibrarySheet(
      title: title,
      load: load,
      remove: remove,
    ),
  );
}

class _FillSignLibrarySheet extends StatefulWidget {
  const _FillSignLibrarySheet({
    required this.title,
    required this.load,
    required this.remove,
  });

  final String title;
  final List<SavedInk> Function() load;
  final Future<void> Function(SavedInk entry) remove;

  @override
  State<_FillSignLibrarySheet> createState() => _FillSignLibrarySheetState();
}

class _FillSignLibrarySheetState extends State<_FillSignLibrarySheet> {
  late List<SavedInk> _entries = widget.load();

  void _refresh() => setState(() => _entries = widget.load());

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                widget.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.draw_outlined, color: scheme.primary),
              title: const Text('Draw new'),
              subtitle: const Text('Use the drawing pad'),
              onTap: () => Navigator.of(context)
                  .pop(const FillSignLibraryChoice.drawNew()),
            ),
            ListTile(
              leading: Icon(Icons.keyboard_outlined, color: scheme.primary),
              title: const Text('Type new'),
              subtitle: const Text('Type it as text'),
              onTap: () => Navigator.of(context)
                  .pop(const FillSignLibraryChoice.typeNew()),
            ),
            if (_entries.isNotEmpty) ...[
              const Divider(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Saved on this device',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    return ListTile(
                      leading: Icon(
                        entry.kind == SavedInkKind.drawn
                            ? Icons.history_edu
                            : Icons.text_fields,
                        color: scheme.onSurfaceVariant,
                      ),
                      title: Text(entry.name),
                      subtitle: Text(
                        entry.kind == SavedInkKind.drawn
                            ? 'Drawn'
                            : 'Typed',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        tooltip: 'Delete',
                        onPressed: () async {
                          await widget.remove(entry);
                          if (mounted) _refresh();
                        },
                      ),
                      onTap: () => Navigator.of(context).pop(
                        FillSignLibraryChoice.saved(entry),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}