import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Desktop: asks for a save location, then makes sure the bytes are written.
Future<String?> saveBytes({
  required String fileName,
  required Uint8List bytes,
  required String dialogTitle,
  required String extension,
  required String mimeType,
}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: [extension],
    bytes: bytes,
  );
  if (path == null) return null;

  // Some desktop platforms return the chosen path without writing the bytes.
  final file = File(path);
  if (!await file.exists() || (await file.length()) == 0) {
    await file.writeAsBytes(bytes, flush: true);
  }
  return path;
}
