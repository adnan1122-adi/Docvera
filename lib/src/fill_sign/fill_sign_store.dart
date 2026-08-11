import 'dart:convert';

import 'package:dart_pdf_editor/dart_pdf_editor.dart' show PdfInkSignature;
import 'package:shared_preferences/shared_preferences.dart';

/// How a saved signature or initials entry was created.
enum SavedInkKind { drawn, typed }

/// A reusable signature or initials stored on-device for Fill & Sign.
///
/// [drawn] carries an encoded [PdfInkSignature] (vector strokes scaled to a
/// normalized pad box); [typed] carries plain text rendered as a movable
/// FreeText annotation. Entries are persisted in `shared_preferences` only -
/// nothing is uploaded or sent off-device.
class SavedInk {
  const SavedInk({
    required this.name,
    required this.kind,
    this.signature,
    this.text,
  }) : assert(kind == SavedInkKind.drawn
            ? signature != null && text == null
            : text != null && signature == null);

  final String name;
  final SavedInkKind kind;

  /// Non-null for drawn entries: the strokes the pad captured.
  final PdfInkSignature? signature;

  /// Non-null for typed entries: the text the user typed.
  final String? text;

  Map<String, Object?> toJson() => {
        'name': name,
        'kind': kind == SavedInkKind.drawn ? 'drawn' : 'typed',
        if (signature != null) 'data': signature!.encode(),
        if (text != null) 'text': text,
      };

  static SavedInk? fromJson(Map<String, Object?> json) {
    try {
      final kind =
          json['kind'] == 'typed' ? SavedInkKind.typed : SavedInkKind.drawn;
      if (kind == SavedInkKind.drawn) {
        final data = json['data'];
        final decoded = data is String ? PdfInkSignature.decode(data) : null;
        if (decoded == null) return null;
        return SavedInk(
          name: (json['name'] as String?) ?? 'Signature',
          kind: kind,
          signature: decoded,
        );
      }
      final text = json['text'] as String?;
      if (text == null || text.trim().isEmpty) return null;
      return SavedInk(
        name: (json['name'] as String?) ?? 'Signature',
        kind: kind,
        text: text,
      );
    } catch (_) {
      return null;
    }
  }
}

/// The local Fill & Sign library: named signatures and initials that persist
/// on the device (SharedPreferences, `localStorage` on the web) for reuse
/// across documents. Privacy: stored on-device only.
class FillSignStore {
  static const String _signaturesKey = 'docvera.fill_sign.signatures.v1';
  static const String _initialsKey = 'docvera.fill_sign.initials.v1';

  final SharedPreferences _prefs;

  FillSignStore(this._prefs);

  Future<FillSignStore> _ensure() async => this;

  List<SavedInk> _read(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final entry in list)
          if (entry is Map) ?SavedInk.fromJson(entry.cast<String, Object?>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _write(String key, List<SavedInk> entries) async {
    await _prefs.setString(
      key,
      jsonEncode([for (final e in entries) e.toJson()]),
    );
  }

  Future<FillSignStore> load() async => _ensure();

  /// Saved signatures, newest first.
  List<SavedInk> savedSignatures() => _read(_signaturesKey);

  /// Saved initials, newest first.
  List<SavedInk> savedInitials() => _read(_initialsKey);

  /// Adds a signature, saving under [name] (or "My Signature" by default).
  /// Newest first.
  Future<void> saveSignature(SavedInk entry) async {
    final list = List<SavedInk>.of(savedSignatures());
    list.insert(0, entry);
    await _write(_signaturesKey, list);
  }

  /// Adds initials, saving under [name] (or "My Initials" by default).
  Future<void> saveInitials(SavedInk entry) async {
    final list = List<SavedInk>.of(savedInitials());
    list.insert(0, entry);
    await _write(_initialsKey, list);
  }

  /// Removes a saved signature by name.
  Future<void> removeSignature(String name) async {
    final list = List<SavedInk>.of(savedSignatures())
      ..removeWhere((e) => e.name == name);
    await _write(_signaturesKey, list);
  }

  /// Removes saved initials by name.
  Future<void> removeInitials(String name) async {
    final list = List<SavedInk>.of(savedInitials())
      ..removeWhere((e) => e.name == name);
    await _write(_initialsKey, list);
  }
}
