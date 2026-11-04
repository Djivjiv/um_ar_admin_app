import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../domain/models/user_profile_model.dart';
import 'paged_query.dart';
import 'repository_exception.dart';

class UserRepository {
  final _client = SupabaseConfig.client;
  static const _table = 'user_profiles';

  Future<List<UserProfileModel>> getAll() async {
    try {
      final rows = await fetchAllPages((a, b) => _client
          .from(_table)
          .select()
          .order('created_at', ascending: false)
          .order('id')
          .range(a, b));
      return rows.map(UserProfileModel.fromJson).toList();
    } catch (e) {
      throw RepositoryException('Failed to load users', e);
    }
  }

  /// Updates one account, failing clearly when nothing was changed.
  Future<UserProfileModel> _update(
    String id,
    Map<String, dynamic> values,
    String what,
  ) async {
    try {
      final rows =
          await _client.from(_table).update(values).eq('id', id).select();
      requireAffected(rows, what);
      return UserProfileModel.fromJson(rows.first);
    } on RepositoryException {
      rethrow;
    } on PostgrestException catch (e) {
      throw RepositoryException('$what failed: ${e.message}', e);
    } catch (e) {
      throw RepositoryException('$what failed', e);
    }
  }

  Future<UserProfileModel> verifyUser(String id, {bool verified = true}) =>
      _update(id, {'is_verified': verified}, 'Updating verification');

  Future<UserProfileModel> suspendUser(String id, {bool suspended = true}) =>
      _update(id, {'is_active': !suspended}, 'Updating account status');

  /// Accepts a pending non-student account.
  Future<UserProfileModel> approveUser(String id) =>
      _update(id, {'is_verified': true}, 'Approving the account');

  /// Turns down a pending account: unverified and inactive, so it leaves the
  /// pending list. Reactivating it puts it back there.
  Future<UserProfileModel> rejectUser(String id) => _update(
      id, {'is_verified': false, 'is_active': false}, 'Rejecting the account');

  /// Sets the account's role. The Users screen checks `roleChangeBlocker`
  /// first; db/user_roles.sql enforces the same rules in the database.
  Future<UserProfileModel> setRole(String id, String role) async {
    if (!kUserRoles.contains(role)) {
      throw RepositoryException('Unknown role "$role"');
    }
    return _update(id, {'role': role}, 'Changing the role');
  }
}
