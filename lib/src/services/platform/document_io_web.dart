import 'dart:typed_data';

/// Web build has no filesystem - the caller embeds bytes as base64 instead.
abstract final class PlatformDocumentIo {
  static Future<String?> persistCopy(Uint8List bytes, String name) async => null;

  static Future<Uint8List> readPath(String path) =>
      throw UnsupportedError('No filesystem on the web.');

  static Future<void> writeToPath(String path, Uint8List bytes) =>
      throw UnsupportedError('No filesystem on the web.');

  static Future<void> deleteFile(String path) async {}

  static Future<String> writeTemp(Uint8List bytes, String name) =>
      throw UnsupportedError('No filesystem on the web.');
}
