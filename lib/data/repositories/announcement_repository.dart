import '../../core/config/supabase_config.dart';
import '../../domain/models/announcement_model.dart';
import 'repository_exception.dart';

class AnnouncementRepository {
  final _client = SupabaseConfig.client;
  static const _table = 'announcements';

  Future<List<AnnouncementModel>> getAll() async {
    try {
      final rows = await _client
          .from(_table)
          .select()
          .order('created_at', ascending: false);
      return (rows as List)
          .map((e) => AnnouncementModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw RepositoryException('Failed to load announcements', e);
    }
  }

  Future<AnnouncementModel> create(AnnouncementModel announcement) async {
    try {
      final row = await _client
          .from(_table)
          .insert(announcement.toJson()..remove('id'))
          .select()
          .single();
      return AnnouncementModel.fromJson(row);
    } catch (e) {
      throw RepositoryException('Failed to create announcement', e);
    }
  }

  Future<AnnouncementModel> update(AnnouncementModel announcement) async {
    try {
      if (announcement.id == null) {
        throw RepositoryException('Cannot update announcement without an id');
      }
      final payload = announcement.toJson()..remove('id');
      payload['updated_at'] = DateTime.now().toUtc().toIso8601String();
      final row = await _client
          .from(_table)
          .update(payload)
          .eq('id', announcement.id!)
          .select()
          .single();
      return AnnouncementModel.fromJson(row);
    } catch (e) {
      if (e is RepositoryException) rethrow;
      throw RepositoryException('Failed to update announcement', e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.from(_table).delete().eq('id', id);
    } catch (e) {
      throw RepositoryException('Failed to delete announcement', e);
    }
  }

  Future<AnnouncementModel> toggleActive(String id, bool isActive) async {
    try {
      final row = await _client
          .from(_table)
          .update({
            'is_active': isActive,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id)
          .select()
          .single();
      return AnnouncementModel.fromJson(row);
    } catch (e) {
      throw RepositoryException('Failed to toggle announcement status', e);
    }
  }

  /// Deactivates announcements whose `expires_at` is in the past.
  Future<int> expireOld() async {
    try {
      final rows = await _client
          .from(_table)
          .update({
            'is_active': false,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .lt('expires_at', DateTime.now().toUtc().toIso8601String())
          .eq('is_active', true)
          .select();
      return (rows as List).length;
    } catch (e) {
      throw RepositoryException('Failed to expire old announcements', e);
    }
  }
}
