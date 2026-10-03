import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../core/utils/parse_utils.dart';
import '../../domain/models/facility_model.dart';
import 'repository_exception.dart';

class FacilityRepository {
  final _client = SupabaseConfig.client;
  static const _table = 'facilities';
  static const _detailsTable = 'facility_details';

  static const _joinedSelect = '*, buildings(id, name), '
      'facility_details(id, office_hours, contact_number, services, '
      'payment_method, instructions)';

  String _describe(Object e) {
    if (e is PostgrestException) return e.message;
    return e.toString();
  }

  /// Lightweight fetch used by the floor-plan editor's "link to room/facility"
  /// dropdown — do not change its shape without checking that screen.
  Future<List<FacilityModel>> getByBuilding(int buildingId) async {
    try {
      final rows = await _client
          .from(_table)
          .select('id, roomname, room_number, building_id, floor')
          .eq('building_id', buildingId)
          .order('floor')
          .order('room_number');
      return (rows as List)
          .map((e) => FacilityModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Table may not exist / be readable — degrade to empty.
      return const [];
    }
  }

  /// Full list for the Facilities screen: joins the building name and the
  /// one-to-one facility_details row, with optional server-side filters.
  Future<List<FacilityModel>> getAll({
    int? buildingId,
    String? category,
    String? search,
  }) async {
    try {
      return await _fetch(
        select: _joinedSelect,
        buildingId: buildingId,
        category: category,
        search: search,
      );
    } on PostgrestException catch (e) {
      // The facility_details FK / table may not be set up yet — fall back to
      // just the facilities + building so the list still loads.
      try {
        return await _fetch(
          select: '*, buildings(id, name)',
          buildingId: buildingId,
          category: category,
          search: search,
        );
      } catch (_) {
        throw RepositoryException(
            'Failed to load facilities: ${e.message}', e);
      }
    } catch (e) {
      throw RepositoryException(
          'Failed to load facilities: ${_describe(e)}', e);
    }
  }

  Future<List<FacilityModel>> _fetch({
    required String select,
    int? buildingId,
    String? category,
    String? search,
  }) async {
    var query = _client.from(_table).select(select);
    if (buildingId != null) {
      query = query.eq('building_id', buildingId);
    }
    if (category != null && category.isNotEmpty) {
      query = query.eq('facility_categories', category);
    }
    if (search != null && search.trim().isNotEmpty) {
      query = query.ilike('roomname', '%${search.trim()}%');
    }
    final rows = await query.order('roomname');
    return (rows as List)
        .map((e) => FacilityModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Inserts the facility, then its details row. Returns the new facility id.
  Future<int> create(FacilityModel facility) async {
    try {
      final row = await _client
          .from(_table)
          .insert(facility.facilityJson())
          .select('id')
          .single();
      final id = parseInt(row['id']);
      if (id == null) {
        throw RepositoryException('Facility saved but no id was returned.');
      }
      await _client.from(_detailsTable).insert({
        'facility_id': id,
        ...facility.detailsJson(),
      });
      return id;
    } on RepositoryException {
      rethrow;
    } on PostgrestException catch (e) {
      throw RepositoryException(
          'Failed to create facility: ${e.message}', e);
    } catch (e) {
      throw RepositoryException(
          'Failed to create facility: ${_describe(e)}', e);
    }
  }

  Future<void> update(int id, FacilityModel facility) async {
    try {
      final rows = await _client
          .from(_table)
          .update(facility.facilityJson())
          .eq('id', id)
          .select('id');
      if ((rows as List).isEmpty) {
        throw RepositoryException(
            'Update affected 0 rows — facility $id is missing or blocked by RLS.');
      }
      // Older facilities may have no details row yet.
      final existing = await _client
          .from(_detailsTable)
          .select('id')
          .eq('facility_id', id)
          .maybeSingle();
      if (existing != null) {
        await _client
            .from(_detailsTable)
            .update(facility.detailsJson())
            .eq('facility_id', id);
      } else {
        await _client.from(_detailsTable).insert({
          'facility_id': id,
          ...facility.detailsJson(),
        });
      }
    } on RepositoryException {
      rethrow;
    } on PostgrestException catch (e) {
      throw RepositoryException(
          'Failed to update facility: ${e.message}', e);
    } catch (e) {
      throw RepositoryException(
          'Failed to update facility: ${_describe(e)}', e);
    }
  }

  /// Deletes the details row first, then the facility itself.
  Future<void> delete(int id) async {
    try {
      await _client.from(_detailsTable).delete().eq('facility_id', id);
      await _client.from(_table).delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw RepositoryException(
          'Failed to delete facility: ${e.message}', e);
    } catch (e) {
      throw RepositoryException(
          'Failed to delete facility: ${_describe(e)}', e);
    }
  }
}
