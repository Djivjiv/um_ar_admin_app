// Small helpers for safely parsing dynamic JSON values from Supabase.

List<String> parseStringList(dynamic value) {
  if (value == null) return <String>[];
  if (value is List) {
    return value.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList();
  }
  if (value is String && value.isNotEmpty) {
    // Postgres array literal fallback: {a,b,c}
    final trimmed = value.replaceAll(RegExp(r'^\{|\}$'), '');
    if (trimmed.isEmpty) return <String>[];
    return trimmed.split(',').map((e) => e.trim().replaceAll('"', '')).toList();
  }
  return <String>[];
}

DateTime? parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString())?.toLocal();
}

double? parseDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int? parseInt(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

bool parseBool(dynamic value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  final s = value.toString().toLowerCase();
  return s == 'true' || s == 't' || s == '1';
}
