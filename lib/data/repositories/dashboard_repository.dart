import 'package:http/http.dart' as http;

import '../../core/config/supabase_config.dart';
import '../../core/utils/parse_utils.dart';
import '../../domain/models/announcement_model.dart';
import 'repository_exception.dart';

// ---------------------------------------------------------------------------
// Result models
// ---------------------------------------------------------------------------

class DashboardTopStats {
  final int students;
  final int registeredAccounts;
  final int activeVisitors;
  final int activeUsers;
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
  final List<int> mobile; // all navigation_sessions
  final List<int> visitor; // visitor_sessions
  final List<int> kiosk; // kiosk_sessions
  final List<int> registered; // navigation_sessions with a user_id

  const DailySeries({
    this.days = const [],
    this.mobile = const [],
    this.visitor = const [],
    this.kiosk = const [],
    this.registered = const [],
  });

  bool get isEmpty => days.isEmpty;
}

class SusSummary {
  final int totalResponses;
  final double averageScore;
  final int poor; // 0-50
  final int marginal; // 51-68
  final int good; // 69-80
  final int excellent; // 81-100

  const SusSummary({
    this.totalResponses = 0,
    this.averageScore = 0,
    this.poor = 0,
    this.marginal = 0,
    this.good = 0,
    this.excellent = 0,
  });

  String get grade {
    if (averageScore > 80) return 'Excellent';
    if (averageScore >= 69) return 'Good';
    if (averageScore >= 51) return 'Marginal';
    return 'Poor';
  }
}

class CommentEntry {
  final String text;
  final String userType; // "Student", "Visitor", "Kiosk"
  final DateTime? at;

  const CommentEntry({required this.text, required this.userType, this.at});
}

class BuildingVisit {
  final String name;
  final int count;
  const BuildingVisit(this.name, this.count);
}

class SystemStatus {
  final bool supabaseOk;
  final bool mapTilerOk;
  final int totalBuildings;
  final int totalOutdoorNodes;
  final int totalIndoorNodes;
  final int totalFloorPlans;
  final DateTime? lastDataUpdate;

  const SystemStatus({
    this.supabaseOk = false,
    this.mapTilerOk = false,
    this.totalBuildings = 0,
    this.totalOutdoorNodes = 0,
    this.totalIndoorNodes = 0,
    this.totalFloorPlans = 0,
    this.lastDataUpdate,
  });
}

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

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
  final _client = SupabaseConfig.client;

  static const _dateKeys = [
    'submitted_at',
    'created_at',
    'started_at',
    'inserted_at',
    'timestamp',
  ];

  Future<List<Map<String, dynamic>>> _safeSelect(
    String table, [
    String columns = '*',
  ]) async {
    try {
      final rows = await _client.from(table).select(columns);
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (_) {
      // Table may not exist yet (e.g. kiosk_* tables). Degrade gracefully.
      return <Map<String, dynamic>>[];
    }
  }

  // ---- Row 1 -------------------------------------------------------------

  Future<DashboardTopStats> getTopStats() async {
    try {
      final profiles = await _safeSelect(
          'user_profiles', 'id, role, is_verified, is_active');
      final visitors = await _safeSelect('visitor_sessions', 'id, is_expired');
      final kiosk = await _safeSelect('kiosk_sessions', 'id');

      final students = profiles
          .where((p) => (p['role']?.toString().toLowerCase()) == 'student')
          .length;
      final verified =
          profiles.where((p) => p['is_verified'] == true).length;
      final activeProfiles =
          profiles.where((p) => p['is_active'] != false).length;
      final activeVisitors =
          visitors.where((v) => v['is_expired'] != true).length;

      return DashboardTopStats(
        students: students,
        registeredAccounts: verified,
        activeVisitors: activeVisitors,
        activeUsers: activeProfiles + activeVisitors,
        kioskUsers: kiosk.length,
      );
    } catch (e) {
      throw RepositoryException('Failed to load dashboard stats', e);
    }
  }

  // ---- Row 2 -----------------------------------------------------------

  Future<DailySeries> getDailySeries(int days) async {
    try {
      final now = _dateOnly(DateTime.now());
      final start = now.subtract(Duration(days: days - 1));
      final dayList = [
        for (var i = 0; i < days; i++) start.add(Duration(days: i)),
      ];
      final index = {for (var i = 0; i < dayList.length; i++) dayList[i]: i};

      final mobile = List<int>.filled(days, 0);
      final visitor = List<int>.filled(days, 0);
      final kiosk = List<int>.filled(days, 0);
      final registered = List<int>.filled(days, 0);

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

      final navRows =
          await _safeSelect('navigation_sessions', 'id, started_at, user_id');
      // Mobile line: every navigation session that day.
      bucket(navRows, mobile, ['started_at', 'created_at']);
      // "Registered" bar: navigation sessions by a logged-in registered user.
      bucket(
        navRows,
        registered,
        ['started_at', 'created_at'],
        where: (r) =>
            r['user_id'] != null && r['user_id'].toString().isNotEmpty,
      );
      bucket(await _safeSelect('visitor_sessions', 'id, started_at'), visitor,
          ['started_at', 'created_at']);
      bucket(await _safeSelect('kiosk_sessions'), kiosk, _dateKeys);

      return DailySeries(
        days: dayList,
        mobile: mobile,
        visitor: visitor,
        kiosk: kiosk,
        registered: registered,
      );
    } catch (e) {
      throw RepositoryException('Failed to load daily activity', e);
    }
  }

  // ---- Row 3 & Row 4 left --------------------------------------------------

  Future<SusSummary> getSusSummary() async {
    try {
      final web = await _safeSelect('sus_responses', 'sus_score');
      final kiosk = await _safeSelect('kiosk_sus_responses');

      final scores = <double>[];
      for (final r in [...web, ...kiosk]) {
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
        totalResponses: web.length + kiosk.length,
        averageScore: scores.isEmpty
            ? 0
            : scores.reduce((a, b) => a + b) / scores.length,
        poor: poor,
        marginal: marginal,
        good: good,
        excellent: excellent,
      );
    } catch (e) {
      throw RepositoryException('Failed to load SUS summary', e);
    }
  }

  // ---- Row 4 right ------------------------------------------------------

  Future<List<CommentEntry>> getComments(DateTime day) async {
    try {
      final target = _dateOnly(day);
      final web = await _safeSelect('sus_responses');
      final kiosk = await _safeSelect('kiosk_sus_responses');

      final entries = <CommentEntry>[];

      void collect(
          List<Map<String, dynamic>> rows, String fallbackType) {
        for (final r in rows) {
          final comment =
              _anyValue(r, ['comment', 'comments', 'feedback'])?.toString();
          if (comment == null || comment.trim().isEmpty) continue;
          final at = _anyDate(r, _dateKeys);
          if (at == null || _dateOnly(at) != target) continue;
          final rawType =
              _anyValue(r, ['user_type', 'type'])?.toString().trim();
          entries.add(CommentEntry(
            text: comment.trim(),
            userType: (rawType == null || rawType.isEmpty)
                ? fallbackType
                : _prettyType(rawType),
            at: at,
          ));
        }
      }

      collect(web, 'Student');
      collect(kiosk, 'Kiosk');

      entries.sort((a, b) =>
          (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
      return entries;
    } catch (e) {
      throw RepositoryException('Failed to load comments', e);
    }
  }

  String _prettyType(String raw) {
    final r = raw.toLowerCase();
    if (r.contains('visit')) return 'Visitor';
    if (r.contains('kiosk')) return 'Kiosk';
    if (r.contains('student')) return 'Student';
    return raw[0].toUpperCase() + raw.substring(1);
  }

  // ---- Row 5 left ------------------------------------------------------

  Future<List<BuildingVisit>> getMostVisited({int limit = 6}) async {
    try {
      final rows =
          await _safeSelect('navigation_sessions', 'to_name');
      final counts = <String, int>{};
      for (final r in rows) {
        final name = r['to_name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        counts[name] = (counts[name] ?? 0) + 1;
      }
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return [
        for (final e in sorted.take(limit)) BuildingVisit(e.key, e.value),
      ];
    } catch (e) {
      throw RepositoryException('Failed to load most visited buildings', e);
    }
  }

  // ---- Row 5 center ---------------------------------------------------

  Future<List<AnnouncementModel>> getRecentAnnouncements({int limit = 5}) async {
    try {
      final rows = await _client
          .from('announcements')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((e) => AnnouncementModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw RepositoryException('Failed to load announcements', e);
    }
  }

  // ---- Row 5 right ---------------------------------------------------

  Future<SystemStatus> getSystemStatus() async {
    var supabaseOk = false;
    DateTime? lastUpdate;
    var buildings = 0, outdoor = 0, indoor = 0, floors = 0;

    try {
      final b = await _client
          .from('buildings')
          .select('id, updated_at')
          .order('updated_at', ascending: false);
      supabaseOk = true;
      final list = (b as List).cast<Map<String, dynamic>>();
      buildings = list.length;
      if (list.isNotEmpty) {
        lastUpdate = parseDate(list.first['updated_at']);
      }
    } catch (_) {
      supabaseOk = false;
    }

    outdoor = (await _safeSelect('outdoor_nodes', 'id')).length;
    indoor = (await _safeSelect('indoor_nodes', 'id')).length;
    floors = (await _safeSelect('building_floors', 'id')).length;

    final mapTilerOk = await _pingMapTiler();

    return SystemStatus(
      supabaseOk: supabaseOk,
      mapTilerOk: mapTilerOk,
      totalBuildings: buildings,
      totalOutdoorNodes: outdoor,
      totalIndoorNodes: indoor,
      totalFloorPlans: floors,
      lastDataUpdate: lastUpdate,
    );
  }

  Future<bool> _pingMapTiler() async {
    try {
      final res = await http
          .get(Uri.parse('https://api.maptiler.com/'))
          .timeout(const Duration(seconds: 6));
      // Any HTTP response (even 4xx without a key) means the API is reachable.
      return res.statusCode > 0;
    } catch (_) {
      return false;
    }
  }
}
