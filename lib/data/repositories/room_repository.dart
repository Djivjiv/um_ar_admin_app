import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../domain/models/room_model.dart';
import 'indoor_link_cleanup.dart';
import 'paged_query.dart';
import 'repository_exception.dart';

class RoomRepository {
  final _client = SupabaseConfig.client;
  static const _table = 'rooms';

  /// Active rooms unless [status] says otherwise; [accessLevel] narrows to
  /// one level.
  Future<List<RoomModel>> getAll({
    ActiveFilter status = ActiveFilter.active,
    String? accessLevel,
  }) async {
    try {
      final rows = await fetchAllPages((a, b) => applyAccessFilter(
              applyActiveFilter(_client.from(_table).select(), status),
              accessLevel)
          .order('roomname')
          .order('id')
          .range(a, b));
      return rows.map(RoomModel.fromJson).toList();
    } catch (e) {
      throw RepositoryException(
          'Failed to load rooms: ${describeAccessError(e)}', e);
    }
  }

  /// Active rooms of the building unless [status] says otherwise.
  Future<List<RoomModel>> getByBuilding(
    int buildingId, {
    ActiveFilter status = ActiveFilter.active,
    String? accessLevel,
  }) async {
    try {
      final rows = await fetchAllPages((a, b) => applyAccessFilter(
              applyActiveFilter(
                  _client.from(_table).select().eq('building_id', buildingId),
                  status),
              accessLevel)
          .order('roomname')
          .order('id')
          .range(a, b));
      return rows.map(RoomModel.fromJson).toList();
    } catch (e) {
      throw RepositoryException(
          'Failed to load rooms for building: ${describeAccessError(e)}', e);
    }
  }

  Future<RoomModel> create(RoomModel room) async {
    try {
      final row = await _client
          .from(_table)
          .insert(room.toJson()..remove('id'))
          .select()
          .single();
      return RoomModel.fromJson(row);
    } on PostgrestException catch (e) {
      throw RepositoryException(
          'Failed to create room: ${describeAccessError(e)}', e);
    } catch (e) {
      throw RepositoryException('Failed to create room: $e', e);
    }
  }

  /// How many indoor nodes point at this room, to warn before deactivating.
  Future<int> linkedNodeCount(int id) async {
    try {
      final rows = await linkedIndoorNodes(_client,
          table: LinkedTable.rooms, ids: [id]);
      return rows.length;
    } catch (e) {
      throw RepositoryException('Failed to check linked indoor nodes', e);
    }
  }

  /// Saves the room. Saving it inactive also unlinks indoor nodes pointing
  /// at it, as the user apps hide those rooms and routes would dead-end.
  Future<RoomModel> update(RoomModel room) async {
    final id = room.id;
    if (id == null) {
      throw RepositoryException('Cannot update a room without an id');
    }
    // rooms.id is int8 — parse defensively in case it arrived as a String.
    final int idValue = int.parse(id.toString());
    if (room.isActive) return _save(room, idValue);
    return unlinkIndoorNodesThen(
      _client,
      table: LinkedTable.rooms,
      ids: [idValue],
      then: () => _save(room, idValue),
    );
  }

  Future<RoomModel> _save(RoomModel room, int idValue) async {
    try {
      final payload = room.toJson()
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
          'Update affected 0 rows for room id $idValue. The row may not exist, '
          'or Row Level Security is blocking updates for this account.',
        );
      }
      return RoomModel.fromJson(list.first as Map<String, dynamic>);
    } on RepositoryException {
      rethrow;
    } on PostgrestException catch (e) {
      throw RepositoryException(
          'Failed to update room: ${describeAccessError(e)}', e);
    } catch (e) {
      throw RepositoryException('Failed to update room: $e', e);
    }
  }

  /// Deletes the room and, in the same action, unlinks every indoor node
  /// whose `linked_room_id` points at it.
  Future<void> delete(int id) async {
    try {
      await unlinkIndoorNodesThen(
        _client,
        table: LinkedTable.rooms,
        ids: [id],
        then: () async {
          final rows =
              await _client.from(_table).delete().eq('id', id).select('id');
          requireAffected(rows, 'Deleting the room');
        },
      );
    } on RepositoryException {
      rethrow;
    } on PostgrestException catch (e) {
      throw RepositoryException('Failed to delete room: ${e.message}', e);
    } catch (e) {
      throw RepositoryException('Failed to delete room', e);
    }
  }

  /// Sets `is_active`. Deactivating also unlinks indoor nodes, as in [update].
  Future<RoomModel> toggleActive(int id, bool isActive) async {
    Future<RoomModel> write() async {
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
        return RoomModel.fromJson(row);
      } catch (e) {
        throw RepositoryException('Failed to change room status', e);
      }
    }

    if (isActive) return write();
    return unlinkIndoorNodesThen(
      _client,
      table: LinkedTable.rooms,
      ids: [id],
      then: write,
    );
  }
}
