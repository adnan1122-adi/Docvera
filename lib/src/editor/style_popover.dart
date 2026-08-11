import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart' show PdfTextAlign;

/// Preset swatches for the quick color picker.
const List<Color> kStyleSwatches = [
  Color(0xFF000000),
  Color(0xFFFFFFFF),
  Color(0xFF525252),
  Color(0xFF9E9E9E),
  Color(0xFFE53935),
  Color(0xFFFB8C00),
  Color(0xFFFDD835),
  Color(0xFF43A047),
  Color(0xFF1E88E5),
  Color(0xFF8E24AA),
  Color(0xFF6D4C41),
  Color(0xFF00ACC1),
];

/// Opens an anchored popover with the live style controls for the active
/// tool (colour, stroke width, opacity, font, size).
Future<void> showPdfStylePopover(
  BuildContext context, {
  required PdfEditingController editing,
  required PdfViewerController viewer,
}) async {
  final box = context.findRenderObject() as RenderBox?;
  final anchor = box == null
      ? Offset.zero
      : box.localToGlobal(Offset.zero);
  final size = MediaQuery.sizeOf(context);

  var top = anchor.dy - 12;
  var left = anchor.dx - 260;
  top = top.clamp(8.0, size.height - 480).toDouble();
  left = left.clamp(8.0, size.width - 280).toDouble();

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss style popover',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (_, _, _) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        Positioned(
          top: top,
          left: left,
          child: _StylePanel(editing: editing),
        ),
      ],
    ),
  );
}

class _StylePanel extends StatefulWidget {
  const _StylePanel({required this.editing});

  final PdfEditingController editing;

  @override
  State<_StylePanel> createState() => _StylePanelState();
}

class _StylePanelState extends State<_StylePanel> {
  late double _strokeWidth;
  late double _opacity;
  late double _fontSize;
  late PdfStandardFont _font;
  late PdfTextAlign? _align;

  PdfEditingController get editing => widget.editing;

  @override
  void initState() {
    super.initState();
    final prefs = editing.preferences;
    _strokeWidth = prefs.strokeWidth;
    _opacity = prefs.opacity;
    _fontSize = prefs.fontSize;
    _font = prefs.fontFamily;
    _align = prefs.textAlign;
  }

  Future<void> _pickColor() async {
    final color = await showPdfColorPicker(
      context,
      initial: editing.color,
      recentColors: editing.preferences.recentColors,
    );
    if (color != null) editing.color = color;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prefs = editing.preferences;

    Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              child,
            ],
          ),
        );

    return Material(
      elevation: 6,
      shadowColor: Colors.black38,
      color: scheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 268,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              section(
                'Color',
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final swatch in kStyleSwatches)
                      _Swatch(
                        color: swatch,
                        selected: editing.color.toARGB32() == swatch.toARGB32(),
                        onTap: () => editing.color = swatch,
                      ),
                    Tooltip(
                      message: 'More colors',
                      child: InkWell(
                        onTap: _pickColor,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: scheme.outline),
                          ),
                          child: Icon(Icons.add, size: 18, color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              section(
                'Stroke width',
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _strokeWidth,
                        min: 1,
                        max: 12,
                        divisions: 11,
                        label: '${_strokeWidth.round()}',
                        onChanged: (v) {
                          setState(() => _strokeWidth = v);
                          prefs.strokeWidth = v;
                        },
                      ),
                    ),
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${_strokeWidth.round()}',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
              section(
                'Opacity',
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _opacity,
                        min: 0.1,
                        max: 1,
                        divisions: 9,
                        onChanged: (v) {
                          setState(() => _opacity = v);
                          prefs.opacity = v;
                        },
                      ),
                    ),
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${(100 * _opacity).round()}%',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
              section(
                'Font',
                DropdownButton<PdfStandardFont>(
                  value: _font,
                  isExpanded: true,
                  items: [
                    for (final f in PdfStandardFont.values)
                      DropdownMenuItem(
                        value: f,
                        child: Text(
                          f.baseFont,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (f) {
                    if (f == null) return;
                    setState(() => _font = f);
                    prefs.fontFamily = f;
                  },
                ),
              ),
              section(
                'Font size',
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _fontSize,
                        min: 6,
                        max: 72,
                        divisions: 33,
                        onChanged: (v) {
                          setState(() => _fontSize = v);
                          prefs.fontSize = v;
                        },
                      ),
                    ),
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${_fontSize.round()}',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
              section(
                'Alignment',
                SegmentedButton<PdfTextAlign?>(
                  segments: const [
                    ButtonSegment<PdfTextAlign?>(
                      value: PdfTextAlign.left,
                      icon: Icon(Icons.format_align_left, size: 16),
                    ),
                    ButtonSegment<PdfTextAlign?>(
                      value: PdfTextAlign.center,
                      icon: Icon(Icons.format_align_center, size: 16),
                    ),
                    ButtonSegment<PdfTextAlign?>(
                      value: PdfTextAlign.right,
                      icon: Icon(Icons.format_align_right, size: 16),
                    ),
                  ],
                  selected: {_align},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    final value = selection.firstOrNull;
                    setState(() => _align = value);
                    prefs.textAlign = value;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outline,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check,
                size: 15,
                color: color.computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white,
              )
            : null,
      ),
    );
  }
}
