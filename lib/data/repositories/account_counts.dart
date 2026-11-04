import 'package:supabase_flutter/supabase_flutter.dart';

/// Which `user_profiles` accounts a count covers.
enum AccountGroup {
  /// Every active account.
  all,

  /// Active accounts with the student role.
  students,

  /// Active accounts with `is_verified` true.
  verified,
}

/// The one counting rule for accounts, used by the Dashboard and Analytics so
/// they can't drift apart: only active accounts count. A null `is_active`
/// counts as active, as in `is_admin()` and the models, so deactivated and
/// rejected accounts are the only ones left out.
PostgrestFilterBuilder<T> applyActiveAccountFilter<T>(
  PostgrestFilterBuilder<T> query,
  AccountGroup group,
) {
  final active = query.not('is_active', 'is', false);
  return switch (group) {
    AccountGroup.all => active,
    AccountGroup.students => active.ilike('role', 'student'),
    AccountGroup.verified => active.eq('is_verified', true),
  };
}

/// Exact count of the active accounts in [group]; no rows are downloaded.
Future<int> countActiveAccounts(
  SupabaseClient client, [
  AccountGroup group = AccountGroup.all,
]) async =>
    await applyActiveAccountFilter(
        client.from('user_profiles').count(), group);
