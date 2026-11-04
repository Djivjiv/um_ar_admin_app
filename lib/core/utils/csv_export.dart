import 'dart:convert';
import 'dart:typed_data';

import 'file_save.dart';

/// One CSV cell. Text starting with `=`, `+`, `-`, `@`, tab or return is what
/// Excel runs as a formula, and these cells can hold text the public typed,
/// so a leading `'` keeps it as plain text.
String _cell(Object? value) {
  var text = value?.toString() ?? '';
  if (value is String && RegExp(r'^[=+\-@\t\r]').hasMatch(text)) {
    text = "'$text";
  }
  if (RegExp(r'[",\r\n]').hasMatch(text)) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

/// [rows] (first row = header) as CSV text.
String csvEncode(List<List<Object?>> rows) =>
    rows.map((r) => r.map(_cell).join(',')).join('\r\n');

/// Saves [rows] as a `.csv` file. Starts with a UTF-8 byte order mark, which
/// Excel needs to read accents and "ñ" correctly. Returns the saved path or
/// downloaded file name, or null if cancelled.
Future<String?> saveCsvFile(String suggestedName, List<List<Object?>> rows) {
  final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(csvEncode(rows))];
  return saveBytes(
    fileName: '$suggestedName.csv',
    bytes: Uint8List.fromList(bytes),
    dialogTitle: 'Export to CSV',
    extension: 'csv',
    mimeType: 'text/csv',
  );
}
