import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/recent_document.dart';

/// Persists the list of recently opened documents in `shared_preferences`.
///
/// Entries are capped at [RecentStore.maxEntries]; reopening a document bumps
/// it to the front. Bytes embedded for the web are capped at
/// [RecentStore.embeddedByteCap] so localStorage quota is never blown.
class RecentStore {
  static const String _key = 'pdf_editor.recent_documents.v1';

  /// Hard cap on how many recents are kept.
  static const int maxEntries = 12;

  /// Web-only: bytes larger than this are not embedded in preferences (the
  /// entry is kept but cannot be reopened from recents).
  static const int embeddedByteCap = 6 * 1024 * 1024;

  Future<List<RecentDocument>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <RecentDocument>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => RecentDocument.fromJson(e.cast<String, Object?>()))
          .toList();
    } catch (_) {
      return <RecentDocument>[];
    }
  }

  Future<void> upsert(RecentDocument doc) async {
    final prefs = await SharedPreferences.getInstance();
    final list = List<RecentDocument>.of(await load());
    list.removeWhere((d) => d.name == doc.name && d.path == doc.path);
    list.insert(0, doc);
    if (list.length > maxEntries) list.removeRange(maxEntries, list.length);
    await prefs.setString(_key, jsonEncode(list.map((d) => d.toJson()).toList()));
  }

  Future<void> touch(RecentDocument doc) =>
      upsert(doc.copyWith(lastOpened: DateTime.now()));

  Future<void> remove(RecentDocument doc) async {
    final prefs = await SharedPreferences.getInstance();
    final list = List<RecentDocument>.of(await load());
    list.removeWhere((d) => d.name == doc.name && d.path == doc.path);
    await prefs.setString(_key, jsonEncode(list.map((d) => d.toJson()).toList()));
  }
}
