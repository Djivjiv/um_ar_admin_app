import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

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

/// Builds an `.xlsx` workbook from [rows] (first row = header) and prompts the
/// user for a save location. Returns the saved path, or null if cancelled.
Future<String?> saveExcelFile(
  String suggestedName,
  String sheetName,
  List<List<Object?>> rows,
) async {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
  final safeSheet =
      (sheetName.length > 31 ? sheetName.substring(0, 31) : sheetName)
          .replaceAll(RegExp(r'[\[\]\*\?/\\:]'), ' ')
          .trim();
  final finalSheet = safeSheet.isEmpty ? 'Sheet1' : safeSheet;
  if (finalSheet != defaultSheet) {
    excel.rename(defaultSheet, finalSheet);
  }
  final sheet = excel[finalSheet];

  var isHeader = true;
  for (final row in rows) {
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

  final bytes = excel.save();
  if (bytes == null) return null;
  final data = Uint8List.fromList(bytes);

  final name = suggestedName.toLowerCase().endsWith('.xlsx')
      ? suggestedName
      : '$suggestedName.xlsx';

  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Export to Excel',
    fileName: name,
    type: FileType.custom,
    allowedExtensions: const ['xlsx'],
    bytes: data,
  );
  if (path == null) return null;

  // Some desktop platforms return the chosen path without writing the bytes.
  final file = File(path);
  if (!await file.exists() || (await file.length()) == 0) {
    await file.writeAsBytes(data, flush: true);
  }
  return path;
}
