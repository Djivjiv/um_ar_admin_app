import '../../core/config/supabase_config.dart';
import '../../core/utils/navigation_metrics.dart';
import '../../core/utils/sus_dedupe.dart';
import '../../core/utils/trip_export.dart';
import '../../domain/models/sus_response_model.dart';
import 'analytics_repository.dart' show ChartPoint;
import 'paged_query.dart';
import 'repository_exception.dart';

/// SUS statistics over one response per person.
class SusStats {
  /// Newest first.
  final List<SusResponseModel> responses;
  final double average;
  final List<ChartPoint> distribution;
  final List<ChartPoint> byUserType;
  final SusDedupeResult dedupe;

  const SusStats({
    this.responses = const [],
    this.average = 0,
    this.distribution = const [],
    this.byUserType = const [],
    this.dedupe = const SusDedupeResult(),
  });
}

/// Counts [scores] into the standard SUS grade bands.
List<ChartPoint> susBands(Iterable<double> scores) {
  final bands = <String, int>{
    '0-25': 0,
    '26-50': 0,
    '51-68': 0,
    '69-80': 0,
    '81-100': 0,
  };
  for (final s in scores) {
    final band = s <= 25
        ? '0-25'
        : s <= 50
            ? '26-50'
            : s <= 68
                ? '51-68'
                : s <= 80
                    ? '69-80'
                    : '81-100';
    bands[band] = bands[band]! + 1;
  }
  return [
    for (final e in bands.entries) ChartPoint(e.key, e.value.toDouble()),
  ];
}

/// Computes the statistics from raw rows, keeping each person's first one.
SusStats computeSusStats(List<Map<String, dynamic>> rows) {
  final dedupe = dedupeSusRows(rows);
  final responses = dedupe.kept.map(SusResponseModel.fromJson).toList();
  final scores = responses.map((r) => r.susScore).whereType<double>().toList();

  final sums = <String, double>{};
  final counts = <String, int>{};
  for (final r in responses) {
    if (r.susScore == null) continue;
    final type = r.userType ?? 'unknown';
    sums[type] = (sums[type] ?? 0) + r.susScore!;
    counts[type] = (counts[type] ?? 0) + 1;
  }
  return SusStats(
    responses: responses,
    average:
        scores.isEmpty ? 0 : scores.reduce((a, b) => a + b) / scores.length,
    distribution: susBands(scores),
    byUserType: [
      for (final e in sums.entries)
        ChartPoint(e.key, e.value / counts[e.key]!),
    ],
    dedupe: dedupe,
  );
}

/// The SUS sheet, first row = header. [modeByTrip] is each trip's mode label,
/// for the answers linked to a trip. `role` is what the user app recorded;
/// `user_type` is signed-in or visitor, as in the trip export. The anonymous
/// id stands in for the raw account, session and row ids, which stay out.
List<List<Object?>> susExportRows(
  Iterable<SusResponseModel> responses,
  Map<String, String> modeByTrip,
) =>
    <List<Object?>>[
      [
        'anonymous_device_id',
        'navigation_session_id',
        'mode',
        'user_type',
        'role',
        for (var i = 1; i <= 10; i++) 'q$i',
        'sus_score',
        'submitted_at',
      ],
      for (final r in responses)
        [
          anonymousDeviceId(r.deviceCode),
          r.navigationSessionId ?? '',
          modeByTrip[r.navigationSessionId] ?? '',
          r.isVisitor ? 'visitor' : 'signed-in',
          r.userType ?? '',
          for (var i = 1; i <= 10; i++) r.answerFor(i),
          r.susScore,
          r.submittedAt?.toIso8601String() ?? '',
        ],
    ];

class SusRepository {
  final _client = SupabaseConfig.client;
  static const _table = 'sus_responses';
  static const _navTable = 'navigation_sessions';

  Future<List<Map<String, dynamic>>> _allRows() {
    return fetchAllPages((a, b) => _client
        .from(_table)
        .select()
        .order('submitted_at', ascending: false)
        .order('id')
        .range(a, b));
  }

  /// One response per person, newest first.
  Future<List<SusResponseModel>> getAll() async {
    return (await getStats()).responses;
  }

  Future<SusStats> getStats() async {
    try {
      return computeSusStats(await _allRows());
    } catch (e) {
      throw RepositoryException('Failed to load SUS responses', e);
    }
  }

  /// Each trip's mode label by `trip_id`, or none when the table doesn't
  /// exist yet. `select *`, as `mode` may not exist either.
  Future<Map<String, String>> _modeByTrip() async {
    try {
      final rows = await fetchAllPages((a, b) =>
          _client.from(_navTable).select().order('id').range(a, b));
      return {
        for (final t in groupNavigationTrips(rows))
          t.start['trip_id'].toString(): modeLabel(t.mode),
      };
    } catch (e) {
      if (isMissingTable(e)) return const {};
      rethrow;
    }
  }

  /// Rows for an Excel export — first row is the header. One response per
  /// person, like the statistics.
  Future<List<List<Object?>>> exportRows() async {
    try {
      return susExportRows(await getAll(), await _modeByTrip());
    } catch (e) {
      if (e is RepositoryException) rethrow;
      throw RepositoryException(
          'Failed to export SUS responses: ${describeError(e)}', e);
    }
  }
}
