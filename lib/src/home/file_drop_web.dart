import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

typedef DropHandler = void Function(Uint8List bytes, String name);

JSFunction? _over;
JSFunction? _drop;

/// Registers global `dragover`/`drop` listeners on the web so a PDF dropped
/// anywhere on the page is handed to [onPdf]. Capture-phase listeners beat
/// Flutter's own drag handling.
void setupWebFileDrop(DropHandler onPdf) {
  void over(web.Event e) => e.preventDefault();

  void drop(web.Event e) {
    e.preventDefault();
    final dataTransfer = (e as web.DragEvent).dataTransfer;
    if (dataTransfer == null) return;
    final files = dataTransfer.files;
    if (files.length != 1) return;
    final file = files.item(0);
    if (file == null || !file.name.toLowerCase().endsWith('.pdf')) return;
    file.arrayBuffer().toDart.then((ab) {
      onPdf(ab.toDart.asUint8List(), file.name);
    });
  }

  _over = over.toJS;
  _drop = drop.toJS;
  web.window.addEventListener('dragover', _over, true.toJS);
  web.window.addEventListener('drop', _drop, true.toJS);
}

void disposeWebFileDrop() {
  if (_over != null) web.window.removeEventListener('dragover', _over!);
  if (_drop != null) web.window.removeEventListener('drop', _drop!);
  _over = null;
  _drop = null;
}
