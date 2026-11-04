import '../../core/config/supabase_config.dart';
import '../../domain/models/facility_content_model.dart';
import 'paged_query.dart';
import 'repository_exception.dart';

class ContentRepository {
  final _client = SupabaseConfig.client;
  static const _table = 'facility_content';

  Future<List<FacilityContentModel>> getAll() async {
    try {
      final rows = await fetchAllPages((a, b) => _client
          .from(_table)
          .select()
          .order('created_at', ascending: false)
          .order('id')
          .range(a, b));
      return rows.map(FacilityContentModel.fromJson).toList();
    } catch (e) {
      throw RepositoryException('Failed to load facility content', e);
    }
  }

  Future<List<FacilityContentModel>> getByBuilding(int buildingId) async {
    try {
      final rows = await fetchAllPages((a, b) => _client
          .from(_table)
          .select()
          .eq('building_id', buildingId)
          .order('created_at', ascending: false)
          .order('id')
          .range(a, b));
      return rows.map(FacilityContentModel.fromJson).toList();
    } catch (e) {
      throw RepositoryException('Failed to load content for building', e);
    }
  }

  Future<FacilityContentModel> create(FacilityContentModel content) async {
    try {
      final row = await _client
          .from(_table)
          .insert(content.toJson()..remove('id'))
          .select()
          .single();
      return FacilityContentModel.fromJson(row);
    } catch (e) {
      throw RepositoryException('Failed to create content', e);
    }
  }

  Future<FacilityContentModel> update(FacilityContentModel content) async {
    try {
      if (content.id == null) {
        throw RepositoryException('Cannot update content without an id');
      }
      final payload = content.toJson()..remove('id');
      payload['updated_at'] = DateTime.now().toUtc().toIso8601String();
      final row = await _client
          .from(_table)
          .update(payload)
          .eq('id', content.id!)
          .select()
          .single();
      return FacilityContentModel.fromJson(row);
    } catch (e) {
      if (e is RepositoryException) rethrow;
      throw RepositoryException('Failed to update content', e);
    }
  }

  Future<void> delete(String id) async {
    try {
      final rows =
          await _client.from(_table).delete().eq('id', id).select('id');
      requireAffected(rows, 'Deleting the content');
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException('Failed to delete content', e);
    }
  }

  Future<FacilityContentModel> toggleActive(String id, bool isActive) async {
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
      return FacilityContentModel.fromJson(row);
    } catch (e) {
      throw RepositoryException('Failed to toggle content status', e);
    }
  }
}
