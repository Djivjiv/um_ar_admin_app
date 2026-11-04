import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'file_save.dart';

CellValue _cell(Object? value) {
  if (value == null) return TextCellValue('');
  if (value is int) return IntCellValue(value);
  if (value is double) {
    return value.isFinite ? DoubleCellValue(value) : TextCellValue('$value');
  }
  if (value is bool) return TextCellValue(value ? 'TRUE' : 'FALSE');
  if (value is num) return DoubleCellValue(value.toDouble());
  return TextCellValue(value.toString());
}

/// One sheet of a workbook. The first row of [rows] is the header.
class ExcelSheetData {
  final String name;
  final List<List<Object?>> rows;

  const ExcelSheetData(this.name, this.rows);
}

/// A name Excel accepts: 31 characters at most, none of `[]*?/\:`.
String _safeSheetName(String name) {
  final safe = (name.length > 31 ? name.substring(0, 31) : name)
      .replaceAll(RegExp(r'[\[\]\*\?/\\:]'), ' ')
      .trim();
  return safe.isEmpty ? 'Sheet1' : safe;
}

/// The `.xlsx` file for [sheets], in order, or null if it can't be built.
List<int>? buildExcelBytes(List<ExcelSheetData> sheets) {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
  for (final (index, data) in sheets.indexed) {
    final name = _safeSheetName(data.name);
    if (index == 0 && name != defaultSheet) excel.rename(defaultSheet, name);
    final sheet = excel[name];

    var isHeader = true;
    for (final row in data.rows) {
      sheet.appendRow([for (final c in row) _cell(c)]);
      if (isHeader) {
        for (var i = 0; i < row.length; i++) {
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
              .cellStyle = CellStyle(bold: true);
        }
        isHeader = false;
      }
    }
  }
  return excel.save();
}

/// Builds an `.xlsx` workbook from [rows] (first row = header) and prompts the
/// user for a save location (desktop) or downloads it (web). Returns the saved
/// path or downloaded file name, or null if cancelled.
Future<String?> saveExcelFile(
  String suggestedName,
  String sheetName,
  List<List<Object?>> rows,
) =>
    saveExcelWorkbook(suggestedName, [ExcelSheetData(sheetName, rows)]);

/// Like [saveExcelFile], with several sheets.
Future<String?> saveExcelWorkbook(
  String suggestedName,
  List<ExcelSheetData> sheets,
) async {
  final bytes = buildExcelBytes(sheets);
  if (bytes == null) return null;
  final data = Uint8List.fromList(bytes);

  final name = suggestedName.toLowerCase().endsWith('.xlsx')
      ? suggestedName
      : '$suggestedName.xlsx';

  return saveBytes(
    fileName: name,
    bytes: data,
    dialogTitle: 'Export to Excel',
    extension: 'xlsx',
    mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  );
}
