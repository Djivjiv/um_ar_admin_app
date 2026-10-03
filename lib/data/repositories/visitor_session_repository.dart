import '../../core/config/supabase_config.dart';
import '../../domain/models/navigation_session_model.dart';
import '../../domain/models/visitor_session_model.dart';
import 'repository_exception.dart';

class VisitorSessionRepository {
  final _client = SupabaseConfig.client;
  static const _table = 'visitor_sessions';
  static const _navTable = 'navigation_sessions';

  Future<List<VisitorSessionModel>> getAll() async {
    try {
      final rows = await _client
          .from(_table)
          .select()
          .order('started_at', ascending: false);
      return (rows as List)
          .map((e) => VisitorSessionModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw RepositoryException('Failed to load visitor sessions', e);
    }
  }

  Future<List<NavigationSessionModel>> getNavigationHistory(
      String visitorSessionId) async {
    try {
      final rows = await _client
          .from(_navTable)
          .select()
          .eq('visitor_session_id', visitorSessionId)
          .order('started_at', ascending: false);
      return (rows as List)
          .map((e) =>
              NavigationSessionModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw RepositoryException('Failed to load visitor navigation history', e);
    }
  }
}
