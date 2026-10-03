import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../domain/models/kiosk_session_model.dart';
import 'repository_exception.dart';

class KioskRepository {
  final _client = SupabaseConfig.client;
  static const _table = 'kiosk_sessions';

  Future<List<KioskSessionModel>> getSessions() async {
    try {
      final rows =
          await _client.from(_table).select().order('started_at', ascending: false);
      return (rows as List)
          .map((e) => KioskSessionModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      // Table not created yet — degrade to an empty list rather than break
      // the whole users screen.
      if (e.code == '42P01' || e.code == 'PGRST205') return const [];
      throw RepositoryException('Failed to load kiosk sessions: ${e.message}', e);
    } catch (e) {
      throw RepositoryException('Failed to load kiosk sessions', e);
    }
  }
}
