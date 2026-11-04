import 'dart:math' as math;

// Pure geo helpers (no Flutter imports) so they can be unit-tested directly.

/// Mean Earth radius (IUGG), metres.
const double earthRadiusM = 6371008.8;

double _rad(double deg) => deg * math.pi / 180;

/// Great-circle distance in metres between two lat/lng points.
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  final dLat = _rad(lat2 - lat1);
  final dLng = _rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadiusM * math.asin(math.min(1.0, math.sqrt(a)));
}

/// Null when [lat]/[lng] are valid WGS84 coordinates, otherwise an error
/// message suitable for a form field.
String? validateLatLng(double? lat, double? lng) {
  if (lat == null || lat.isNaN) return 'Latitude must be a number.';
  if (lng == null || lng.isNaN) return 'Longitude must be a number.';
  if (lat < -90 || lat > 90) return 'Latitude must be between -90 and 90.';
  if (lng < -180 || lng > 180) return 'Longitude must be between -180 and 180.';
  return null;
}

final _pairPattern = RegExp(
  r'^\s*\(?\s*([-+]?\d+(?:\.\d+)?)\s*[,;\s]\s*([-+]?\d+(?:\.\d+)?)\s*\)?\s*$',
);

/// Parses a pasted "lat, lng" string such as `7.06492, 125.59840`,
/// `7.06492 125.59840`, `7.06492;125.59840` or `(7.06492, 125.59840)`.
/// Returns null when the text isn't a pair or the values are out of range.
({double lat, double lng})? parseLatLngPair(String input) {
  final m = _pairPattern.firstMatch(input);
  if (m == null) return null;
  final lat = double.tryParse(m.group(1)!);
  final lng = double.tryParse(m.group(2)!);
  if (validateLatLng(lat, lng) != null) return null;
  return (lat: lat!, lng: lng!);
}

// --- edge length helpers (Outdoor AR editor) ---------------------------------

/// Allowed range for the "Max edge length" setting, metres.
const double minEdgeLimitM = 2;
const double maxEdgeLimitM = 100;

double _deg(double rad) => rad * 180 / math.pi;

/// Great-circle midpoint of two lat/lng points.
({double lat, double lng}) geoMidpoint(
    double lat1, double lng1, double lat2, double lng2) {
  final p1 = _rad(lat1);
  final p2 = _rad(lat2);
  final l1 = _rad(lng1);
  final dl = _rad(lng2 - lng1);
  final bx = math.cos(p2) * math.cos(dl);
  final by = math.cos(p2) * math.sin(dl);
  final lat = math.atan2(math.sin(p1) + math.sin(p2),
      math.sqrt(math.pow(math.cos(p1) + bx, 2) + by * by));
  final lng = l1 + math.atan2(by, math.cos(p1) + bx);
  return (lat: _deg(lat), lng: (_deg(lng) + 540) % 360 - 180);
}

/// Distance label: one decimal in metres ("12.4 m"), km past 1000 m
/// ("1.25 km").
String formatDistanceM(double meters) {
  if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(2)} km';
  return '${meters.toStringAsFixed(1)} m';
}

/// True when [lengthM] is over [limitM]. Compared at the 0.1 m precision
/// [formatDistanceM] shows, so an edge labelled "6.0 m" never counts as over
/// a 6 m limit.
bool exceedsEdgeLimit(double lengthM, double limitM) =>
    (lengthM * 10).round() > (limitM * 10).round();

/// Parses the "Max edge length (m)" field; null unless it is a number from
/// [minEdgeLimitM] to [maxEdgeLimitM].
double? parseEdgeLimit(String input) {
  final v = double.tryParse(input.trim());
  if (v == null || v.isNaN || v < minEdgeLimitM || v > maxEdgeLimitM) {
    return null;
  }
  return v;
}
