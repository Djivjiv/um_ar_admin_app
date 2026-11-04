import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../core/utils/excel_export.dart';
import '../../core/utils/parse_utils.dart';
import '../../core/utils/short_code.dart';
import '../../domain/models/kiosk_session_model.dart';
import '../../domain/models/kiosk_settings_model.dart';
import 'analytics_repository.dart' show ChartPoint;
import 'paged_query.dart';
import 'repository_exception.dart';

/// Session counts for fixed calendar periods (independent of any filter).
class KioskSessionCounts {
  final int today;
  final int thisWeek; // since Monday 00:00
  final int thisMonth; // since the 1st, 00:00

  const KioskSessionCounts({
    this.today = 0,
    this.thisWeek = 0,
    this.thisMonth = 0,
  });
}

class KioskAnalytics {
  final int totalSessions;
  final int totalSearches;
  final int totalRoutes;
  final int totalDestinationViews;
  final int feedbackCount;

  /// Average over sessions that have an `ended_at`; null if none do.
  final Duration? averageDuration;
  final int sessionsWithDuration;

  /// One point per day in the range (zero days included).
  final List<ChartPoint> dailyUsage;

  /// 24 points, index = hour of day.
  final List<ChartPoint> peakHours;

  final List<ChartPoint> topSearches;
  final List<ChartPoint> topBuildings;
  final List<ChartPoint> topRoutes;

  /// Events per kiosk, labelled by the first 8 characters of
  /// `kiosk_events.device_code`. Empty when that column doesn't exist yet
  /// (the kiosk app's kiosk_device_code.sql) or no event has one.
  final List<ChartPoint> eventsByKiosk;

  /// False when the `kiosk_events` table doesn't exist yet, so the "most
  /// searched / viewed / requested" lists can't be computed.
  final bool eventsAvailable;

  const KioskAnalytics({
    this.totalSessions = 0,
    this.totalSearches = 0,
    this.totalRoutes = 0,
    this.totalDestinationViews = 0,
    this.feedbackCount = 0,
    this.averageDuration,
    this.sessionsWithDuration = 0,
    this.dailyUsage = const [],
    this.peakHours = const [],
    this.topSearches = const [],
    this.topBuildings = const [],
    this.topRoutes = const [],
    this.eventsByKiosk = const [],
    this.eventsAvailable = false,
  });
}

/// One visitor comment from the kiosk's post-navigation survey.
class KioskSurveyComment {
  final String text;
  final String? destination;
  final int overallRating;
  final DateTime? createdAt;

  /// The first 8 characters of the kiosk's `device_code`, or null when the
  /// row has none (or the column doesn't exist yet).
  final String? kioskCode;

  const KioskSurveyComment({
    required this.text,
    this.destination,
    this.overallRating = 0,
    this.createdAt,
    this.kioskCode,
  });
}

/// Summary of `kiosk_survey_responses` in a date range.
class KioskSurveySummary {
  final int responseCount;

  /// 1–5 averages; null when there are no responses.
  final double? averageEase;
  final double? averageAccuracy;
  final double? averageOverall;

  /// Share of responses answering "Yes, definitely" (0–100).
  final double? wouldUseAgainPercent;
  final int wouldUseAgainYes;
  final int wouldUseAgainMaybe;
  final int wouldUseAgainNo;

  /// Newest first.
  final List<KioskSurveyComment> recentComments;

  /// False when the table doesn't exist yet (kiosk_survey.sql not run).
  final bool available;

  const KioskSurveySummary({
    this.responseCount = 0,
    this.averageEase,
    this.averageAccuracy,
    this.averageOverall,
    this.wouldUseAgainPercent,
    this.wouldUseAgainYes = 0,
    this.wouldUseAgainMaybe = 0,
    this.wouldUseAgainNo = 0,
    this.recentComments = const [],
    this.available = true,
  });
}

class KioskRepository {
  final _client = SupabaseConfig.client;
  static const _table = 'kiosk_sessions';
  static const _settingsTable = 'kiosk_settings';
  static const _eventsTable = 'kiosk_events';
  static const _surveyTable = 'kiosk_survey_responses';
  static const _recentCommentLimit = 20;

  static bool _isMissingTable(PostgrestException e) =>
      e.code == '42P01' || e.code == 'PGRST205';

  /// The row's `device_code`, shortened; null without one.
  static String? _kioskCode(Map<String, dynamic> row) {
    final code = row['device_code']?.toString().trim() ?? '';
    return code.isEmpty ? null : shortId(code);
  }

  // ---- settings -----------------------------------------------------------

  /// Returns the settings row, or defaults (with a null id) if none exists.
  Future<KioskSettingsModel> getSettings() async {
    try {
      final rows = await _client
          .from(_settingsTable)
          .select()
          .order('id')
          .limit(1);
      final list = rows as List;
      if (list.isEmpty) return const KioskSettingsModel();
      return KioskSettingsModel.fromJson(list.first as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw RepositoryException(
          'Failed to load kiosk settings: ${e.message}', e);
    } catch (e) {
      throw RepositoryException('Failed to load kiosk settings', e);
    }
  }

  /// Sets or changes the kiosk exit PIN on the settings row [settingsId],
  /// or on a new row when there is none yet. The PIN is never read back,
  /// and failures never carry it: the database's error can quote the row,
  /// so it is not attached.
  Future<void> setExitPin(String pin, {int? settingsId}) async {
    if (!kExitPinFormat.hasMatch(pin)) {
      throw RepositoryException('The PIN must be 4 to 8 digits.');
    }
    try {
      final List<dynamic> rows;
      if (settingsId == null) {
        rows = await _client
            .from(_settingsTable)
            .insert({
              ...(const KioskSettingsModel().toJson()..remove('updated_at')),
              'exit_pin': pin,
            })
            .select('id');
      } else {
        rows = await _client
            .from(_settingsTable)
            .update({
              'exit_pin': pin,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', settingsId)
            .select('id');
      }
      requireAffected(rows, 'Saving the exit PIN');
    } on RepositoryException {
      rethrow;
    } on PostgrestException catch (e) {
      if (isMissingColumn(e, 'exit_pin')) {
        throw RepositoryException(
            'The exit_pin column is missing. Run db/kiosk_settings.sql in '
            'the Supabase SQL editor.');
      }
      throw RepositoryException(
          'Failed to save the exit PIN (database error ${e.code ?? 'unknown'}).');
    } catch (_) {
      throw RepositoryException('Failed to save the exit PIN.');
    }
  }

  /// Saves [settings] (inserting the row the first time) and returns it.
  Future<KioskSettingsModel> updateSettings(KioskSettingsModel settings) async {
    try {
      final payload =
          settings.copyWith(updatedAt: DateTime.now()).toJson()..remove('id');
      final Map<String, dynamic> row;
      if (settings.id == null) {
        row = await _client
            .from(_settingsTable)
            .insert(payload)
            .select()
            .single();
      } else {
        final rows = await _client
            .from(_settingsTable)
            .update(payload)
            .eq('id', settings.id!)
            .select();
        final list = rows as List;
        if (list.isEmpty) {
          throw RepositoryException(
            'Update affected 0 rows. The settings row may be missing, or Row '
            'Level Security is blocking updates: only admins can change '
            'kiosk settings (db/admin_lockdown.sql).',
          );
        }
        row = list.first as Map<String, dynamic>;
      }
      return KioskSettingsModel.fromJson(row);
    } on RepositoryException {
      rethrow;
    } on PostgrestException catch (e) {
      throw RepositoryException(
          'Failed to save kiosk settings: ${e.message}', e);
    } catch (e) {
      throw RepositoryException('Failed to save kiosk settings', e);
    }
  }

  // ---- sessions -----------------------------------------------------------

  /// Fetches every row of a filtered query, page by page.
  Future<List<Map<String, dynamic>>> _fetchAll(
    String table, {
    String columns = '*',
    String dateColumn = 'started_at',
    DateTime? from,
    DateTime? to,
  }) {
    return fetchAllPages((a, b) {
      var query = _client.from(table).select(columns);
      if (from != null) {
        query = query.gte(dateColumn, from.toUtc().toIso8601String());
      }
      if (to != null) {
        query = query.lt(dateColumn, to.toUtc().toIso8601String());
      }
      return query
          .order(dateColumn, ascending: false)
          .order('id')
          .range(a, b);
    });
  }

  /// Sessions newest first, optionally limited to `from <= started_at < to`.
  Future<List<KioskSessionModel>> getKioskSessions({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final rows = await _fetchAll(_table, from: from, to: to);
      return rows.map(KioskSessionModel.fromJson).toList();
    } on PostgrestException catch (e) {
      // Table not created yet — degrade to an empty list rather than break.
      if (_isMissingTable(e)) return const [];
      throw RepositoryException('Failed to load kiosk sessions: ${e.message}', e);
    } catch (e) {
      throw RepositoryException('Failed to load kiosk sessions', e);
    }
  }

  /// All sessions — used by the Users screen.
  Future<List<KioskSessionModel>> getSessions() => getKioskSessions();

  Future<KioskSessionCounts> getSessionCounts() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final week = today.subtract(Duration(days: now.weekday - 1));
    final month = DateTime(now.year, now.month);
    final earliest = week.isBefore(month) ? week : month;
    try {
      final rows = await _fetchAll(_table, columns: 'started_at', from: earliest);
      var t = 0, w = 0, m = 0;
      for (final r in rows) {
        final d = KioskSessionModel.fromJson(r).startedAt;
        if (d == null) continue;
        if (!d.isBefore(today)) t++;
        if (!d.isBefore(week)) w++;
        if (!d.isBefore(month)) m++;
      }
      return KioskSessionCounts(today: t, thisWeek: w, thisMonth: m);
    } on PostgrestException catch (e) {
      if (_isMissingTable(e)) return const KioskSessionCounts();
      throw RepositoryException(
          'Failed to load kiosk session counts: ${e.message}', e);
    } catch (e) {
      throw RepositoryException('Failed to load kiosk session counts', e);
    }
  }

  // ---- analytics ----------------------------------------------------------

  /// Usage analytics for sessions with `from <= started_at < to`.
  Future<KioskAnalytics> getSessionAnalytics({
    required DateTime from,
    required DateTime to,
  }) async {
    final sessions = await getKioskSessions(from: from, to: to);

    final dayCounts = <DateTime, int>{};
    final hours = List<int>.filled(24, 0);
    var searches = 0, routes = 0, views = 0, feedback = 0;
    var durationTotal = Duration.zero;
    var withDuration = 0;
    for (final s in sessions) {
      searches += s.searchesCount;
      routes += s.routesCalculated;
      views += s.destinationsViewed;
      if (s.feedbackGiven) feedback++;
      final d = s.duration;
      if (d != null) {
        durationTotal += d;
        withDuration++;
      }
      final start = s.startedAt;
      if (start == null) continue;
      final day = DateTime(start.year, start.month, start.day);
      dayCounts[day] = (dayCounts[day] ?? 0) + 1;
      hours[start.hour]++;
    }

    final daily = <ChartPoint>[];
    final dayFmt = DateFormat('MMM d');
    for (var day = DateTime(from.year, from.month, from.day);
        day.isBefore(to);
        day = DateTime(day.year, day.month, day.day + 1)) {
      daily.add(ChartPoint(dayFmt.format(day), (dayCounts[day] ?? 0).toDouble()));
    }

    var eventsAvailable = true;
    final top = <String, Map<String, int>>{
      'search': {},
      'building_view': {},
      'route': {},
    };
    final byKiosk = <String, int>{};
    try {
      final events = await _fetchAll(_eventsTable,
          // `*`, as device_code only exists once kiosk_device_code.sql ran.
          dateColumn: 'created_at',
          from: from,
          to: to);
      for (final e in events) {
        final bucket = top[e['event_type']?.toString()];
        final label = e['label']?.toString().trim() ?? '';
        if (bucket == null || label.isEmpty) continue;
        bucket[label] = (bucket[label] ?? 0) + 1;
        if (_kioskCode(e) case final code?) {
          byKiosk[code] = (byKiosk[code] ?? 0) + 1;
        }
      }
    } on PostgrestException catch (e) {
      if (!_isMissingTable(e)) {
        throw RepositoryException(
            'Failed to load kiosk events: ${e.message}', e);
      }
      eventsAvailable = false;
    } catch (e) {
      throw RepositoryException('Failed to load kiosk events', e);
    }

    List<ChartPoint> ranked(Map<String, int> counts) {
      final entries = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return [
        for (final e in entries.take(8)) ChartPoint(e.key, e.value.toDouble()),
      ];
    }

    return KioskAnalytics(
      totalSessions: sessions.length,
      totalSearches: searches,
      totalRoutes: routes,
      totalDestinationViews: views,
      feedbackCount: feedback,
      averageDuration:
          withDuration == 0 ? null : durationTotal ~/ withDuration,
      sessionsWithDuration: withDuration,
      dailyUsage: daily,
      peakHours: [
        for (var h = 0; h < 24; h++)
          ChartPoint(h.toString().padLeft(2, '0'), hours[h].toDouble()),
      ],
      topSearches: ranked(top['search']!),
      topBuildings: ranked(top['building_view']!),
      topRoutes: ranked(top['route']!),
      eventsByKiosk: ranked(byKiosk),
      eventsAvailable: eventsAvailable,
    );
  }

  // ---- survey -------------------------------------------------------------

  /// Kiosk post-navigation survey results with `from <= created_at < to`.
  Future<KioskSurveySummary> getSurveySummary({
    required DateTime from,
    required DateTime to,
  }) async {
    final List<Map<String, dynamic>> rows;
    try {
      rows = await _fetchAll(_surveyTable,
          dateColumn: 'created_at', from: from, to: to);
    } on PostgrestException catch (e) {
      if (_isMissingTable(e)) {
        return const KioskSurveySummary(available: false);
      }
      throw RepositoryException(
          'Failed to load kiosk survey responses: ${e.message}', e);
    } catch (e) {
      throw RepositoryException('Failed to load kiosk survey responses', e);
    }
    if (rows.isEmpty) return const KioskSurveySummary();

    double? avg(String column) {
      final values = [
        for (final r in rows)
          if (parseInt(r[column]) case final v? when v >= 1 && v <= 5) v,
      ];
      return values.isEmpty
          ? null
          : values.reduce((a, b) => a + b) / values.length;
    }

    var yes = 0, maybe = 0, no = 0;
    final comments = <KioskSurveyComment>[];
    for (final r in rows) {
      switch (r['would_use_again']?.toString().toLowerCase()) {
        case 'yes':
          yes++;
        case 'maybe':
          maybe++;
        case 'no':
          no++;
      }
      final text = r['comments']?.toString().trim() ?? '';
      if (text.isNotEmpty && comments.length < _recentCommentLimit) {
        comments.add(KioskSurveyComment(
          text: text,
          destination: r['destination_name']?.toString(),
          overallRating: parseInt(r['overall_rating']) ?? 0,
          createdAt: parseDate(r['created_at']),
          kioskCode: _kioskCode(r),
        ));
      }
    }
    final answered = yes + maybe + no;

    return KioskSurveySummary(
      responseCount: rows.length,
      averageEase: avg('ease_rating'),
      averageAccuracy: avg('accuracy_rating'),
      averageOverall: avg('overall_rating'),
      wouldUseAgainPercent: answered == 0 ? null : yes * 100 / answered,
      wouldUseAgainYes: yes,
      wouldUseAgainMaybe: maybe,
      wouldUseAgainNo: no,
      recentComments: comments,
    );
  }

  // ---- export -------------------------------------------------------------

  /// Prompts for a location and writes [sessions] to an .xlsx file.
  /// Returns the saved path, or null if the admin cancelled.
  Future<String?> exportSessionsToExcel(
    List<KioskSessionModel> sessions, {
    required DateTime from,
    required DateTime to,
  }) async {
    final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final rows = <List<Object?>>[
      [
        'Session ID',
        'Started At',
        'Ended At',
        'Duration (seconds)',
        'Searches',
        'Routes Calculated',
        'Destinations Viewed',
        'Feedback Given',
      ],
      for (final s in sessions)
        [
          s.id,
          s.startedAt == null ? '' : fmt.format(s.startedAt!),
          s.endedAt == null ? '' : fmt.format(s.endedAt!),
          s.duration?.inSeconds,
          s.searchesCount,
          s.routesCalculated,
          s.destinationsViewed,
          s.feedbackGiven,
        ],
    ];
    final day = DateFormat('yyyyMMdd');
    final lastDay = to.subtract(const Duration(days: 1));
    try {
      return await saveExcelFile(
        'kiosk_sessions_${day.format(from)}_${day.format(lastDay)}',
        'Kiosk Sessions',
        rows,
      );
    } catch (e) {
      throw RepositoryException('Failed to export kiosk sessions', e);
    }
  }
}
