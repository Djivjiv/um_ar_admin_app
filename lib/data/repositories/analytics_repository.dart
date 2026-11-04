import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../core/utils/date_range.dart';
import '../../core/utils/excel_export.dart';
import '../../core/utils/navigation_metrics.dart';
import '../../core/utils/parse_utils.dart';
import '../../core/utils/sus_dedupe.dart';
import '../../core/utils/trip_export.dart';
import 'account_counts.dart';
import 'paged_query.dart';
import 'repository_exception.dart';

/// A single (label, value) pair used by charts.
class ChartPoint {
  final String label;
  final double value;
  const ChartPoint(this.label, this.value);
}

/// The Analytics cards, counted per trip with the same grouping as
/// [computeNavigationMetrics], so the two agree on screen.
class TripSummary {
  final int trips;
  final int completedTrips;

  /// Percent of trips completed; null with no trips.
  final double? completionRate;

  /// Mean length in meters of trips that have one: a distance of 0 or null
  /// means unknown, so those trips are left out. Null when none has.
  final double? averageDistance;
  final List<ChartPoint> perDay;
  final List<ChartPoint> mostVisited;

  /// 24 values, index = hour of day.
  final List<ChartPoint> peakHours;

  /// Rows with no `trip_id`, written before trips existed. Not counted.
  final int rowsWithoutTrip;

  const TripSummary({
    this.trips = 0,
    this.completedTrips = 0,
    this.completionRate,
    this.averageDistance,
    this.perDay = const [],
    this.mostVisited = const [],
    this.peakHours = const [],
    this.rowsWithoutTrip = 0,
  });
}

/// Summarises raw `navigation_sessions` rows, one count per trip.
TripSummary summarizeTrips(
  List<Map<String, dynamic>> rows, {
  int mostVisitedLimit = 8,
}) {
  final trips = groupNavigationTrips(rows);
  final days = <String, int>{};
  final places = <String, int>{};
  final hours = List<int>.filled(24, 0);
  for (final t in trips) {
    final d = t.startedAt;
    if (d != null) {
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      days[key] = (days[key] ?? 0) + 1;
      hours[d.hour]++;
    }
    if (t.toName.isNotEmpty) places[t.toName] = (places[t.toName] ?? 0) + 1;
  }

  final completed = trips.where((t) => t.completed).length;
  final distances = [for (final t in trips) ?t.distanceMeters];
  final dayKeys = days.keys.toList()..sort();
  final ranked = places.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return TripSummary(
    trips: trips.length,
    completedTrips: completed,
    completionRate: trips.isEmpty ? null : completed / trips.length * 100,
    averageDistance: distances.isEmpty
        ? null
        : distances.reduce((a, b) => a + b) / distances.length,
    perDay: [for (final k in dayKeys) ChartPoint(k, days[k]!.toDouble())],
    mostVisited: [
      for (final e in ranked.take(mostVisitedLimit))
        ChartPoint(e.key, e.value.toDouble()),
    ],
    peakHours: [
      for (var h = 0; h < 24; h++)
        ChartPoint(h.toString().padLeft(2, '0'), hours[h].toDouble()),
    ],
    rowsWithoutTrip: rowsWithoutTripId(rows),
  );
}

/// The label for an account with no role.
const kNoRoleLabel = 'No role yet';

/// The User Distribution chart: people, one per `user_id` or `device_code`.
class UserDistribution {
  final List<ChartPoint> points;

  /// Rows with neither id, so they can't be matched to a person.
  final int rowsWithoutPerson;

  const UserDistribution({
    this.points = const [],
    this.rowsWithoutPerson = 0,
  });
}

/// Counts the people behind [usageRows] by role. Signed-in people take their
/// role from [roleByUser]; people known only by `device_code` are visitors,
/// and share that slice with any account whose role is `visitor`.
UserDistribution summarizePeople(
  Iterable<Map<String, dynamic>> usageRows,
  Map<String, String?> roleByUser,
) {
  final seen = <String>{};
  final counts = <String, int>{};
  var withoutPerson = 0;
  for (final row in usageRows) {
    final person = personKey(row);
    if (person == null) {
      withoutPerson++;
      continue;
    }
    if (!seen.add(person)) continue;
    final String label;
    if (person.startsWith('device:')) {
      label = 'visitor';
    } else {
      final role = roleByUser[person.substring('user:'.length)]?.trim() ?? '';
      label = role.isEmpty ? kNoRoleLabel : role.toLowerCase();
    }
    counts[label] = (counts[label] ?? 0) + 1;
  }
  return UserDistribution(
    points: [
      for (final e in counts.entries) ChartPoint(e.key, e.value.toDouble()),
    ],
    rowsWithoutPerson: withoutPerson,
  );
}

class AnalyticsRepository {
  final _client = SupabaseConfig.client;
  static const _navTable = 'navigation_sessions';
  static const _susTable = 'sus_responses';
  static const _profilesTable = 'user_profiles';
  static const _visitorTable = 'visitor_sessions';

  /// Raw rows with `from <= started_at < to`, `select *`: that returns
  /// whatever columns the table has, so a column the app expects but the
  /// table lacks can't fail the request.
  Future<List<Map<String, dynamic>>> _sessionRows({
    DateTime? from,
    DateTime? to,
  }) {
    return fetchAllPages((a, b) {
      var query = _client.from(_navTable).select();
      if (from != null) {
        query = query.gte('started_at', from.toUtc().toIso8601String());
      }
      if (to != null) {
        query = query.lt('started_at', to.toUtc().toIso8601String());
      }
      return query.order('started_at').order('id').range(a, b);
    });
  }

  bool _inRange(DateTime? at, DateTime? from, DateTime? to) {
    if (from == null && to == null) return true;
    if (at == null) return false;
    return withinSpan(
      at,
      from ?? DateTime.fromMillisecondsSinceEpoch(0),
      to ?? DateTime(9999),
    );
  }

  /// Every SUS response, not just a date range: a person's first response may
  /// be outside it, and only the first one counts. Null when the table
  /// doesn't exist.
  Future<SusDedupeResult?> _dedupedSus() async {
    try {
      return dedupeSusRows(await fetchAllPages((a, b) => _client
          .from(_susTable)
          .select()
          .order('submitted_at')
          .order('id')
          .range(a, b)));
    } on PostgrestException catch (e) {
      if (!isMissingTable(e)) rethrow;
      return null;
    }
  }

  /// The accounts with `is_verified` true.
  Future<Set<String>> _verifiedUserIds() async {
    final rows = await fetchAllPages((a, b) => _client
        .from(_profilesTable)
        .select('id, is_verified')
        .order('id')
        .range(a, b));
    return {
      for (final r in rows)
        if (parseBool(r['is_verified'])) r['id'].toString(),
    };
  }

  /// Error rate, completion time, SUS, the AR vs 2D split and visitors vs
  /// verified users. A table that only lacks columns gives "No data yet" per
  /// metric; a failed request is an error, so it can't pass for an empty
  /// range.
  Future<NavigationMetrics> getNavigationMetrics({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final sessions = await _sessionRows(from: from, to: to);
      final dedupe = await _dedupedSus();
      return computeNavigationMetrics(
        sessions,
        [
          for (final r in dedupe?.kept ?? const <Map<String, dynamic>>[])
            if (_inRange(parseDate(r['submitted_at']), from, to)) r,
        ],
        susTableAvailable: dedupe != null,
        susNote: dedupe == null ? null : susDedupeNote(dedupe),
        verifiedUserIds: await _verifiedUserIds(),
      );
    } catch (e) {
      throw RepositoryException(
          'Failed to load navigation metrics: ${describeError(e)}', e);
    }
  }

  /// The trip-based cards for `from <= started_at < to`.
  Future<TripSummary> getTripSummary({DateTime? from, DateTime? to}) async {
    try {
      return summarizeTrips(await _sessionRows(from: from, to: to));
    } catch (e) {
      throw RepositoryException(
          'Failed to load trips: ${describeError(e)}', e);
    }
  }

  /// Rows of [table] with `from <= dateColumn < to`, or none when the table
  /// doesn't exist yet.
  Future<List<Map<String, dynamic>>> _usageRows(
    String table,
    String dateColumn, {
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      return await fetchAllPages((a, b) {
        var query = _client.from(table).select();
        if (from != null) {
          query = query.gte(dateColumn, from.toUtc().toIso8601String());
        }
        if (to != null) {
          query = query.lt(dateColumn, to.toUtc().toIso8601String());
        }
        return query.order('id').range(a, b);
      });
    } catch (e) {
      if (isMissingTable(e)) return const [];
      rethrow;
    }
  }

  /// The people who navigated, answered the SUS or started a visitor session
  /// in `from <= t < to`, by role.
  Future<UserDistribution> getUserDistribution({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final profiles = await fetchAllPages((a, b) => _client
          .from(_profilesTable)
          .select('id, role')
          .order('id')
          .range(a, b));
      final visitors =
          await _usageRows(_visitorTable, 'started_at', from: from, to: to);
      return summarizePeople(
        [
          ...await _sessionRows(from: from, to: to),
          ...await _usageRows(_susTable, 'submitted_at', from: from, to: to),
          // Rows from before device_code existed only have device_id.
          for (final v in visitors)
            {...v, 'device_code': v['device_code'] ?? v['device_id']},
        ],
        {for (final p in profiles) p['id'].toString(): p['role']?.toString()},
      );
    } catch (e) {
      throw RepositoryException(
          'Failed to load user distribution: ${describeError(e)}', e);
    }
  }

  Future<int> getTripsTodayCount() async {
    try {
      final now = DateTime.now();
      final today = wholeDays(now, now);
      final rows = await _sessionRows(from: today.from, to: today.to);
      return groupNavigationTrips(rows).length;
    } catch (e) {
      throw RepositoryException('Failed to count today\'s trips', e);
    }
  }

  /// Active accounts, by the same rule as the Dashboard.
  Future<int> getTotalUsersCount() async {
    try {
      return await countActiveAccounts(_client);
    } catch (e) {
      throw RepositoryException('Failed to count users', e);
    }
  }

  /// The Analytics workbook for `from <= started_at < to`: one row per trip,
  /// then the summary figures. [rangeLabel] is printed on the summary.
  Future<List<ExcelSheetData>> exportTripWorkbook({
    DateTime? from,
    DateTime? to,
    required String rangeLabel,
  }) async {
    try {
      final sessions = await _sessionRows(from: from, to: to);
      final dedupe = await _dedupedSus();
      final metrics = await getNavigationMetrics(from: from, to: to);
      return [
        ExcelSheetData(
          'Trips',
          tripExportRows(sessions, dedupe?.kept ?? const []),
        ),
        ExcelSheetData(
          'Summary',
          summaryExportRows(metrics, range: rangeLabel),
        ),
      ];
    } catch (e) {
      if (e is RepositoryException) rethrow;
      throw RepositoryException(
          'Failed to export trips: ${describeError(e)}', e);
    }
  }
}
