import '../../core/config/supabase_config.dart';
import '../../domain/models/sus_response_model.dart';
import 'analytics_repository.dart' show ChartPoint;
import 'repository_exception.dart';

class SusRepository {
  final _client = SupabaseConfig.client;
  static const _table = 'sus_responses';

  Future<List<SusResponseModel>> getAll() async {
    try {
      final rows = await _client
          .from(_table)
          .select()
          .order('submitted_at', ascending: false);
      return (rows as List)
          .map((e) => SusResponseModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw RepositoryException('Failed to load SUS responses', e);
    }
  }

  Future<double> getAverageScore() async {
    try {
      final all = await getAll();
      final scores =
          all.map((r) => r.susScore).whereType<double>().toList();
      if (scores.isEmpty) return 0;
      return scores.reduce((a, b) => a + b) / scores.length;
    } catch (e) {
      if (e is RepositoryException) rethrow;
      throw RepositoryException('Failed to compute average SUS score', e);
    }
  }

  /// Buckets scores into standard SUS grade bands.
  Future<List<ChartPoint>> getScoreDistribution() async {
    try {
      final all = await getAll();
      final bands = <String, int>{
        '0-25': 0,
        '26-50': 0,
        '51-68': 0,
        '69-80': 0,
        '81-100': 0,
      };
      for (final r in all) {
        final s = r.susScore;
        if (s == null) continue;
        if (s <= 25) {
          bands['0-25'] = bands['0-25']! + 1;
        } else if (s <= 50) {
          bands['26-50'] = bands['26-50']! + 1;
        } else if (s <= 68) {
          bands['51-68'] = bands['51-68']! + 1;
        } else if (s <= 80) {
          bands['69-80'] = bands['69-80']! + 1;
        } else {
          bands['81-100'] = bands['81-100']! + 1;
        }
      }
      return [
        for (final e in bands.entries) ChartPoint(e.key, e.value.toDouble()),
      ];
    } catch (e) {
      if (e is RepositoryException) rethrow;
      throw RepositoryException('Failed to compute score distribution', e);
    }
  }

  Future<List<ChartPoint>> getScoreByUserType() async {
    try {
      final all = await getAll();
      final sums = <String, double>{};
      final counts = <String, int>{};
      for (final r in all) {
        if (r.susScore == null) continue;
        final type = r.userType ?? 'unknown';
        sums[type] = (sums[type] ?? 0) + r.susScore!;
        counts[type] = (counts[type] ?? 0) + 1;
      }
      return [
        for (final e in sums.entries)
          ChartPoint(e.key, e.value / counts[e.key]!),
      ];
    } catch (e) {
      if (e is RepositoryException) rethrow;
      throw RepositoryException('Failed to compute score by user type', e);
    }
  }

  /// Rows for an Excel export — first row is the header.
  Future<List<List<Object?>>> exportRows() async {
    try {
      final all = await getAll();
      return <List<Object?>>[
        [
          'id',
          'user_id',
          'visitor_session_id',
          'user_type',
          for (var i = 1; i <= 10; i++) 'q$i',
          'sus_score',
          'submitted_at',
        ],
        for (final r in all)
          [
            r.id,
            r.userId ?? '',
            r.visitorSessionId ?? '',
            r.userType ?? '',
            for (var i = 1; i <= 10; i++) r.answerFor(i),
            r.susScore,
            r.submittedAt?.toIso8601String() ?? '',
          ],
      ];
    } catch (e) {
      if (e is RepositoryException) rethrow;
      throw RepositoryException('Failed to export SUS responses', e);
    }
  }
}
