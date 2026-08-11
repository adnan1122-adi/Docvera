import 'dart:typed_data';

typedef DropHandler = void Function(Uint8List bytes, String name);

/// Native builds get drag-and-drop through the file picker; the global web
/// listeners are a no-op here.
void setupWebFileDrop(DropHandler onPdf) {}

void disposeWebFileDrop() {}
