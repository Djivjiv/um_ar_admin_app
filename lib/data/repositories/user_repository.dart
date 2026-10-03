import '../../core/config/supabase_config.dart';
import '../../domain/models/navigation_session_model.dart';
import '../../domain/models/user_profile_model.dart';
import 'repository_exception.dart';

class UserRepository {
  final _client = SupabaseConfig.client;
  static const _table = 'user_profiles';
  static const _navTable = 'navigation_sessions';

  Future<List<UserProfileModel>> getAll() async {
    try {
      final rows = await _client
          .from(_table)
          .select()
          .order('created_at', ascending: false);
      return (rows as List)
          .map((e) => UserProfileModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw RepositoryException('Failed to load users', e);
    }
  }

  Future<UserProfileModel> verifyUser(String id, {bool verified = true}) async {
    try {
      final row = await _client
          .from(_table)
          .update({'is_verified': verified})
          .eq('id', id)
          .select()
          .single();
      return UserProfileModel.fromJson(row);
    } catch (e) {
      throw RepositoryException('Failed to verify user', e);
    }
  }

  Future<UserProfileModel> suspendUser(String id, {bool suspended = true}) async {
    try {
      final row = await _client
          .from(_table)
          .update({'is_active': !suspended})
          .eq('id', id)
          .select()
          .single();
      return UserProfileModel.fromJson(row);
    } catch (e) {
      throw RepositoryException('Failed to suspend user', e);
    }
  }

  Future<void> deleteUser(String id) async {
    try {
      await _client.from(_table).delete().eq('id', id);
    } catch (e) {
      throw RepositoryException('Failed to delete user', e);
    }
  }

  Future<List<NavigationSessionModel>> getNavigationHistory(String userId) async {
    try {
      final rows = await _client
          .from(_navTable)
          .select()
          .eq('user_id', userId)
          .order('started_at', ascending: false);
      return (rows as List)
          .map((e) =>
              NavigationSessionModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw RepositoryException('Failed to load navigation history', e);
    }
  }
}
