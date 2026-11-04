import 'parse_utils.dart';

/// Columns that say who answered: `user_id` when signed in, else
/// `device_code`. Anonymous rows from before navigation_evaluation.sql have
/// neither, so nothing here assumes the columns or their values exist.
const kSusPersonColumns = ['user_id', 'device_code'];

/// The outcome of keeping one SUS response per person.
class SusDedupeResult {
  /// The counted rows, in their original order.
  final List<Map<String, dynamic>> kept;

  /// Later responses from people already counted.
  final int duplicatesIgnored;

  /// Kept rows with neither id. They can't be matched to anyone, so each
  /// counts once, and repeat answers among them can't be seen.
  final int unidentified;

  /// Of [kSusPersonColumns], those the table doesn't have.
  final List<String> missingColumns;

  const SusDedupeResult({
    this.kept = const [],
    this.duplicatesIgnored = 0,
    this.unidentified = 0,
    this.missingColumns = const [],
  });
}

/// Who wrote [row]: `user:<id>` when signed in, else `device:<code>`, or null
/// with neither.
String? personKey(Map<String, dynamic> row) {
  final user = row['user_id']?.toString().trim() ?? '';
  if (user.isNotEmpty) return 'user:$user';
  final device = row['device_code']?.toString().trim() ?? '';
  return device.isEmpty ? null : 'device:$device';
}

/// Orders by `submitted_at`, then `id`; a row with no date goes last.
int _earliestFirst(Map<String, dynamic> a, Map<String, dynamic> b) {
  final x = parseDate(a['submitted_at']);
  final y = parseDate(b['submitted_at']);
  if (x != null && y != null && x != y) return x.compareTo(y);
  if ((x == null) != (y == null)) return x == null ? 1 : -1;
  final ids = (parseInt(a['id']) ?? 0).compareTo(parseInt(b['id']) ?? 0);
  return ids != 0 ? ids : '${a['id']}'.compareTo('${b['id']}');
}

/// Keeps each person's first response. Run this over every row, before any
/// date filter: otherwise a second response looks like a first one when the
/// real first falls outside the range.
SusDedupeResult dedupeSusRows(List<Map<String, dynamic>> rows) {
  final missing = rows.isEmpty
      ? const <String>[]
      : [
          for (final c in kSusPersonColumns)
            if (!rows.any((r) => r.containsKey(c))) c,
        ];

  final firstOfPerson = <String, Map<String, dynamic>>{};
  var unidentified = 0;
  for (final row in rows) {
    final key = personKey(row);
    if (key == null) {
      unidentified++;
      continue;
    }
    final current = firstOfPerson[key];
    if (current == null || _earliestFirst(row, current) < 0) {
      firstOfPerson[key] = row;
    }
  }

  final counted = firstOfPerson.values.toSet();
  final kept = [
    for (final row in rows)
      if (personKey(row) == null || counted.contains(row)) row,
  ];
  return SusDedupeResult(
    kept: kept,
    duplicatesIgnored: rows.length - kept.length,
    unidentified: unidentified,
    missingColumns: missing,
  );
}

/// The on-screen note for a [SusDedupeResult], or null with nothing to say.
String? susDedupeNote(SusDedupeResult r) {
  final parts = <String>[
    if (r.duplicatesIgnored > 0)
      'One response per person: ${r.duplicatesIgnored} '
          '${r.duplicatesIgnored == 1 ? 'duplicate' : 'duplicates'} ignored.',
    if (r.missingColumns.isNotEmpty)
      'Expected columns: ${kSusPersonColumns.join(', ')}. '
          'Missing: ${r.missingColumns.join(', ')}.',
    if (r.unidentified > 0)
      '${r.unidentified} anonymous '
          '${r.unidentified == 1 ? 'response has' : 'responses have'} no '
          'user_id or device_code, so repeat answers among them can\'t be '
          'detected.',
  ];
  return parts.isEmpty ? null : parts.join(' ');
}
