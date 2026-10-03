import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../domain/models/building_model.dart';
import 'repository_exception.dart';

class BuildingRepository {
  final _client = SupabaseConfig.client;
  static const _table = 'buildings';
  static const _bucket = 'buildings';

  Future<List<BuildingModel>> getAll() async {
    try {
      final rows = await _client.from(_table).select().order('name');
      final list = (rows as List)
          .map((e) => BuildingModel.fromJson(e as Map<String, dynamic>))
          .toList();
      // Case-insensitive alphabetical order by name.
      list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    } catch (e) {
      throw RepositoryException('Failed to load buildings', e);
    }
  }

  Future<BuildingModel> getById(int id) async {
    try {
      final row =
          await _client.from(_table).select().eq('id', id).single();
      return BuildingModel.fromJson(row);
    } catch (e) {
      throw RepositoryException('Failed to load building #$id', e);
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

  Future<BuildingModel> update(BuildingModel building) async {
    final id = building.id;
    if (id == null) {
      throw RepositoryException('Cannot update a building without an id');
    }
    // buildings.id is int8 — parse defensively in case it arrived as a String.
    final int idValue = int.parse(id.toString());

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

  Future<void> delete(int id) async {
    try {
      await _client.from(_table).delete().eq('id', id);
    } catch (e) {
      throw RepositoryException('Failed to delete building', e);
    }
  }

  Future<BuildingModel> toggleActive(int id, bool isActive) async {
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
      return BuildingModel.fromJson(row);
    } catch (e) {
      throw RepositoryException('Failed to toggle building status', e);
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
