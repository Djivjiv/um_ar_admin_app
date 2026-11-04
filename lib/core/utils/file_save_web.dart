import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

/// Web: there is no file system, so the browser downloads the bytes.
Future<String?> saveBytes({
  required String fileName,
  required Uint8List bytes,
  required String dialogTitle,
  required String extension,
  required String mimeType,
}) async {
  final blob = _Blob(<JSAny?>[bytes.toJS].toJS, _BlobOptions(type: mimeType));
  final url = _Url.createObjectURL(blob);
  final anchor = _document.createElement('a')
    ..href = url
    ..download = fileName;
  _document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  // Revoking straight after click() can cancel the download in some browsers.
  Timer(const Duration(seconds: 1), () => _Url.revokeObjectURL(url));
  return fileName;
}

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny?> parts, _BlobOptions options);
}

extension type _BlobOptions._(JSObject _) implements JSObject {
  external factory _BlobOptions({String type});
}

@JS('URL')
extension type _Url._(JSObject _) implements JSObject {
  external static String createObjectURL(_Blob blob);
  external static void revokeObjectURL(String url);
}

@JS('document')
external _Document get _document;

extension type _Document._(JSObject _) implements JSObject {
  external _Element createElement(String tag);
  external _Element? get body;
}

extension type _Element._(JSObject _) implements JSObject {
  external set href(String value);
  external set download(String value);
  external void appendChild(_Element child);
  external void click();
  external void remove();
}
