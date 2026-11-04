
import '../../core/config/supabase_config.dart';
import '../../core/utils/navigation_metrics.dart';
import '../../core/utils/parse_utils.dart';
import '../../domain/models/visitor_session_model.dart';
import 'paged_query.dart';
import 'repository_exception.dart';

/// One line of the Visitor screen: a `visitor_sessions` row, or an offline
/// visitor. The user app starts a session on the phone alone when it has no
/// connection, so that visitor has no row and is known only by `device_code`.
class VisitorEntry {
  /// Null for an offline visitor.
  final VisitorSessionModel? session;
  final String? deviceCode;

  /// When the session started, or the offline visitor's first row.
  final DateTime? startedAt;

  /// The offline visitor's latest row; null for a session.
  final DateTime? lastSeenAt;

  const VisitorEntry({
    this.session,
    this.deviceCode,
    this.startedAt,
    this.lastSeenAt,
  });

  factory VisitorEntry.fromSession(VisitorSessionModel session) => VisitorEntry(
        session: session,
        deviceCode: session.deviceCode,
        startedAt: session.startedAt,
      );

  bool get isOffline => session == null;

  bool get isActive => session?.isActive ?? false;

  /// "Active", "Expired" or "Offline".
  String get statusLabel {
    if (isOffline) return 'Offline';
    return isActive ? 'Active' : 'Expired';
  }
}

/// One visitor's trips, newest first.
class VisitorHistory {
  final List<NavigationTrip> trips;

  /// Rows with no `trip_id`, left out as everywhere else.
  final int rowsWithoutTrip;

  const VisitorHistory({this.trips = const [], this.rowsWithoutTrip = 0});
}

/// The offline visitors in [rows], one per `device_code`. [rows] are from
/// `navigation_sessions` and `sus_responses`, with no `visitor_session_id`.
/// Rows of signed-in users, and rows with no `device_code`, can't be one.
List<VisitorEntry> offlineVisitorEntries(
  Iterable<Map<String, dynamic>> rows,
) {
  final first = <String, DateTime?>{};
  final last = <String, DateTime?>{};
  for (final row in rows) {
    final code = row['device_code']?.toString().trim() ?? '';
    if (code.isEmpty || !isVisitorRow(row)) continue;
    final at = parseDate(row['started_at'] ?? row['submitted_at']);
    final earliest = first[code];
    final latest = last[code];
    first[code] = earliest == null || (at != null && at.isBefore(earliest))
        ? at
        : earliest;
    last[code] =
        latest == null || (at != null && at.isAfter(latest)) ? at : latest;
  }
  return [
    for (final code in first.keys)
      VisitorEntry(
        deviceCode: code,
        startedAt: first[code],
        lastSeenAt: last[code],
      ),
  ];
}

class VisitorSessionRepository {
  final _client = SupabaseConfig.client;
  static const _table = 'visitor_sessions';
  static const _navTable = 'navigation_sessions';
  static const _susTable = 'sus_responses';

  Future<List<VisitorSessionModel>> getAll() async {
    try {
      final rows = await fetchAllPages((a, b) => _client
          .from(_table)
          .select()
          .order('started_at', ascending: false)
          .order('id')
          .range(a, b));
      return rows.map(VisitorSessionModel.fromJson).toList();
    } catch (e) {
      throw RepositoryException('Failed to load visitor sessions', e);
    }
  }

  /// Visitors' rows of [table] that belong to no session, or none when the
  /// table doesn't exist yet. `select *`, as `device_code` may not exist yet.
  Future<List<Map<String, dynamic>>> _rowsWithoutSession(String table) async {
    try {
      return await fetchAllPages((a, b) => _client
          .from(table)
          .select()
          .isFilter('visitor_session_id', null)
          .isFilter('user_id', null)
          .order('id')
          .range(a, b));
    } catch (e) {
      if (isMissingTable(e)) return const [];
      rethrow;
    }
  }

  /// Sessions and offline visitors together, newest first.
  Future<List<VisitorEntry>> getEntries() async {
    final sessions = await getAll();
    try {
      final rows = [
        ...await _rowsWithoutSession(_navTable),
        ...await _rowsWithoutSession(_susTable),
      ];
      final entries = [
        ...sessions.map(VisitorEntry.fromSession),
        ...offlineVisitorEntries(rows),
      ];
      final never = DateTime.fromMillisecondsSinceEpoch(0);
      entries.sort((a, b) =>
          (b.startedAt ?? never).compareTo(a.startedAt ?? never));
      return entries;
    } catch (e) {
      throw RepositoryException(
          'Failed to load offline visitors: ${describeError(e)}', e);
    }
  }

  /// [entry]'s trips, one line each: by session, or by `device_code` for an
  /// offline visitor.
  Future<VisitorHistory> getTripHistory(VisitorEntry entry) async {
    try {
      final session = entry.session;
      final rows = await fetchAllPages((a, b) {
        var query = _client.from(_navTable).select();
        query = session != null
            ? query.eq('visitor_session_id', session.id)
            : query
                .eq('device_code', entry.deviceCode ?? '')
                .isFilter('visitor_session_id', null)
                .isFilter('user_id', null);
        return query
            .order('started_at', ascending: false)
            .order('id')
            .range(a, b);
      });
      return VisitorHistory(
        trips: groupNavigationTrips(rows),
        rowsWithoutTrip: rowsWithoutTripId(rows),
      );
    } catch (e) {
      throw RepositoryException(
          'Failed to load visitor trips: ${describeError(e)}', e);
    }
  }
}
