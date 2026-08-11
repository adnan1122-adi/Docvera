/// A PDF the user has opened before, enough to reopen it later.
///
/// On native platforms the document lives at [path] inside the app's
/// documents directory. On the web the bytes are kept inline in [base64]
/// (localStorage cannot hold large blobs, so oversized files are capped -
/// see [RecentStore.embeddedByteCap]).
class RecentDocument {
  const RecentDocument({
    required this.name,
    required this.sizeBytes,
    required this.lastOpened,
    this.path,
    this.base64,
  });

  final String name;
  final int sizeBytes;
  final DateTime lastOpened;

  /// Absolute path to a copy kept in the app documents directory (native).
  final String? path;

  /// Base64-encoded PDF bytes for web persistence.
  final String? base64;

  bool get canOpen => path != null || base64 != null;

  RecentDocument copyWith({
    String? name,
    int? sizeBytes,
    DateTime? lastOpened,
  }) =>
      RecentDocument(
        name: name ?? this.name,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        lastOpened: lastOpened ?? this.lastOpened,
        path: path,
        base64: base64,
      );

  Map<String, Object?> toJson() => {
        'name': name,
        'sizeBytes': sizeBytes,
        'lastOpened': lastOpened.millisecondsSinceEpoch,
        'path': path,
        'base64': base64,
      };

  factory RecentDocument.fromJson(Map<String, Object?> json) => RecentDocument(
        name: json['name'] as String? ?? 'Untitled.pdf',
        sizeBytes: json['sizeBytes'] as int? ?? 0,
        lastOpened: DateTime.fromMillisecondsSinceEpoch(
            json['lastOpened'] as int? ?? 0),
        path: json['path'] as String?,
        base64: json['base64'] as String?,
      );
}
