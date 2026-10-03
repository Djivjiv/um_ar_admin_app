import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../domain/models/floor_plan_model.dart';
import '../../domain/models/indoor_edge_model.dart';
import '../../domain/models/indoor_node_model.dart';
import 'repository_exception.dart';

class FloorPlanRepository {
  final _client = SupabaseConfig.client;
  static const _table = 'building_floors';
  static const _bucket = 'floorplans';
  static const _indoorNodesTable = 'indoor_nodes';
  static const _indoorEdgesTable = 'indoor_edges';

  /// Turns a Supabase/Postgrest/Storage error into a human-readable message.
  String _describe(Object e) {
    if (e is PostgrestException) return e.message;
    if (e is StorageException) return e.message;
    return e.toString();
  }

  Future<List<FloorPlanModel>> getAll() async {
    try {
      final rows = await _client
          .from(_table)
          .select()
          .order('building_id')
          .order('floor_number');
      return (rows as List)
          .map((e) => FloorPlanModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw RepositoryException('Failed to load floor plans', e);
    }
  }

  Future<List<FloorPlanModel>> getByBuilding(int buildingId) async {
    try {
      final rows = await _client
          .from(_table)
          .select()
          .eq('building_id', buildingId)
          .order('floor_number');
      return (rows as List)
          .map((e) => FloorPlanModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw RepositoryException('Failed to load floor plans for building', e);
    }
  }

  Future<FloorPlanModel> create(FloorPlanModel plan) async {
    try {
      final payload = plan.toJson()
        ..remove('id')
        ..remove('created_at');
      final row =
          await _client.from(_table).insert(payload).select().single();
      return FloorPlanModel.fromJson(row);
    } catch (e) {
      throw RepositoryException('Failed to save floor plan: ${_describe(e)}', e);
    }
  }

  Future<FloorPlanModel> update(FloorPlanModel plan) async {
    final id = plan.id;
    if (id == null) {
      throw RepositoryException('Cannot update a floor plan without an id');
    }
    try {
      final payload = plan.toJson()
        ..remove('id')
        ..remove('created_at');
      final rows = await _client
          .from(_table)
          .update(payload)
          .eq('id', int.parse(id.toString()))
          .select();
      final list = rows as List;
      if (list.isEmpty) {
        throw RepositoryException(
          'Update affected 0 rows for floor plan $id. The row may not exist, '
          'or Row Level Security is blocking updates for this account.',
        );
      }
      return FloorPlanModel.fromJson(list.first as Map<String, dynamic>);
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException(
          'Failed to save floor plan: ${_describe(e)}', e);
    }
  }

  Future<void> delete(int id) async {
    try {
      await _client.from(_table).delete().eq('id', id);
    } catch (e) {
      throw RepositoryException('Failed to delete floor plan', e);
    }
  }

  Future<String> uploadImage(String fileName, Uint8List bytes) async {
    try {
      final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = '${DateTime.now().millisecondsSinceEpoch}_$safeName';
      await _client.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: _contentTypeFor(safeName),
            ),
          );
      return _client.storage.from(_bucket).getPublicUrl(path);
    } catch (e) {
      throw RepositoryException(
          'Failed to upload floor plan image: ${_describe(e)}', e);
    }
  }

  /// Uploads to an exact storage path (e.g. `{buildingId}/floor_1_169...png`)
  /// instead of the auto-prefixed name used by [uploadImage]. Used by the
  /// GeoreferencingScreen so files land in a per-building folder.
  Future<String> uploadImageAtPath(String path, Uint8List bytes) async {
    try {
      await _client.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: _contentTypeFor(path),
            ),
          );
      return _client.storage.from(_bucket).getPublicUrl(path);
    } catch (e) {
      throw RepositoryException(
          'Failed to upload floor plan image: ${_describe(e)}', e);
    }
  }

  String _contentTypeFor(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  // ---- Indoor graph -------------------------------------------------------

  Future<List<IndoorNodeModel>> getIndoorNodes(int floorPlanId) async {
    try {
      final rows = await _client
          .from(_indoorNodesTable)
          .select()
          .eq('floor_plan_id', floorPlanId);
      return (rows as List)
          .map((e) => IndoorNodeModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw RepositoryException(
          'Failed to load indoor nodes: ${_describe(e)}', e);
    }
  }

  /// Every indoor node in a building (across all its floor plans) — used to
  /// verify that a stair/elevator group is linked on more than one floor.
  Future<List<IndoorNodeModel>> getIndoorNodesForBuilding(int buildingId) async {
    try {
      final rows = await _client
          .from(_indoorNodesTable)
          .select()
          .eq('building_id', buildingId);
      return (rows as List)
          .map((e) => IndoorNodeModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<IndoorEdgeModel>> getIndoorEdges(int floorPlanId) async {
    try {
      final rows = await _client
          .from(_indoorEdgesTable)
          .select()
          .eq('floor_plan_id', floorPlanId);
      return (rows as List)
          .map((e) => IndoorEdgeModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw RepositoryException(
          'Failed to load indoor edges: ${_describe(e)}', e);
    }
  }

  Future<IndoorNodeModel> createIndoorNode(IndoorNodeModel node) async {
    try {
      final row = await _client
          .from(_indoorNodesTable)
          .insert(node.toJson()..remove('created_at'))
          .select()
          .single();
      return IndoorNodeModel.fromJson(row);
    } catch (e) {
      throw RepositoryException('Failed to add node: ${_describe(e)}', e);
    }
  }

  Future<IndoorNodeModel> updateIndoorNode(IndoorNodeModel node) async {
    try {
      final row = await _client
          .from(_indoorNodesTable)
          .update(node.toJson()
            ..remove('id')
            ..remove('created_at'))
          .eq('id', node.id)
          .select()
          .single();
      return IndoorNodeModel.fromJson(row);
    } catch (e) {
      throw RepositoryException('Failed to update node: ${_describe(e)}', e);
    }
  }

  Future<void> deleteIndoorNode(String id) async {
    try {
      await _client
          .from(_indoorEdgesTable)
          .delete()
          .or('from_node.eq.$id,to_node.eq.$id');
      await _client.from(_indoorNodesTable).delete().eq('id', id);
    } catch (e) {
      throw RepositoryException('Failed to delete node: ${_describe(e)}', e);
    }
  }

  Future<IndoorEdgeModel> createIndoorEdge(IndoorEdgeModel edge) async {
    try {
      final row = await _client
          .from(_indoorEdgesTable)
          .insert(edge.toJson()..remove('id'))
          .select()
          .single();
      return IndoorEdgeModel.fromJson(row);
    } catch (e) {
      throw RepositoryException(
          'Failed to create indoor edge: ${_describe(e)}', e);
    }
  }

  Future<void> deleteIndoorEdge(String id) async {
    try {
      await _client.from(_indoorEdgesTable).delete().eq('id', id);
    } catch (e) {
      throw RepositoryException('Failed to delete indoor edge', e);
    }
  }
}
