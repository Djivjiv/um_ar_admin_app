import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../domain/models/room_model.dart';
import 'repository_exception.dart';

class RoomRepository {
  final _client = SupabaseConfig.client;
  static const _table = 'rooms';

  Future<List<RoomModel>> getAll() async {
    try {
      final rows = await _client.from(_table).select().order('roomname');
      return (rows as List)
          .map((e) => RoomModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw RepositoryException('Failed to load rooms', e);
    }
  }

  Future<List<RoomModel>> getByBuilding(int buildingId) async {
    try {
      final rows = await _client
          .from(_table)
          .select()
          .eq('building_id', buildingId)
          .order('roomname');
      return (rows as List)
          .map((e) => RoomModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw RepositoryException('Failed to load rooms for building', e);
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
      throw RepositoryException('Failed to create room: ${e.message}', e);
    } catch (e) {
      throw RepositoryException('Failed to create room: $e', e);
    }
  }

  Future<RoomModel> update(RoomModel room) async {
    final id = room.id;
    if (id == null) {
      throw RepositoryException('Cannot update a room without an id');
    }
    // rooms.id is int8 — parse defensively in case it arrived as a String.
    final int idValue = int.parse(id.toString());

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
      throw RepositoryException('Failed to update room: ${e.message}', e);
    } catch (e) {
      throw RepositoryException('Failed to update room: $e', e);
    }
  }

  Future<void> delete(int id) async {
    try {
      await _client.from(_table).delete().eq('id', id);
    } catch (e) {
      throw RepositoryException('Failed to delete room', e);
    }
  }

  Future<RoomModel> toggleActive(int id, bool isActive) async {
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
      throw RepositoryException('Failed to toggle room status', e);
    }
  }
}
