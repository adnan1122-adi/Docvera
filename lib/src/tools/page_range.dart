/// A closed 1-based inclusive page range, e.g. "1-3" or a single page "10".
class PageRange {
  const PageRange(this.start, this.end)
      : assert(start >= 1),
        assert(end >= start);

  final int start;
  final int end;

  int get length => end - start + 1;

  bool get isSingle => start == end;

  @override
  String toString() => isSingle ? '$start' : '$start-$end';

  @override
  bool operator ==(Object other) =>
      other is PageRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Parses a user-entered range list like "1-3, 5-7, 10" into [PageRange]s.
///
/// Throws a [FormatException] with a user-friendly message for malformed or
/// duplicate input. Values are NOT checked against the document's real page
/// count here; that happens at split time.
List<PageRange> parsePageRanges(String input) {
  final tokens =
      input.split(RegExp(r'[,\s]+')).where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) {
    throw const FormatException('Enter at least one page or range.');
  }
  final ranges = <PageRange>[];
  final seen = <String>{};
  for (final token in tokens) {
    final match = RegExp(r'^(\d+)(?:-(\d+))?$').firstMatch(token);
    if (match == null) {
      throw FormatException(
          '"$token" is not a valid page or range. Use numbers like 3 or '
          'ranges like 1-3.');
    }
    if (seen.contains(token)) {
      throw FormatException('"$token" is listed more than once.');
    }
    seen.add(token);
    final start = int.parse(match.group(1)!);
    final end = int.parse(match.group(2) ?? match.group(1)!);
    if (start < 1) {
      throw FormatException('Pages are numbered from 1, not $start.');
    }
    if (end < start) {
      throw FormatException('Range "$token" is invalid: $start comes after $end.');
    }
    ranges.add(PageRange(start, end));
  }
  return ranges;
}
