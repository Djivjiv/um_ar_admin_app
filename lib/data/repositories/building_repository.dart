import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../domain/models/building_model.dart';
import 'indoor_link_cleanup.dart';
import 'paged_query.dart';
import 'repository_exception.dart';

class BuildingRepository {
  final _client = SupabaseConfig.client;
  static const _table = 'buildings';
  static const _bucket = 'buildings';

  /// Active buildings unless [status] says otherwise. Pass
  /// [ActiveFilter.all] only for name lookups or an admin-chosen filter.
  Future<List<BuildingModel>> getAll({
    ActiveFilter status = ActiveFilter.active,
  }) async {
    try {
      final rows = await fetchAllPages((a, b) =>
          applyActiveFilter(_client.from(_table).select(), status)
              .order('name')
              .order('id')
              .range(a, b));
      final list = rows.map(BuildingModel.fromJson).toList();
      // Case-insensitive alphabetical order by name.
      list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    } catch (e) {
      throw RepositoryException('Failed to load buildings', e);
    }
  }

  Future<BuildingModel> create(BuildingModel building) async {
    try {
      final row = await _client
          .from(_table)
          .insert(building.toJson()..remove('id'))
          .select()
          .single();
      return BuildingModel.fromJson(row);
    } on PostgrestException catch (e) {
      throw RepositoryException('Failed to create building: ${e.message}', e);
    } catch (e) {
      throw RepositoryException('Failed to create building: $e', e);
    }
  }

  /// Saves the building. Saving it inactive also unlinks indoor nodes
  /// pointing at its rooms and facilities, as deactivating a room does: the
  /// user apps hide an inactive building, and routes would dead-end there.
  Future<BuildingModel> update(BuildingModel building) async {
    final id = building.id;
    if (id == null) {
      throw RepositoryException('Cannot update a building without an id');
    }
    // buildings.id is int8 — parse defensively in case it arrived as a String.
    final int idValue = int.parse(id.toString());
    if (building.isActive) return _save(building, idValue);
    return _unlinkChildrenThen(idValue, () => _save(building, idValue));
  }

  Future<BuildingModel> _save(BuildingModel building, int idValue) async {
    try {
      final payload = building.toJson()
        ..remove('id')
        ..remove('created_at')
        ..remove('updated_at');
      payload['updated_at'] = DateTime.now().toUtc().toIso8601String();

      final rows = await _client
          .from(_table)
          .update(payload)
          .eq('id', idValue)
          .select();

      final list = rows as List;
      if (list.isEmpty) {
        throw RepositoryException(
          'Update affected 0 rows for building id $idValue. The row may not '
          'exist, or Row Level Security is blocking updates for this account.',
        );
      }
      return BuildingModel.fromJson(list.first as Map<String, dynamic>);
    } on RepositoryException {
      rethrow;
    } on PostgrestException catch (e) {
      throw RepositoryException('Failed to update building: ${e.message}', e);
    } catch (e) {
      throw RepositoryException('Failed to update building: $e', e);
    }
  }

  /// Saves only the Outdoor AR marker columns (added by db/building_ar_columns.sql).
  /// An empty [arLabel] is stored as null.
  Future<BuildingModel> updateArSettings(
    int id, {
    required String arEmoji,
    required String? arLabel,
    required double arArrivalRadiusM,
  }) async {
    try {
      final rows = await _client
          .from(_table)
          .update({
            'ar_emoji': arEmoji,
            'ar_label': (arLabel == null || arLabel.isEmpty) ? null : arLabel,
            'ar_arrival_radius_m': arArrivalRadiusM,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id)
          .select();
      final list = rows as List;
      if (list.isEmpty) {
        throw RepositoryException(
          'Update affected 0 rows for building id $id. The row may not '
          'exist, or Row Level Security is blocking updates for this account.',
        );
      }
      return BuildingModel.fromJson(list.first as Map<String, dynamic>);
    } on RepositoryException {
      rethrow;
    } on PostgrestException catch (e) {
      throw RepositoryException('Failed to save AR settings: ${e.message}', e);
    } catch (e) {
      throw RepositoryException('Failed to save AR settings: $e', e);
    }
  }

  /// Ids of the building's rows in [table] (`rooms` or `facilities`).
  Future<List<int>> _idsIn(String table, int buildingId) async {
    final rows = await fetchAllPages((a, b) => _client
        .from(table)
        .select('id')
        .eq('building_id', buildingId)
        .order('id')
        .range(a, b));
    return [for (final r in rows) (r['id'] as num).toInt()];
  }

  /// Unlinks indoor nodes pointing at the building's rooms and facilities,
  /// then runs [then]. If [then] fails, the links are put back.
  Future<T> _unlinkChildrenThen<T>(
    int buildingId,
    Future<T> Function() then,
  ) async {
    final rooms = await _idsIn('rooms', buildingId);
    final facilities = await _idsIn('facilities', buildingId);
    return unlinkIndoorNodesThen(
      _client,
      table: LinkedTable.rooms,
      ids: rooms,
      then: () => unlinkIndoorNodesThen(
        _client,
        table: LinkedTable.facilities,
        ids: facilities,
        then: then,
      ),
    );
  }

  /// How many indoor nodes point at the building's rooms and facilities, to
  /// warn before deactivating it.
  Future<int> linkedNodeCount(int id) async {
    try {
      final rooms = await linkedIndoorNodes(_client,
          table: LinkedTable.rooms, ids: await _idsIn('rooms', id));
      final facilities = await linkedIndoorNodes(_client,
          table: LinkedTable.facilities, ids: await _idsIn('facilities', id));
      return rooms.length + facilities.length;
    } catch (e) {
      throw RepositoryException('Failed to check linked indoor nodes', e);
    }
  }

  /// Deletes the building. Its rooms and facilities may go with it (or be
  /// orphaned), so indoor nodes pointing at them are unlinked first.
  Future<void> delete(int id) async {
    try {
      await _unlinkChildrenThen(id, () async {
        final rows =
            await _client.from(_table).delete().eq('id', id).select('id');
        requireAffected(rows, 'Deleting the building');
      });
    } on RepositoryException {
      rethrow;
    } on PostgrestException catch (e) {
      throw RepositoryException('Failed to delete building: ${e.message}', e);
    } catch (e) {
      throw RepositoryException('Failed to delete building', e);
    }
  }

  /// Uploads [bytes] to the `buildings` storage bucket and returns a public URL.
  Future<String> uploadImage(String fileName, Uint8List bytes) async {
    try {
      final path =
          '${DateTime.now().millisecondsSinceEpoch}_$fileName';
      await _client.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      return _client.storage.from(_bucket).getPublicUrl(path);
    } catch (e) {
      throw RepositoryException('Failed to upload building image', e);
    }
  }
}
