import 'dart:math' as math;

import 'package:dart_pdf_editor/dart_pdf_editor.dart'
    show PdfInkSignature;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

/// Ink colours offered on the drawing pads.
const List<Color> kFillSignInks = [
  Color(0xFF000000),
  Color(0xFF1A3E8C),
  Color(0xFFB71C1C),
];

/// Shows the Fill & Sign drawing pad: capture a signature or initials with
/// a mouse, finger, or stylus (pressure-aware strokes), with clear, undo
/// (stroke-by-stroke), ink colour, cancel and save. Resolves to the drawn
/// [PdfInkSignature], or null when cancelled.
Future<PdfInkSignature?> showFillSignInkPad(
  BuildContext context, {
  required String title,
  String saveLabel = 'Save',
}) async {
  final size = MediaQuery.sizeOf(context);
  final padWidth = math.min(360.0, size.width - 48);
  return showDialog<PdfInkSignature>(
    context: context,
    builder: (context) => _FillSignInkPadDialog(
      title: title,
      saveLabel: saveLabel,
      padWidth: padWidth,
    ),
  );
}

/// Asks the user to type a signature or initials. Resolves to the text, or
/// null when cancelled.
Future<String?> showFillSignTypeDialog(
  BuildContext context, {
  required String title,
  required String hint,
  String initial = '',
}) =>
    showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: initial);
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                Navigator.of(context).pop(value.trim());
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) Navigator.of(context).pop(value);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

/// Asks for a name to save a signature/initials under (e.g. "My Signature").
/// Resolves to the trimmed name (empty means "keep the default"), or null
/// when cancelled.
Future<String?> showFillSignNameDialog(
  BuildContext context, {
  required String title,
  String placeholder = 'My Signature',
}) =>
    showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: placeholder);
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. My Signature',
            ),
            onSubmitted: (value) =>
                Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

/// Asks for the current (or a manual) date. Resolves to the date text, or
/// null when cancelled. Defaults to today, formatted dd/MM/yyyy.
Future<String?> showFillSignDateDialog(BuildContext context) async {
  var text = _formatDate(DateTime.now());
  return showDialog<String>(
    context: context,
    builder: (context) {
      final controller = TextEditingController(text: text);
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Insert date'),
          content: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'dd/MM/yyyy',
                    isDense: true,
                  ),
                  onChanged: (v) => text = v,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.calendar_today_outlined),
                tooltip: 'Pick a date',
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    controller.text = _formatDate(picked);
                    setState(() => text = controller.text);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = text.trim();
                if (value.isNotEmpty) Navigator.of(context).pop(value);
              },
              child: const Text('Place'),
            ),
          ],
        ),
      );
    },
  );
}

String _formatDate(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd/$mm/${d.year}';
}

class _FillSignInkPadDialog extends StatefulWidget {
  const _FillSignInkPadDialog({
    required this.title,
    required this.saveLabel,
    required this.padWidth,
  });

  final String title;
  final String saveLabel;
  final double padWidth;

  @override
  State<_FillSignInkPadDialog> createState() => _FillSignInkPadDialogState();
}

class _FillSignInkPadDialogState extends State<_FillSignInkPadDialog> {
  final List<List<Offset>> _strokes = [];
  final List<List<double>?> _pressures = [];
  List<Offset>? _active;
  List<double>? _activePressures;
  double? _pointerPressure;
  Color _ink = kFillSignInks.first;

  bool get _isEmpty => _strokes.isEmpty && _active == null;

  static double? _pressureOf(PointerEvent event) {
    if (event.pressureMax <= event.pressureMin) return null;
    return ((event.pressure - event.pressureMin) /
            (event.pressureMax - event.pressureMin))
        .clamp(0.0, 1.0);
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() {
      _strokes.removeLast();
      _pressures.removeLast();
    });
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _pressures.clear();
      _active = null;
      _activePressures = null;
    });
  }

  void _save() {
    final signature = PdfInkSignature.fromPad(_strokes, _pressures, _ink);
    if (signature != null) Navigator.of(context).pop(signature);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: widget.padWidth,
            height: 180,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: scheme.outline),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Listener(
                onPointerDown: (e) =>
                    _pointerPressure = _pressureOf(e),
                onPointerMove: (e) =>
                    _pointerPressure = _pressureOf(e),
                child: GestureDetector(
                  dragStartBehavior: DragStartBehavior.down,
                  onPanStart: (details) {
                    final pressure = _pointerPressure;
                    setState(() {
                      _active = [details.localPosition];
                      _activePressures =
                          pressure == null ? null : [pressure];
                    });
                  },
                  onPanUpdate: (details) {
                    setState(() {
                      _active!.add(details.localPosition);
                      _activePressures
                          ?.add(_pointerPressure ?? _activePressures!.last);
                    });
                  },
                  onPanEnd: (_) {
                    final stroke = _active;
                    if (stroke == null) return;
                    setState(() {
                      _strokes.add(stroke);
                      _pressures.add(_activePressures);
                      _active = null;
                      _activePressures = null;
                    });
                  },
                  child: CustomPaint(
                    key: const ValueKey('fill-sign-pad'),
                    size: Size(widget.padWidth, 180),
                    painter: _FillSignPadPainter(
                      strokes: [
                        ..._strokes,
                        ?_active,
                      ],
                      pressures: [
                        ..._pressures,
                        ?_activePressures,
                      ],
                      color: _ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            for (final ink in kFillSignInks)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: InkWell(
                  onTap: () => setState(() => _ink = ink),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: ink,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _ink == ink
                            ? scheme.primary
                            : scheme.outline,
                        width: _ink == ink ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            TextButton.icon(
              onPressed: _isEmpty ? null : _undo,
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('Undo'),
            ),
            TextButton(
              onPressed: _isEmpty
                  ? null
                  : () => setState(_clear),
              child: const Text('Clear'),
            ),
          ]),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isEmpty ? null : _save,
          child: Text(widget.saveLabel),
        ),
      ],
    );
  }
}

class _FillSignPadPainter extends CustomPainter {
  _FillSignPadPainter({
    required this.strokes,
    required this.pressures,
    required this.color,
  });

  final List<List<Offset>> strokes;
  final List<List<double>?> pressures;
  final Color color;

  static const _baseWidth = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < strokes.length; i++) {
      final stroke = strokes[i];
      final pressure = pressures[i];
      if (stroke.length < 2) {
        paint.strokeWidth = pressure?.isNotEmpty == true
            ? _baseWidth * 2 * pressure!.first
            : _baseWidth;
        canvas.drawCircle(stroke.first, paint.strokeWidth / 2, paint);
        continue;
      }
      for (var s = 0; s < stroke.length - 1; s++) {
        paint.strokeWidth = pressure?.isNotEmpty == true
            ? _baseWidth * 2 * pressure![s]
            : _baseWidth;
        canvas.drawLine(stroke[s], stroke[s + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(_FillSignPadPainter old) =>
      old.strokes != strokes ||
      old.pressures != pressures ||
      old.color != color;
}
