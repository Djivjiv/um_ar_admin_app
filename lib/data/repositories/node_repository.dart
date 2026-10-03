import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../domain/models/outdoor_edge_model.dart';
import '../../domain/models/outdoor_node_model.dart';
import 'repository_exception.dart';

class NodeRepository {
  final _client = SupabaseConfig.client;
  static const _nodesTable = 'outdoor_nodes';
  static const _edgesTable = 'outdoor_edges';

  String _describe(Object e) =>
      e is PostgrestException ? e.message : e.toString();

  static const _nodeSelectWithBuilding = '*, buildings(id, name, short_name)';

  /// Fetches nodes from `outdoor_nodes` (active ones by default), joining the
  /// linked building's name.
  Future<List<OutdoorNodeModel>> getAllNodes({bool activeOnly = true}) async {
    try {
      List<dynamic> rows;
      try {
        rows = activeOnly
            ? await _client
                .from(_nodesTable)
                .select(_nodeSelectWithBuilding)
                .eq('is_active', true)
            : await _client.from(_nodesTable).select(_nodeSelectWithBuilding);
      } catch (embedErr) {
        // No FK relationship / column — fall back to a plain select.
        debugPrint('outdoor_nodes embedded select failed ($embedErr); '
            'retrying without buildings join');
        rows = activeOnly
            ? await _client.from(_nodesTable).select().eq('is_active', true)
            : await _client.from(_nodesTable).select();
      }

      // If the active filter returned nothing, the column may be null/false in
      // this DB — fall back to fetching everything so the map still populates.
      if (activeOnly && rows.isEmpty) {
        debugPrint('outdoor_nodes: 0 rows with is_active=true, refetching all');
        try {
          rows = await _client
              .from(_nodesTable)
              .select(_nodeSelectWithBuilding);
        } catch (_) {
          rows = await _client.from(_nodesTable).select();
        }
      }

      final nodes = rows
          .map((e) => OutdoorNodeModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final withCoords =
          nodes.where((n) => n.lat != null && n.lng != null).length;
      debugPrint(
          'Fetched ${nodes.length} nodes from Supabase ($withCoords with coords)');
      return nodes;
    } catch (e) {
      debugPrint('outdoor_nodes fetch failed: $e');
      throw RepositoryException(
          'Failed to load outdoor nodes: ${_describe(e)}', e);
    }
  }

  Future<List<OutdoorEdgeModel>> getAllEdges() async {
    try {
      final rows = await _client.from(_edgesTable).select();
      final edges = (rows as List)
          .map((e) => OutdoorEdgeModel.fromJson(e as Map<String, dynamic>))
          .toList();
      debugPrint('Fetched ${edges.length} edges from Supabase');
      return edges;
    } catch (e) {
      debugPrint('outdoor_edges fetch failed: $e');
      throw RepositoryException(
          'Failed to load outdoor edges: ${_describe(e)}', e);
    }
  }

  Future<OutdoorNodeModel> createNode(OutdoorNodeModel node) async {
    try {
      final row = await _client
          .from(_nodesTable)
          .insert(node.toJson())
          .select()
          .single();
      return OutdoorNodeModel.fromJson(row);
    } catch (e) {
      throw RepositoryException('Failed to create node: ${_describe(e)}', e);
    }
  }

  Future<OutdoorNodeModel> updateNode(OutdoorNodeModel node) async {
    try {
      final rows = await _client
          .from(_nodesTable)
          .update(node.toJson()..remove('id'))
          .eq('id', node.id.toString())
          .select();
      final list = rows as List;
      if (list.isEmpty) {
        throw RepositoryException(
            'Update affected 0 rows (node ${node.id} missing or blocked by RLS).');
      }
      return OutdoorNodeModel.fromJson(list.first as Map<String, dynamic>);
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException('Failed to update node: ${_describe(e)}', e);
    }
  }

  /// Deletes a node and every edge it participates in.
  Future<void> deleteNode(String id) async {
    try {
      await _client
          .from(_edgesTable)
          .delete()
          .or('from_node.eq.$id,to_node.eq.$id');
      await _client.from(_nodesTable).delete().eq('id', id.toString());
    } catch (e) {
      throw RepositoryException('Failed to delete node: ${_describe(e)}', e);
    }
  }

  Future<OutdoorEdgeModel> createEdge(OutdoorEdgeModel edge) async {
    try {
      final row = await _client
          .from(_edgesTable)
          .insert(edge.toJson()..remove('id'))
          .select()
          .single();
      return OutdoorEdgeModel.fromJson(row);
    } catch (e) {
      throw RepositoryException('Failed to create edge: ${_describe(e)}', e);
    }
  }

  Future<void> deleteEdge(String id) async {
    try {
      await _client.from(_edgesTable).delete().eq('id', id.toString());
    } catch (e) {
      throw RepositoryException('Failed to delete edge: ${_describe(e)}', e);
    }
  }

  /// Sets (or clears) the `indoor_node_id` link on an outdoor node — the other
  /// half of the outdoor↔indoor entrance connection.
  Future<void> setIndoorLink(String outdoorNodeId, String? indoorNodeId) async {
    try {
      await _client
          .from(_nodesTable)
          .update({'indoor_node_id': indoorNodeId})
          .eq('id', outdoorNodeId.toString());
    } catch (e) {
      throw RepositoryException(
          'Failed to link outdoor node: ${_describe(e)}', e);
    }
  }

  Future<List<OutdoorNodeModel>> getEntranceNodesForBuilding(
      int buildingId) async {
    try {
      final rows = await _client
          .from(_nodesTable)
          .select()
          .eq('building_id', buildingId)
          .eq('is_entrance', true);
      return (rows as List)
          .map((e) => OutdoorNodeModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // Column may not exist yet — degrade to empty rather than break.
      return const [];
    }
  }
}
