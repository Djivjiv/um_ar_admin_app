import '../../core/config/supabase_config.dart';
import '../../domain/models/navigation_session_model.dart';
import 'repository_exception.dart';

/// A single (label, value) pair used by charts.
class ChartPoint {
  final String label;
  final double value;
  const ChartPoint(this.label, this.value);
}

class AnalyticsRepository {
  final _client = SupabaseConfig.client;
  static const _navTable = 'navigation_sessions';
  static const _profilesTable = 'user_profiles';
  static const _visitorTable = 'visitor_sessions';
  static const _susTable = 'sus_responses';

  Future<List<NavigationSessionModel>> _sessions({
    DateTime? from,
    DateTime? to,
  }) async {
    dynamic query = _client.from(_navTable).select();
    if (from != null) {
      query = query.gte('started_at', from.toUtc().toIso8601String());
    }
    if (to != null) {
      query = query.lte('started_at', to.toUtc().toIso8601String());
    }
    final rows = await query;
    return (rows as List)
        .map((e) => NavigationSessionModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ChartPoint>> getSessionsPerDay({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final sessions = await _sessions(from: from, to: to);
      final counts = <String, int>{};
      for (final s in sessions) {
        final d = s.startedAt;
        if (d == null) continue;
        final key =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        counts[key] = (counts[key] ?? 0) + 1;
      }
      final keys = counts.keys.toList()..sort();
      return [for (final k in keys) ChartPoint(k, counts[k]!.toDouble())];
    } catch (e) {
      throw RepositoryException('Failed to load sessions per day', e);
    }
  }

  Future<List<ChartPoint>> getUserDistribution() async {
    try {
      final profiles = await _client.from(_profilesTable).select('role');
      final visitors = await _client.from(_visitorTable).select('id');
      final counts = <String, int>{};
      for (final p in profiles as List) {
        final role = (p['role']?.toString() ?? 'user');
        counts[role] = (counts[role] ?? 0) + 1;
      }
      counts['visitor'] = (visitors as List).length;
      return [
        for (final e in counts.entries) ChartPoint(e.key, e.value.toDouble()),
      ];
    } catch (e) {
      throw RepositoryException('Failed to load user distribution', e);
    }
  }

  Future<List<ChartPoint>> getMostVisitedBuildings({
    DateTime? from,
    DateTime? to,
    int limit = 8,
  }) async {
    try {
      final sessions = await _sessions(from: from, to: to);
      final counts = <String, int>{};
      for (final s in sessions) {
        final name = (s.toName ?? '').trim();
        if (name.isEmpty) continue;
        counts[name] = (counts[name] ?? 0) + 1;
      }
      final entries = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return [
        for (final e in entries.take(limit))
          ChartPoint(e.key, e.value.toDouble()),
      ];
    } catch (e) {
      throw RepositoryException('Failed to load most visited buildings', e);
    }
  }

  /// Returns 24 values (index = hour of day) with session counts.
  Future<List<ChartPoint>> getPeakHours({DateTime? from, DateTime? to}) async {
    try {
      final sessions = await _sessions(from: from, to: to);
      final buckets = List<int>.filled(24, 0);
      for (final s in sessions) {
        final d = s.startedAt;
        if (d == null) continue;
        buckets[d.hour]++;
      }
      return [
        for (var h = 0; h < 24; h++)
          ChartPoint(h.toString().padLeft(2, '0'), buckets[h].toDouble()),
      ];
    } catch (e) {
      throw RepositoryException('Failed to load peak hours', e);
    }
  }

  Future<double> getCompletionRate({DateTime? from, DateTime? to}) async {
    try {
      final sessions = await _sessions(from: from, to: to);
      if (sessions.isEmpty) return 0;
      final completed = sessions.where((s) => s.completed).length;
      return completed / sessions.length * 100;
    } catch (e) {
      throw RepositoryException('Failed to compute completion rate', e);
    }
  }

  Future<double> getAverageDistance({DateTime? from, DateTime? to}) async {
    try {
      final sessions = await _sessions(from: from, to: to);
      final withDistance =
          sessions.where((s) => s.distanceMeters != null).toList();
      if (withDistance.isEmpty) return 0;
      final total = withDistance.fold<double>(
          0, (sum, s) => sum + (s.distanceMeters ?? 0));
      return total / withDistance.length;
    } catch (e) {
      throw RepositoryException('Failed to compute average distance', e);
    }
  }

  Future<int> getSessionsTodayCount() async {
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final rows = await _client
          .from(_navTable)
          .select('id')
          .gte('started_at', start.toUtc().toIso8601String());
      return (rows as List).length;
    } catch (e) {
      throw RepositoryException('Failed to count today\'s sessions', e);
    }
  }

  Future<int> getTotalUsersCount() async {
    try {
      final rows = await _client.from(_profilesTable).select('id');
      return (rows as List).length;
    } catch (e) {
      throw RepositoryException('Failed to count users', e);
    }
  }

  Future<int> getActiveVisitorsCount() async {
    try {
      final rows = await _client
          .from(_visitorTable)
          .select('id, expires_at, is_expired');
      final now = DateTime.now();
      return (rows as List).where((r) {
        if (r['is_expired'] == true) return false;
        final exp = DateTime.tryParse(r['expires_at']?.toString() ?? '');
        return exp == null || exp.isAfter(now);
      }).length;
    } catch (e) {
      throw RepositoryException('Failed to count active visitors', e);
    }
  }

  Future<double> getAverageSusScore() async {
    try {
      final rows = await _client.from(_susTable).select('sus_score');
      final scores = (rows as List)
          .map((r) => double.tryParse(r['sus_score']?.toString() ?? ''))
          .whereType<double>()
          .toList();
      if (scores.isEmpty) return 0;
      return scores.reduce((a, b) => a + b) / scores.length;
    } catch (e) {
      throw RepositoryException('Failed to compute average SUS score', e);
    }
  }

  Future<List<NavigationSessionModel>> getRecentSessions({int limit = 10}) async {
    try {
      final rows = await _client
          .from(_navTable)
          .select()
          .order('started_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((e) =>
              NavigationSessionModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw RepositoryException('Failed to load recent sessions', e);
    }
  }

  /// Rows for an Excel export — first row is the header.
  Future<List<List<Object?>>> exportSessionsRows({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final sessions = await _sessions(from: from, to: to);
      return <List<Object?>>[
        [
          'id',
          'user_id',
          'visitor_session_id',
          'from_name',
          'to_name',
          'distance_meters',
          'duration_seconds',
          'completed',
          'started_at',
          'completed_at',
        ],
        for (final s in sessions)
          [
            s.id,
            s.userId ?? '',
            s.visitorSessionId ?? '',
            s.fromName ?? '',
            s.toName ?? '',
            s.distanceMeters,
            s.durationSeconds,
            s.completed,
            s.startedAt?.toIso8601String() ?? '',
            s.completedAt?.toIso8601String() ?? '',
          ],
      ];
    } catch (e) {
      throw RepositoryException('Failed to export sessions', e);
    }
  }
}
