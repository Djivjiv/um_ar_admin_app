import 'package:intl/intl.dart';

import '../../domain/models/feedback_comment_model.dart';
import 'navigation_metrics.dart';
import 'parse_utils.dart';

/// The short id for a raw `device_code`, or '' with none. The raw code never
/// goes in an export.
String anonymousDeviceId(Object? deviceCode) {
  final code = deviceCode?.toString().trim() ?? '';
  return code.isEmpty ? '' : anonymousId(code);
}

/// The Trips sheet, first row = header: one row per trip. Older rows with no
/// `trip_id` are left out, as everywhere else. [susResponses] should already
/// hold one response per person. The error columns stay empty on trips where
/// off-route events weren't tracked: a 0 there would read as a clean trip.
List<List<Object?>> tripExportRows(
  List<Map<String, dynamic>> sessions,
  List<Map<String, dynamic>> susResponses,
) {
  final susByTrip = <String, double>{};
  for (final r in susResponses) {
    final trip = r['navigation_session_id']?.toString() ?? '';
    final score = parseDouble(r['sus_score']);
    if (trip.isNotEmpty && score != null) susByTrip.putIfAbsent(trip, () => score);
  }
  final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  return [
    [
      'trip_id',
      'date',
      'mode',
      'user_type',
      'anonymous_device_id',
      'completed',
      'completed_manually',
      'duration_seconds',
      'distance_meters',
      'error_count',
      'reroute_count',
      'off_route_events',
      'total_steps',
      'sus_score',
    ],
    for (final t in groupNavigationTrips(sessions))
      [
        t.start['trip_id'],
        t.startedAt == null ? '' : dateFormat.format(t.startedAt!),
        modeLabel(t.mode),
        t.isVisitor ? 'visitor' : 'signed-in',
        anonymousDeviceId(t.start['device_code'] ?? t.end?['device_code']),
        t.completed,
        t.completedManually,
        parseInt(t.end?['duration_seconds']),
        t.distanceMeters,
        t.errorCount,
        t.reroutes,
        t.offRouteEvents,
        parseInt(t.end?['total_steps']) ?? parseInt(t.start['total_steps']),
        susByTrip[t.start['trip_id']?.toString()],
      ],
  ];
}

double? _percent(double? rate) =>
    rate == null ? null : double.parse((rate * 100).toStringAsFixed(1));

double? _oneDecimal(double? value) =>
    value == null ? null : double.parse(value.toStringAsFixed(1));

/// The Summary sheet, first row = header: every trip, each mode, then
/// visitors and verified users, followed by notes on how to read them.
List<List<Object?>> summaryExportRows(
  NavigationMetrics metrics, {
  required String range,
}) {
  final other = metrics.comparison.otherSignedInTrips;
  return [
    [
      'Group',
      'Trips',
      'Completed',
      'Completion rate (%)',
      'GPS-only arrivals',
      'GPS-only rate (%)',
      'Manual arrivals',
      'Errors per step (%)',
      'Off-route events',
      'Reroutes',
      'Average time (s)',
      'Average SUS',
    ],
    for (final g in [
      metrics.overall,
      ...metrics.modes,
      metrics.comparison.visitors,
      metrics.comparison.verified,
    ])
      [
        g.label,
        g.trips,
        g.completedTrips,
        _percent(g.completionRate),
        g.gpsArrivals,
        _percent(g.gpsArrivalRate),
        g.manualArrivals,
        _percent(g.errorRate),
        g.offRouteEvents,
        g.reroutes,
        _oneDecimal(g.averageSeconds),
        _oneDecimal(g.averageSus),
      ],
    // One empty cell: the Excel package drops a row with none.
    const [''],
    ['Range: $range'],
    const ['Visitor = no user_id. Verified = signed in with is_verified true.'],
    ['Trips by signed-in accounts that are not verified, in neither group: '
        '$other'],
    const ['Errors per step counts off-route events plus reroutes.'],
    const ['Average SUS by mode uses answers linked to a trip of that mode.'],
  ];
}
