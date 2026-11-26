/// Parses `itunes:duration` values: `3600`, `3600.5`, `59:12`, `1:02:03`.
Duration? parseItunesDuration(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty) return null;
  final parts = s.split(':');
  if (parts.length > 3) return null;
  var total = 0.0;
  for (final p in parts) {
    final v = double.tryParse(p.trim());
    if (v == null || v < 0) return null;
    total = total * 60 + v;
  }
  return Duration(milliseconds: (total * 1000).round());
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

const _zones = {
  'UT': 0, 'GMT': 0, 'Z': 0, 'UTC': 0,
  'EST': -5, 'EDT': -4, 'CST': -6, 'CDT': -5,
  'MST': -7, 'MDT': -6, 'PST': -8, 'PDT': -7,
  'CET': 1, 'CEST': 2, 'BST': 1,
};

final _rfc822 = RegExp(
  r'^(?:[A-Za-z]{3,},?\s+)?(\d{1,2})\s+([A-Za-z]{3,})\.?\s+(\d{2,4})'
  r'(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?\s*([+-]\d{4}|[A-Za-z]{1,4})?',
);

/// Parses RSS dates (RFC 822 / 2822, tolerant) and ISO 8601. Returns UTC.
DateTime? parseFeedDate(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso.toUtc();

  final m = _rfc822.firstMatch(s);
  if (m == null) return null;
  final day = int.parse(m[1]!);
  final month = _months[m[2]!.substring(0, 3).toLowerCase()];
  if (month == null) return null;
  var year = int.parse(m[3]!);
  if (year < 100) year += year < 70 ? 2000 : 1900;
  final h = int.tryParse(m[4] ?? '') ?? 0;
  final min = int.tryParse(m[5] ?? '') ?? 0;
  final sec = int.tryParse(m[6] ?? '') ?? 0;

  var offset = Duration.zero;
  final z = m[7];
  if (z != null) {
    if (z.startsWith('+') || z.startsWith('-')) {
      final sign = z.startsWith('-') ? -1 : 1;
      offset = Duration(
        hours: sign * int.parse(z.substring(1, 3)),
        minutes: sign * int.parse(z.substring(3, 5)),
      );
    } else {
      offset = Duration(hours: _zones[z.toUpperCase()] ?? 0);
    }
  }
  return DateTime.utc(year, month, day, h, min, sec).subtract(offset);
}
