import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/maptiler_config.dart';
import '../../core/config/supabase_config.dart';
import '../../core/utils/date_range.dart';
import '../../core/utils/navigation_metrics.dart';
import '../../core/utils/parse_utils.dart';
import '../../core/utils/short_code.dart';
import '../../core/utils/sus_dedupe.dart';
import '../../domain/models/feedback_comment_model.dart';
import 'account_counts.dart';
import 'feedback_repository.dart';
import 'paged_query.dart';
import 'repository_exception.dart';

// ---------------------------------------------------------------------------
// Result models
// ---------------------------------------------------------------------------

class DashboardTopStats {
  final int students;
  final int registeredAccounts;
  final int activeVisitors;
  final int activeUsers;

  /// Kiosk sessions started in the selected range (`getTopStats`'s
  /// `rangeDays`), not all time.
  final int kioskUsers;

  const DashboardTopStats({
    this.students = 0,
    this.registeredAccounts = 0,
    this.activeVisitors = 0,
    this.activeUsers = 0,
    this.kioskUsers = 0,
  });
}

class DailySeries {
  final List<DateTime> days;
  final List<int> registered; // trips by a signed-in user
  final List<int> visitor; // trips by a visitor
  final List<int> kiosk; // kiosk_sessions, a different unit: chart it apart

  const DailySeries({
    this.days = const [],
    this.registered = const [],
    this.visitor = const [],
    this.kiosk = const [],
  });

  bool get isEmpty => days.isEmpty;
}

class SusSummary {
  /// SUS responses, from the user app.
  final int totalResponses;

  /// Rows of `kiosk_survey_responses`. These are 1 to 5 ratings with no SUS
  /// score, so they are counted apart and never go into the SUS figures.
  final int kioskSurveys;
  final double averageScore;
  final int poor; // 0-50
  final int marginal; // 51-68
  final int good; // 69-80
  final int excellent; // 81-100

  /// The one-response-per-person note, if there is anything to say.
  final String? note;

  const SusSummary({
    this.totalResponses = 0,
    this.kioskSurveys = 0,
    this.averageScore = 0,
    this.poor = 0,
    this.marginal = 0,
    this.good = 0,
    this.excellent = 0,
    this.note,
  });

  String get grade {
    if (averageScore > 80) return 'Excellent';
    if (averageScore >= 69) return 'Good';
    if (averageScore >= 51) return 'Marginal';
    return 'Poor';
  }
}

/// One comment for the Dashboard panel. Holds only what may be shown, as on
/// the Suggestions screen: no name, email, user id or device code.
class CommentEntry {
  final String text;
  final String userType; // "Student", "Visitor", "Kiosk"

  /// The short anonymous id. For a kiosk comment, which has no person, the
  /// first 8 characters of the kiosk's device_code, or null without one.
  final String? anonymousRef;
  final DateTime? at;

  const CommentEntry({
    required this.text,
    required this.userType,
    this.anonymousRef,
    this.at,
  });
}

class BuildingVisit {
  final String name;
  final int count;
  const BuildingVisit(this.name, this.count);
}

class SystemStatus {
  final bool supabaseOk;
  final bool mapTilerOk;

  /// Null when that count could not be loaded (see [errors]).
  final int? totalBuildings;
  final int? totalOutdoorNodes;
  final int? totalIndoorNodes;
  final int? totalFloorPlans;
  final DateTime? lastDataUpdate;

  /// One "Could not load …" line per count that failed.
  final List<String> errors;

  const SystemStatus({
    this.supabaseOk = false,
    this.mapTilerOk = false,
    this.totalBuildings,
    this.totalOutdoorNodes,
    this.totalIndoorNodes,
    this.totalFloorPlans,
    this.lastDataUpdate,
    this.errors = const [],
  });
}

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Local midnight at the start of the last [days] days, today included.
DateTime dashboardRangeStart(int days, [DateTime? now]) =>
    _dateOnly(now ?? DateTime.now()).subtract(Duration(days: days - 1));

DateTime? _anyDate(Map<String, dynamic> row, List<String> keys) {
  for (final k in keys) {
    if (row[k] != null) {
      final parsed = parseDate(row[k]);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

dynamic _anyValue(Map<String, dynamic> row, List<String> keys) {
  for (final k in keys) {
    if (row[k] != null) return row[k];
  }
  return null;
}

class DashboardRepository {
  DashboardRepository({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final _client = SupabaseConfig.client;
  final http.Client _http;
  final _feedback = FeedbackRepository();

  static const _kioskSurveyTable = 'kiosk_survey_responses';

  /// Every row of [table], paged and ordered by `id`, optionally limited to
  /// rows where `dateColumn >= from`.
  Future<List<Map<String, dynamic>>> _selectAll(
    String table,
    String columns, {
    String? dateColumn,
    DateTime? from,
  }) {
    return fetchAllPages((a, b) {
      var query = _client.from(table).select(columns);
      if (dateColumn != null && from != null) {
        query = query.gte(dateColumn, from.toUtc().toIso8601String());
      }
      return query.order('id').range(a, b);
    });
  }

  /// Rows of the kiosk survey with `from <= created_at < to`, or an empty list
  /// when the table hasn't been created yet. Any other error is rethrown.
  Future<List<Map<String, dynamic>>> _kioskSurveyRows(
    DateTime from,
    DateTime to,
  ) async {
    try {
      return await fetchAllPages((a, b) => _client
          .from(_kioskSurveyTable)
          .select()
          .gte('created_at', from.toUtc().toIso8601String())
          .lt('created_at', to.toUtc().toIso8601String())
          .order('id')
          .range(a, b));
    } catch (e) {
      if (isMissingTable(e)) return <Map<String, dynamic>>[];
      rethrow;
    }
  }

  /// Exact row count of [table] after [filter]; no rows are downloaded.
  Future<int> _count(
    String table, [
    PostgrestFilterBuilder<int> Function(PostgrestFilterBuilder<int> q)?
        filter,
  ]) async {
    final query = _client.from(table).count();
    return await (filter == null ? query : filter(query));
  }

  /// Like [_count], but 0 when the optional table doesn't exist yet.
  Future<int> _countOptional(
    String table, [
    PostgrestFilterBuilder<int> Function(PostgrestFilterBuilder<int> q)?
        filter,
  ]) async {
    try {
      return await _count(table, filter);
    } catch (e) {
      if (isMissingTable(e)) return 0;
      rethrow;
    }
  }

  // ---- Row 1 -------------------------------------------------------------

  /// The account counts follow [countActiveAccounts], as Analytics does.
  /// Kiosk sessions are those started in the last [rangeDays] days, today
  /// included: the Daily Trips range.
  Future<DashboardTopStats> getTopStats({int rangeDays = 7}) async {
    try {
      final from = dashboardRangeStart(rangeDays);
      final counts = await Future.wait([
        countActiveAccounts(_client, AccountGroup.students),
        countActiveAccounts(_client, AccountGroup.verified),
        countActiveAccounts(_client),
        _count('visitor_sessions',
            (q) => applyActiveVisitorFilter(q, DateTime.now())),
        _countOptional('kiosk_sessions',
            (q) => q.gte('started_at', from.toUtc().toIso8601String())),
      ]);
      final activeVisitors = counts[3];

      return DashboardTopStats(
        students: counts[0],
        registeredAccounts: counts[1],
        activeVisitors: activeVisitors,
        activeUsers: counts[2] + activeVisitors,
        kioskUsers: counts[4],
      );
    } catch (e) {
      throw RepositoryException(
          'Could not load user statistics: ${describeError(e)}', e);
    }
  }

  // ---- Row 2 -----------------------------------------------------------

  Future<DailySeries> getDailySeries(int days) async {
    try {
      final start = dashboardRangeStart(days);
      final dayList = [
        for (var i = 0; i < days; i++) start.add(Duration(days: i)),
      ];
      final index = {for (var i = 0; i < dayList.length; i++) dayList[i]: i};

      final registered = List<int>.filled(days, 0);
      final visitor = List<int>.filled(days, 0);
      final kiosk = List<int>.filled(days, 0);

      void bucket(
        List<Map<String, dynamic>> rows,
        List<int> target,
        List<String> keys, {
        bool Function(Map<String, dynamic>)? where,
      }) {
        for (final row in rows) {
          if (where != null && !where(row)) continue;
          final d = _anyDate(row, keys);
          if (d == null) continue;
          final i = index[_dateOnly(d)];
          if (i != null) target[i]++;
        }
      }

      // `*` so a table without trip_id yet gives no trips, not an error.
      final navRows = await _selectAll('navigation_sessions', '*',
          dateColumn: 'started_at', from: start);
      final tripRows = [
        for (final t in groupNavigationTrips(navRows)) t.start,
      ];
      // Both lines count trips, so together they are every trip that day.
      bucket(
        tripRows,
        registered,
        ['started_at', 'created_at'],
        where: (r) => !isVisitorRow(r),
      );
      bucket(
        tripRows,
        visitor,
        ['started_at', 'created_at'],
        where: isVisitorRow,
      );
      List<Map<String, dynamic>> kioskRows;
      try {
        kioskRows = await _selectAll('kiosk_sessions', 'id, started_at',
            dateColumn: 'started_at', from: start);
      } catch (e) {
        if (!isMissingTable(e)) rethrow;
        kioskRows = const [];
      }
      bucket(kioskRows, kiosk, ['started_at']);

      return DailySeries(
        days: dayList,
        registered: registered,
        visitor: visitor,
        kiosk: kiosk,
      );
    } catch (e) {
      throw RepositoryException(
          'Could not load daily activity: ${describeError(e)}', e);
    }
  }

  // ---- Row 3 & Row 4 left --------------------------------------------------

  Future<SusSummary> getSusSummary() async {
    try {
      final dedupe = dedupeSusRows(await _selectAll('sus_responses', '*'));
      final web = dedupe.kept;

      final scores = <double>[];
      for (final r in web) {
        final s = parseDouble(_anyValue(r, ['sus_score', 'score']));
        if (s != null) scores.add(s);
      }

      var poor = 0, marginal = 0, good = 0, excellent = 0;
      for (final s in scores) {
        if (s <= 50) {
          poor++;
        } else if (s <= 68) {
          marginal++;
        } else if (s <= 80) {
          good++;
        } else {
          excellent++;
        }
      }

      return SusSummary(
        totalResponses: web.length,
        kioskSurveys: await _countOptional(_kioskSurveyTable),
        averageScore: scores.isEmpty
            ? 0
            : scores.reduce((a, b) => a + b) / scores.length,
        poor: poor,
        marginal: marginal,
        good: good,
        excellent: excellent,
        note: susDedupeNote(dedupe),
      );
    } catch (e) {
      throw RepositoryException(
          'Could not load survey results: ${describeError(e)}', e);
    }
  }

  // ---- Row 4 right ------------------------------------------------------

  /// The day's comments: `feedback_comments` from the user app, through the
  /// same model as the Suggestions screen so they are anonymised the same
  /// way, and the kiosk survey's free text.
  Future<List<CommentEntry>> getComments(DateTime day) async {
    try {
      final span = wholeDays(day, day);
      final load = await _feedback.getComments(from: span.from, to: span.to);
      final kiosk = await _kioskSurveyRows(span.from, span.to);

      final entries = [
        for (final c in load.rows)
          if (c.comment.isNotEmpty)
            CommentEntry(
              text: c.comment,
              userType: _prettyRole(c.role),
              anonymousRef: c.anonymousRef,
              at: c.createdAt,
            ),
        for (final r in kiosk)
          if ((r['comments']?.toString().trim() ?? '').isNotEmpty)
            CommentEntry(
              text: removeEmails(r['comments'].toString().trim()),
              userType: 'Kiosk',
              anonymousRef: _kioskCode(r),
              at: parseDate(r['created_at']),
            ),
      ];
      entries.sort((a, b) =>
          (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
      return entries;
    } catch (e) {
      throw RepositoryException(
          'Could not load comments: ${describeError(e)}', e);
    }
  }

  /// The kiosk's `device_code`, shortened, or null when the row has none or
  /// the column doesn't exist yet (the kiosk app's kiosk_device_code.sql).
  String? _kioskCode(Map<String, dynamic> row) {
    final code = row['device_code']?.toString().trim() ?? '';
    return code.isEmpty ? null : shortId(code);
  }

  String _prettyRole(String? role) => role == null
      ? 'Unknown role'
      : role[0].toUpperCase() + role.substring(1);

  // ---- Row 5 left ------------------------------------------------------

  Future<List<BuildingVisit>> getMostVisited({int limit = 6}) async {
    try {
      final rows = await _selectAll('navigation_sessions', '*');
      final counts = <String, int>{};
      for (final t in groupNavigationTrips(rows)) {
        if (t.toName.isEmpty) continue;
        counts[t.toName] = (counts[t.toName] ?? 0) + 1;
      }
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return [
        for (final e in sorted.take(limit)) BuildingVisit(e.key, e.value),
      ];
    } catch (e) {
      throw RepositoryException(
          'Could not load most visited buildings: ${describeError(e)}', e);
    }
  }

  // ---- Row 5 right ---------------------------------------------------

  Future<SystemStatus> getSystemStatus() async {
    final errors = <String>[];
    var supabaseOk = false;
    DateTime? lastUpdate;
    int? buildings;

    try {
      buildings = await _count(
          'buildings', (q) => q.not('is_active', 'is', false));
      final latest = await _client
          .from('buildings')
          .select('updated_at')
          .order('updated_at', ascending: false, nullsFirst: false)
          .limit(1);
      supabaseOk = true;
      if (latest.isNotEmpty) {
        lastUpdate = parseDate(latest.first['updated_at']);
      }
    } catch (e) {
      errors.add('Could not load buildings: ${describeError(e)}');
    }

    Future<int?> countOrNull(String table, String label) async {
      try {
        return await _count(table, (q) => q.not('is_active', 'is', false));
      } catch (e) {
        errors.add('Could not load $label: ${describeError(e)}');
        return null;
      }
    }

    final outdoor = await countOrNull('outdoor_nodes', 'outdoor nodes');
    final indoor = await countOrNull('indoor_nodes', 'indoor nodes');
    final floors = await countOrNull('building_floors', 'floor plans');

    var mapTilerOk = false;
    if (!MapTilerConfig.isConfigured) {
      errors.add(MapTilerConfig.missingKeyMessage);
    } else {
      final problem = await mapTilerKeyProblem(_http, MapTilerConfig.apiKey);
      if (problem != null) errors.add(problem);
      mapTilerOk = problem == null;
    }

    return SystemStatus(
      supabaseOk: supabaseOk,
      mapTilerOk: mapTilerOk,
      totalBuildings: buildings,
      totalOutdoorNodes: outdoor,
      totalIndoorNodes: indoor,
      totalFloorPlans: floors,
      lastDataUpdate: lastUpdate,
      errors: errors,
    );
  }
}

/// Why MapTiler won't serve tiles with [key], or null when it will. Asks for
/// a small style file that needs the key, so only a 200 counts as working:
/// any other reply, a rejected key included, is a failure.
Future<String?> mapTilerKeyProblem(http.Client client, String key) async {
  final http.Response res;
  try {
    res = await client
        .get(Uri.https(
            'api.maptiler.com', '/maps/streets-v2/style.json', {'key': key}))
        .timeout(const Duration(seconds: 6));
  } catch (_) {
    return 'Could not reach MapTiler, so map tiles may not load. Check the '
        'internet connection.';
  }
  return switch (res.statusCode) {
    200 => null,
    401 || 403 => 'MapTiler rejected the key (HTTP ${res.statusCode}). Check '
        'MAPTILER_KEY and the domains the key allows in the MapTiler '
        'dashboard.',
    final code => 'MapTiler answered HTTP $code, so map tiles may not load.',
  };
}
