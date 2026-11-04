import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../core/utils/parse_utils.dart';
import '../../domain/models/facility_model.dart';
import 'indoor_link_cleanup.dart';
import 'paged_query.dart';
import 'repository_exception.dart';

class FacilityRepository {
  final _client = SupabaseConfig.client;
  static const _table = 'facilities';
  static const _detailsTable = 'facility_details';

  static const _joinedSelect = '*, buildings(id, name), '
      'facility_details(id, office_hours, contact_number, services, '
      'payment_method, instructions)';

  String _describe(Object e) => describeAccessError(e);

  /// Lightweight fetch used by the floor-plan editor's "link to room/facility"
  /// dropdown — do not change its shape without checking that screen. Only
  /// active facilities, so nothing inactive can be linked.
  Future<List<FacilityModel>> getByBuilding(int buildingId) async {
    try {
      final rows = await fetchAllPages((a, b) => _client
          .from(_table)
          .select('id, roomname, room_number, building_id, floor, is_active')
          .eq('building_id', buildingId)
          .not('is_active', 'is', false)
          .order('floor')
          .order('room_number')
          .order('id')
          .range(a, b));
      return rows.map(FacilityModel.fromJson).toList();
    } catch (e) {
      throw RepositoryException(
          'Failed to load facilities for building: ${_describe(e)}', e);
    }
  }

  /// Full list for the Facilities screen: joins the building name and the
  /// one-to-one facility_details row, with optional server-side filters.
  /// Active facilities unless [status] says otherwise.
  ///
  /// There is no retry without the join: a list missing its details looks
  /// complete, and saving a row from it would blank those details.
  Future<List<FacilityModel>> getAll({
    int? buildingId,
    String? category,
    String? search,
    ActiveFilter status = ActiveFilter.active,
    String? accessLevel,
  }) async {
    try {
      final rows = await fetchAllPages((a, b) {
        var query = applyAccessFilter(
            applyActiveFilter(
                _client.from(_table).select(_joinedSelect), status),
            accessLevel);
        if (buildingId != null) {
          query = query.eq('building_id', buildingId);
        }
        if (category != null && category.isNotEmpty) {
          query = query.eq('facility_categories', category);
        }
        if (search != null && search.trim().isNotEmpty) {
          query = query.ilike('roomname', '%${search.trim()}%');
        }
        return query.order('roomname').order('id').range(a, b);
      });
      return rows.map(FacilityModel.fromJson).toList();
    } catch (e) {
      throw RepositoryException(
          'Failed to load facilities: ${_describe(e)}', e);
    }
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
          'Failed to create facility: ${_describe(e)}', e);
    } catch (e) {
      throw RepositoryException(
          'Failed to create facility: ${_describe(e)}', e);
    }
  }

  /// How many indoor nodes point at this facility, to warn before
  /// deactivating it.
  Future<int> linkedNodeCount(int id) async {
    try {
      final rows = await linkedIndoorNodes(_client,
          table: LinkedTable.facilities, ids: [id]);
      return rows.length;
    } catch (e) {
      throw RepositoryException(
          'Failed to check linked indoor nodes: ${_describe(e)}', e);
    }
  }

  /// Saves the facility. Saving it inactive also unlinks indoor nodes
  /// pointing at it, so routes can't dead-end at a hidden facility.
  Future<void> update(int id, FacilityModel facility) async {
    if (facility.isActive) return _save(id, facility);
    return unlinkIndoorNodesThen(
      _client,
      table: LinkedTable.facilities,
      ids: [id],
      then: () => _save(id, facility),
    );
  }

  Future<void> _save(int id, FacilityModel facility) async {
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
          'Failed to update facility: ${_describe(e)}', e);
    } catch (e) {
      throw RepositoryException(
          'Failed to update facility: ${_describe(e)}', e);
    }
  }

  /// Unlinks indoor nodes pointing at the facility, then deletes the details
  /// row and the facility itself.
  Future<void> delete(int id) async {
    try {
      await unlinkIndoorNodesThen(
        _client,
        table: LinkedTable.facilities,
        ids: [id],
        then: () async {
          await _client.from(_detailsTable).delete().eq('facility_id', id);
          final rows =
              await _client.from(_table).delete().eq('id', id).select('id');
          requireAffected(rows, 'Deleting the facility');
        },
      );
    } on RepositoryException {
      rethrow;
    } on PostgrestException catch (e) {
      throw RepositoryException(
          'Failed to delete facility: ${e.message}', e);
    } catch (e) {
      throw RepositoryException(
          'Failed to delete facility: ${_describe(e)}', e);
    }
  }
}
