import 'package:dart_pdf_editor/dart_pdf_editor.dart' show PdfPageGeometry;
import 'package:flutter/material.dart';

import 'fill_sign_service.dart';

/// The tap-to-place layer shown while a Fill & Sign place-mode is armed.
///
/// Sits in the app's per-page overlay (beneath the engine's editing layer,
/// which is idle here because no tool is armed). Each tap converts to page
/// space through [geometry] and places the armed object; drags pass through
/// to the viewer's pan/scroll, so filling a long page stays comfortable.
class FillSignPlaceTarget extends StatelessWidget {
  const FillSignPlaceTarget({
    super.key,
    required this.geometry,
    required this.config,
    required this.onPlace,
  });

  final PdfPageGeometry geometry;
  final FillSignPlaceConfig config;
  final void Function(double x, double y) onPlace;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          final (x, y) = geometry.toPagePoint(details.localPosition);
          onPlace(x, y);
        },
        child: IgnorePointer(
          child: Center(
            child: Semantics(
              label: config.hint,
              child: _PlaceBadge(config: config),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaceBadge extends StatelessWidget {
  const _PlaceBadge({required this.config});

  final FillSignPlaceConfig config;

  IconData get _icon => switch (config.kind) {
        FillSignPlaceKind.date => Icons.event_outlined,
        FillSignPlaceKind.typedText => Icons.text_fields,
        FillSignPlaceKind.drawnInk => Icons.history_edu_outlined,
        FillSignPlaceKind.checkbox => Icons.check_box_outline_blank,
        FillSignPlaceKind.xMark => Icons.close,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            'Tap to place',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}