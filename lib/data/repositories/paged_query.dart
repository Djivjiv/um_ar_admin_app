import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/access_level.dart';
import 'repository_exception.dart';

/// Rows per request. A plain `select()` silently stops at PostgREST's
/// default max of 1000 rows, so anything that must see every row pages.
const int kPageSize = 1000;

/// Fetches every row by calling [fetchPage] with consecutive inclusive
/// `[from, to]` ranges (for `.range(from, to)`) until a page comes back
/// shorter than [pageSize].
///
/// [fetchPage] should apply a stable order (usually ending in `id`) so pages
/// don't overlap or skip rows.
Future<List<Map<String, dynamic>>> fetchAllPages(
  Future<List<Map<String, dynamic>>> Function(int from, int to) fetchPage, {
  int pageSize = kPageSize,
}) async {
  if (pageSize <= 0) throw ArgumentError.value(pageSize, 'pageSize');
  final all = <Map<String, dynamic>>[];
  for (var start = 0;; start += pageSize) {
    final page = await fetchPage(start, start + pageSize - 1);
    all.addAll(page);
    if (page.length < pageSize) return all;
  }
}

/// Which rows of a table with `is_active` a query returns. Repositories
/// default to [active], so inactive rows only appear when a caller asks.
enum ActiveFilter {
  active('Active'),
  inactive('Inactive'),
  all('All');

  final String label;
  const ActiveFilter(this.label);
}

/// Applies [filter] to [query]. A null `is_active` counts as active, as in
/// the models and the user apps, so "active" is `is not false`.
PostgrestFilterBuilder<T> applyActiveFilter<T>(
  PostgrestFilterBuilder<T> query,
  ActiveFilter filter,
) =>
    switch (filter) {
      ActiveFilter.active => query.not('is_active', 'is', false),
      ActiveFilter.inactive => query.eq('is_active', false),
      ActiveFilter.all => query,
    };

/// Narrows a `visitor_sessions` [query] to sessions active at [now]: the
/// query form of `VisitorSessionModel.isActiveAt`. Change both together.
PostgrestFilterBuilder<T> applyActiveVisitorFilter<T>(
  PostgrestFilterBuilder<T> query,
  DateTime now,
) =>
    query
        .not('is_expired', 'is', true)
        .gt('expires_at', now.toUtc().toIso8601String());

/// Narrows [query] to [level], or leaves it alone when null. A row with no
/// value counts as the default, as it does everywhere else.
PostgrestFilterBuilder<T> applyAccessFilter<T>(
  PostgrestFilterBuilder<T> query,
  String? level,
) {
  if (level == null) return query;
  return level == kDefaultAccessLevel
      ? query.or('access_level.eq.$level,access_level.is.null')
      : query.eq('access_level', level);
}

/// True when [e] means [column] doesn't exist yet.
bool isMissingColumn(Object e, String column) =>
    e is PostgrestException &&
    (e.code == '42703' || e.code == 'PGRST204') &&
    e.message.contains(column);

/// Like [describeError], but says what to do about a missing `access_level`.
String describeAccessError(Object e) => isMissingColumn(e, 'access_level')
    ? 'The access_level column is missing. Run db/access_level.sql in the '
        'Supabase SQL editor.'
    : describeError(e);

/// Throws when a write changed nothing. Row Level Security blocks a write by
/// matching no rows, which PostgREST reports as success, so without this the
/// app would say "deleted" while the row stays.
void requireAffected(List<dynamic> rows, String what) {
  if (rows.isNotEmpty) return;
  throw RepositoryException(
      '$what changed nothing. The row may be gone, or Row Level Security is '
      'blocking this account.');
}

/// True when [e] means the table doesn't exist yet (its SQL hasn't been run).
/// A count is a HEAD request, whose failure has no body, so all it can report
/// is the status: 404, where a normal read gives PGRST205.
bool isMissingTable(Object e) =>
    e is PostgrestException &&
    (e.code == '42P01' || e.code == 'PGRST205' || e.code == '404');

/// The most useful message in [e] for showing to an admin.
String describeError(Object e) =>
    e is PostgrestException ? e.message : e.toString();
