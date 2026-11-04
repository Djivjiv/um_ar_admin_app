import 'parse_utils.dart';

/// Columns each metric needs. `navigation_sessions` isn't defined in this
/// repo; these come from the user app's supabase/navigation_evaluation.sql,
/// which may not have been run, so nothing here assumes they exist.
const kErrorRateColumns = [
  'trip_id',
  'row_type',
  'off_route_tracked',
  'error_count',
  'total_steps',
];
const kCompletionTimeColumns = [
  'trip_id',
  'row_type',
  'completed',
  'duration_seconds',
];
const kModeSplitColumns = ['trip_id', 'row_type', 'mode'];
const kOffRouteColumns = [
  'trip_id',
  'row_type',
  'off_route_tracked',
  'error_count',
  'reroute_count',
];
const kCompletionRateColumns = ['trip_id', 'row_type', 'completed'];
const kGpsArrivalColumns = [...kCompletionRateColumns, 'completed_manually'];

/// From `sus_responses`.
const kSusColumns = ['sus_score'];
const kSusByModeColumns = ['sus_score', 'navigation_session_id'];

/// Of [expected], the columns [rows] don't have. `select *` returns every
/// column, so this reads the real table. With no rows there is nothing to
/// read, so nothing is reported missing.
List<String> missingColumns(
  List<Map<String, dynamic>> rows,
  List<String> expected,
) {
  if (rows.isEmpty) return const [];
  return [
    for (final c in expected)
      if (!rows.any((r) => r.containsKey(c))) c,
  ];
}

/// True for a row written with no signed-in user. Reads `is_visitor` once the
/// user app's visitor_sessions.sql has added it, else `user_id`.
bool isVisitorRow(Map<String, dynamic> row) {
  final flag = row['is_visitor'];
  if (flag != null) return parseBool(flag);
  return (row['user_id']?.toString() ?? '').isEmpty;
}

/// Rows with no `trip_id`, written before trips existed. Never counted.
int rowsWithoutTripId(Iterable<Map<String, dynamic>> rows) =>
    rows.where((r) => (r['trip_id']?.toString() ?? '').isEmpty).length;

/// "AR", "2D" or "Unknown".
String modeLabel(String mode) => switch (mode) {
      'ar' => 'AR',
      '2d' => '2D',
      _ => 'Unknown',
    };

/// The evaluation figures for one group of trips. Values are null when there
/// is nothing to average, or a column they need is missing.
class GroupMetrics {
  final String label;
  final int trips;
  final int completedTrips;

  /// [completedTrips] / [trips], 0 to 1.
  final double? completionRate;

  /// Completed and not completed_manually.
  final int? gpsArrivals;

  /// Completed by the person saying they had arrived.
  final int? manualArrivals;

  /// [gpsArrivals] / [trips], 0 to 1.
  final double? gpsArrivalRate;

  /// Mean of error_count / total_steps per trip.
  final double? errorRate;

  /// Sum of error_count - reroute_count over tracked trips.
  final int? offRouteEvents;

  /// Sum of reroute_count over the same trips.
  final int? reroutes;

  /// Mean duration of completed trips, in seconds.
  final double? averageSeconds;
  final double? averageSus;

  const GroupMetrics({
    required this.label,
    this.trips = 0,
    this.completedTrips = 0,
    this.completionRate,
    this.gpsArrivals,
    this.manualArrivals,
    this.gpsArrivalRate,
    this.errorRate,
    this.offRouteEvents,
    this.reroutes,
    this.averageSeconds,
    this.averageSus,
  });
}

/// One row of the AR vs 2D table.
class ModeMetrics extends GroupMetrics {
  /// `ar`, `2d`, or `unknown` when a trip has no mode.
  final String mode;

  /// Share of all trips, 0 to 1.
  final double share;

  ModeMetrics({
    required this.mode,
    required this.share,
    required GroupMetrics group,
  }) : super(
          label: modeLabel(mode),
          trips: group.trips,
          completedTrips: group.completedTrips,
          completionRate: group.completionRate,
          gpsArrivals: group.gpsArrivals,
          manualArrivals: group.manualArrivals,
          gpsArrivalRate: group.gpsArrivalRate,
          errorRate: group.errorRate,
          offRouteEvents: group.offRouteEvents,
          reroutes: group.reroutes,
          averageSeconds: group.averageSeconds,
          averageSus: group.averageSus,
        );
}

/// Visitors against verified users. Visitor = no user_id. Verified = signed
/// in with is_verified true. Signed-in accounts that aren't verified are in
/// neither group.
class UserComparison {
  final GroupMetrics visitors;
  final GroupMetrics verified;

  /// Trips by signed-in accounts that aren't verified, left out of both.
  final int otherSignedInTrips;

  const UserComparison({
    this.visitors = const GroupMetrics(label: 'Visitors'),
    this.verified = const GroupMetrics(label: 'Verified users'),
    this.otherSignedInTrips = 0,
  });
}

/// The navigation evaluation numbers. A null value means "No data yet".
class NavigationMetrics {
  final int trips;

  /// Mean of error_count / total_steps per trip, 0 or more (not capped at 1).
  /// error_count is off-route events plus reroutes.
  final double? errorRate;

  /// Trips behind [errorRate].
  final int errorRateTrips;

  /// Sum of error_count - reroute_count over tracked trips.
  final int? offRouteEvents;

  /// Sum of reroute_count over the same trips.
  final int? reroutes;

  /// Trips behind [offRouteEvents] and [reroutes].
  final int offRouteTrips;

  /// All completed trips, GPS-confirmed or not.
  final int completedTrips;

  /// [completedTrips] / [trips], 0 to 1.
  final double? completionRate;

  /// Completed and not completed_manually.
  final int? gpsArrivals;

  /// Completed by the person saying they had arrived.
  final int? manualArrivals;

  /// [gpsArrivals] / [trips], 0 to 1.
  final double? gpsArrivalRate;

  /// Mean duration of completed trips, in seconds.
  final double? averageCompletionSeconds;

  /// Trips behind [averageCompletionSeconds].
  final int timedTrips;
  final double? averageSus;
  final int susResponses;
  final List<ModeMetrics> modes;
  final UserComparison comparison;

  /// The columns found missing for each metric.
  final List<String> missingForErrorRate;
  final List<String> missingForOffRoute;
  final List<String> missingForCompletionRate;
  final List<String> missingForGpsArrivals;
  final List<String> missingForCompletionTime;
  final List<String> missingForModeSplit;
  final List<String> missingForSus;
  final List<String> missingForSusByMode;

  /// False when the `sus_responses` table doesn't exist.
  final bool susTableAvailable;

  /// The one-response-per-person note, if there is anything to say.
  final String? susNote;

  const NavigationMetrics({
    this.trips = 0,
    this.errorRate,
    this.errorRateTrips = 0,
    this.offRouteEvents,
    this.reroutes,
    this.offRouteTrips = 0,
    this.completedTrips = 0,
    this.completionRate,
    this.gpsArrivals,
    this.manualArrivals,
    this.gpsArrivalRate,
    this.averageCompletionSeconds,
    this.timedTrips = 0,
    this.averageSus,
    this.susResponses = 0,
    this.modes = const [],
    this.comparison = const UserComparison(),
    this.missingForErrorRate = const [],
    this.missingForOffRoute = const [],
    this.missingForCompletionRate = const [],
    this.missingForGpsArrivals = const [],
    this.missingForCompletionTime = const [],
    this.missingForModeSplit = const [],
    this.missingForSus = const [],
    this.missingForSusByMode = const [],
    this.susTableAvailable = true,
    this.susNote,
  });

  /// Every trip as one group, for the export's first summary row.
  GroupMetrics get overall => GroupMetrics(
        label: 'All trips',
        trips: trips,
        completedTrips: completedTrips,
        completionRate: completionRate,
        gpsArrivals: gpsArrivals,
        manualArrivals: manualArrivals,
        gpsArrivalRate: gpsArrivalRate,
        errorRate: errorRate,
        offRouteEvents: offRouteEvents,
        reroutes: reroutes,
        averageSeconds: averageCompletionSeconds,
        averageSus: averageSus,
      );
}

/// One trip: the `start` row and, once it ended, its `end` row.
class NavigationTrip {
  final Map<String, dynamic> start;
  Map<String, dynamic>? end;
  NavigationTrip(this.start);

  DateTime? get startedAt => parseDate(start['started_at']);

  String get fromName => start['from_name']?.toString().trim() ?? '';

  String get toName => start['to_name']?.toString().trim() ?? '';

  bool get isVisitor => isVisitorRow(start);

  /// Null for a visitor.
  String? get userId {
    final id = start['user_id']?.toString() ?? '';
    return id.isEmpty ? null : id;
  }

  /// The route length, or null when none was recorded. The user app writes 0
  /// when it has no distance, so 0 means unknown, not a trip of no length.
  double? get distanceMeters {
    for (final row in [start, ?end]) {
      final meters = parseDouble(row['distance_meters']);
      if (meters != null && meters > 0) return meters;
    }
    return null;
  }

  String get mode {
    final m = start['mode']?.toString().trim().toLowerCase() ?? '';
    return m.isEmpty ? 'unknown' : m;
  }

  bool get completed => end != null && parseBool(end!['completed']);

  /// Completed by the person saying they had arrived, not by GPS.
  bool get completedManually =>
      completed && parseBool(end!['completed_manually']);

  bool get gpsArrival => completed && !completedManually;

  /// "Completed", "Completed (manual)", "Left early" or "Not finished".
  String get outcome {
    if (end == null) return 'Not finished';
    if (!completed) return 'Left early';
    return completedManually ? 'Completed (manual)' : 'Completed';
  }

  /// Seconds, for completed trips that recorded a duration.
  double? get seconds {
    final d = completed ? parseDouble(end!['duration_seconds']) : null;
    return d;
  }

  /// error_count / total_steps. Only meaningful when the app tracked
  /// off-route events on this trip, so anything else is null.
  double? get errorRate {
    final e = end;
    if (e == null || !parseBool(e['off_route_tracked'])) return null;
    final steps = parseInt(e['total_steps']) ?? parseInt(start['total_steps']);
    final errors = parseInt(e['error_count']);
    if (steps == null || steps <= 0 || errors == null) return null;
    return errors / steps;
  }

  /// reroute_count, on trips where the app tracked off-route events.
  int? get reroutes {
    final e = end;
    if (e == null || !parseBool(e['off_route_tracked'])) return null;
    return parseInt(e['reroute_count']);
  }

  /// error_count, on trips where the app tracked off-route events.
  int? get errorCount {
    final e = end;
    if (e == null || !parseBool(e['off_route_tracked'])) return null;
    return parseInt(e['error_count']);
  }

  /// error_count - reroute_count. Never below 0: rows logged before reroutes
  /// were added to error_count can hold more reroutes than errors.
  int? get offRouteEvents {
    final errors = errorCount;
    final rerouted = reroutes;
    if (errors == null || rerouted == null) return null;
    return errors < rerouted ? 0 : errors - rerouted;
  }
}

double? _mean(Iterable<double> values) {
  if (values.isEmpty) return null;
  return values.reduce((a, b) => a + b) / values.length;
}

/// Groups `navigation_sessions` rows into trips, as the user app's
/// `navigation_trip_metrics` view does: one trip is the rows sharing a
/// `trip_id`, a `start` row plus, once it ends, an `end` row (the newest wins
/// if there are several). Without this, a finished trip would count twice.
/// Rows with no `trip_id`, written before trips existed, are left out.
List<NavigationTrip> groupNavigationTrips(List<Map<String, dynamic>> rows) {
  final trips = <String, NavigationTrip>{};
  for (final r in rows) {
    final id = r['trip_id']?.toString() ?? '';
    if (id.isNotEmpty && r['row_type'] == 'start') {
      trips.putIfAbsent(id, () => NavigationTrip(r));
    }
  }
  for (final r in rows) {
    if (r['row_type'] != 'end') continue;
    final trip = trips[r['trip_id']?.toString()];
    if (trip == null) continue;
    final previous = trip.end;
    if (previous == null ||
        (parseInt(r['id']) ?? 0) >= (parseInt(previous['id']) ?? 0)) {
      trip.end = r;
    }
  }
  return trips.values.toList();
}

/// Computes the metrics from raw [sessions] and [susResponses] rows. Raw
/// maps, not models, so a missing column can be told from an empty value.
/// [susResponses] should already hold one response per person.
/// [verifiedUserIds] are the accounts with `is_verified` true.
NavigationMetrics computeNavigationMetrics(
  List<Map<String, dynamic>> sessions,
  List<Map<String, dynamic>> susResponses, {
  bool susTableAvailable = true,
  String? susNote,
  Set<String> verifiedUserIds = const {},
}) {
  final missingError = missingColumns(sessions, kErrorRateColumns);
  final missingOffRoute = missingColumns(sessions, kOffRouteColumns);
  final missingCompletion = missingColumns(sessions, kCompletionRateColumns);
  final missingGps = missingColumns(sessions, kGpsArrivalColumns);
  final missingTime = missingColumns(sessions, kCompletionTimeColumns);
  final missingSplit = missingColumns(sessions, kModeSplitColumns);
  final missingSus = missingColumns(susResponses, kSusColumns);
  final missingSusByMode = missingColumns(susResponses, kSusByModeColumns);

  final trips = groupNavigationTrips(sessions);
  final tripIds = <String, NavigationTrip>{
    for (final t in trips) t.start['trip_id'].toString(): t,
  };

  final errorRates = [
    if (missingError.isEmpty)
      for (final t in trips) ?t.errorRate,
  ];
  final seconds = [
    if (missingTime.isEmpty)
      for (final t in trips) ?t.seconds,
  ];
  final susScores = [
    for (final r in susResponses) ?parseDouble(r['sus_score']),
  ];

  int sum(Iterable<int> values) => values.fold(0, (a, b) => a + b);

  GroupMetrics groupOf(
    String label,
    List<NavigationTrip> group,
    Iterable<double> sus,
  ) {
    final tracked = [
      if (missingOffRoute.isEmpty)
        for (final t in group)
          if (t.offRouteEvents != null) t,
    ];
    final completed = group.where((t) => t.completed).length;
    final gps = group.where((t) => t.gpsArrival).length;
    final hasRate = group.isNotEmpty && missingCompletion.isEmpty;
    final hasGps = group.isNotEmpty && missingGps.isEmpty;
    return GroupMetrics(
      label: label,
      trips: group.length,
      completedTrips: completed,
      completionRate: hasRate ? completed / group.length : null,
      gpsArrivals: hasGps ? gps : null,
      manualArrivals: hasGps ? completed - gps : null,
      gpsArrivalRate: hasGps ? gps / group.length : null,
      errorRate: missingError.isEmpty
          ? _mean([for (final t in group) ?t.errorRate])
          : null,
      offRouteEvents:
          tracked.isEmpty ? null : sum(tracked.map((t) => t.offRouteEvents!)),
      reroutes: tracked.isEmpty ? null : sum(tracked.map((t) => t.reroutes!)),
      averageSeconds: missingTime.isEmpty
          ? _mean([for (final t in group) ?t.seconds])
          : null,
      averageSus: _mean(sus),
    );
  }

  final all = groupOf('All trips', trips, susScores);
  final offRouteTrips = [
    if (missingOffRoute.isEmpty)
      for (final t in trips)
        if (t.offRouteEvents != null) t,
  ].length;

  bool isVerified(String? user) =>
      user != null && verifiedUserIds.contains(user);
  List<double> scoresWhere(bool Function(Map<String, dynamic>) keep) => [
        for (final r in susResponses)
          if (keep(r)) ?parseDouble(r['sus_score']),
      ];
  final visitorTrips = trips.where((t) => t.isVisitor).toList();
  final verifiedTrips =
      trips.where((t) => !t.isVisitor && isVerified(t.userId)).toList();

  final susByMode = <String, List<double>>{};
  if (missingSusByMode.isEmpty && missingSplit.isEmpty) {
    for (final r in susResponses) {
      final score = parseDouble(r['sus_score']);
      final trip = tripIds[r['navigation_session_id']?.toString()];
      if (score != null && trip != null) {
        (susByMode[trip.mode] ??= []).add(score);
      }
    }
  }

  ModeMetrics forMode(String mode, List<NavigationTrip> group) => ModeMetrics(
        mode: mode,
        share: group.length / trips.length,
        group: groupOf(mode, group, susByMode[mode] ?? const []),
      );

  final byMode = <String, List<NavigationTrip>>{};
  if (missingSplit.isEmpty) {
    for (final t in trips) {
      (byMode[t.mode] ??= []).add(t);
    }
  }
  const order = {'ar': 0, '2d': 1};
  final modeKeys = byMode.keys.toList()
    ..sort((a, b) => (order[a] ?? 2).compareTo(order[b] ?? 2));

  return NavigationMetrics(
    trips: trips.length,
    errorRate: all.errorRate,
    errorRateTrips: errorRates.length,
    offRouteEvents: all.offRouteEvents,
    reroutes: all.reroutes,
    offRouteTrips: offRouteTrips,
    completedTrips: all.completedTrips,
    completionRate: all.completionRate,
    gpsArrivals: all.gpsArrivals,
    manualArrivals: all.manualArrivals,
    gpsArrivalRate: all.gpsArrivalRate,
    averageCompletionSeconds: all.averageSeconds,
    timedTrips: seconds.length,
    averageSus: all.averageSus,
    susResponses: susScores.length,
    modes: [for (final m in modeKeys) forMode(m, byMode[m]!)],
    comparison: UserComparison(
      visitors: groupOf('Visitors', visitorTrips, scoresWhere(isVisitorRow)),
      verified: groupOf(
        'Verified users',
        verifiedTrips,
        scoresWhere(
            (r) => !isVisitorRow(r) && isVerified(r['user_id']?.toString())),
      ),
      otherSignedInTrips:
          trips.length - visitorTrips.length - verifiedTrips.length,
    ),
    missingForErrorRate: missingError,
    missingForOffRoute: missingOffRoute,
    missingForCompletionRate: missingCompletion,
    missingForGpsArrivals: missingGps,
    missingForCompletionTime: missingTime,
    missingForModeSplit: missingSplit,
    missingForSus: missingSus,
    missingForSusByMode: missingSusByMode,
    susTableAvailable: susTableAvailable,
    susNote: susNote,
  );
}

/// "45s", "3m 05s" or "1h 02m".
String formatTripSeconds(double seconds) {
  final total = seconds.round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
  if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
  return '${s}s';
}

/// "12.5%".
String formatPercent(double rate) => '${(rate * 100).toStringAsFixed(1)}%';
