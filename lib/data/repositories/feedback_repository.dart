import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../core/utils/navigation_metrics.dart' show missingColumns;
import '../../domain/models/feedback_comment_model.dart';
import 'paged_query.dart';
import 'repository_exception.dart';

/// What a load of `feedback_comments` found. No rows here means "No data
/// yet"; a failed query throws instead, so it can't look like an empty table.
class FeedbackLoad {
  /// Newest first.
  final List<FeedbackCommentModel> rows;
  final bool tableExists;

  /// Of [kFeedbackColumns], those the table doesn't have.
  final List<String> missingColumns;

  const FeedbackLoad({
    this.rows = const [],
    this.tableExists = true,
    this.missingColumns = const [],
  });
}

class FeedbackRepository {
  final _client = SupabaseConfig.client;
  static const _table = 'feedback_comments';

  /// Comments with `from <= created_at < to`, or every comment without a
  /// range. `select *` so a missing optional column can't fail the request;
  /// the model then keeps only what may be shown.
  Future<FeedbackLoad> getComments({DateTime? from, DateTime? to}) async {
    try {
      final rows = await fetchAllPages((a, b) {
        var query = _client.from(_table).select();
        if (from != null) {
          query = query.gte('created_at', from.toUtc().toIso8601String());
        }
        if (to != null) {
          query = query.lt('created_at', to.toUtc().toIso8601String());
        }
        return query
            .order('created_at', ascending: false)
            .order('id')
            .range(a, b);
      });
      final missing = missingColumns(rows, kFeedbackColumns);
      if (missing.any(kFeedbackRequiredColumns.contains)) {
        return FeedbackLoad(missingColumns: missing);
      }
      return FeedbackLoad(
        rows: rows.map(FeedbackCommentModel.fromJson).toList(),
        missingColumns: missing,
      );
    } on PostgrestException catch (e) {
      if (isMissingTable(e)) return const FeedbackLoad(tableExists: false);
      if (e.code == '42703') return _missingColumnLoad(e);
      throw RepositoryException('Failed to load comments: ${e.message}', e);
    } catch (e) {
      throw RepositoryException(
          'Failed to load comments: ${describeError(e)}', e);
    }
  }

  /// The table lacks a column the query ordered or filtered on. One row, read
  /// with no order, shows which columns it does have.
  Future<FeedbackLoad> _missingColumnLoad(PostgrestException cause) async {
    try {
      final sample = await _client.from(_table).select().limit(1);
      return FeedbackLoad(missingColumns: missingColumns(sample, kFeedbackColumns));
    } catch (e) {
      throw RepositoryException(
          'Failed to load comments: ${cause.message}', cause);
    }
  }
}
