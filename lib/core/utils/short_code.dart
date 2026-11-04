/// The first 8 characters of [id], with "…" when it was longer.
String shortId(String id) => id.length > 8 ? '${id.substring(0, 8)}…' : id;

/// A `device_code` as the screens show it: its first 8 characters, so the
/// full install code stays out of view. '—' when there is none.
String shortDeviceCode(Object? deviceCode) {
  final code = deviceCode?.toString().trim() ?? '';
  return code.isEmpty ? '—' : shortId(code);
}
