import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../domain/models/outdoor_edge_model.dart';
import '../../domain/models/outdoor_node_model.dart';
import 'paged_query.dart';
import 'repository_exception.dart';

class NodeRepository {
  final _client = SupabaseConfig.client;
  static const _nodesTable = 'outdoor_nodes';
  static const _edgesTable = 'outdoor_edges';

  String _describe(Object e) =>
      e is PostgrestException ? e.message : e.toString();

  static const _nodeSelectWithBuilding = '*, buildings(id, name, short_name)';

  /// Every `outdoor_nodes` row (paged), optionally only active ones. A null
  /// `is_active` counts as active, as in [OutdoorNodeModel.fromJson].
  Future<List<Map<String, dynamic>>> _selectNodes(
      String columns, bool activeOnly) {
    return fetchAllPages((a, b) {
      var query = _client.from(_nodesTable).select(columns);
      if (activeOnly) query = query.not('is_active', 'is', false);
      return query.order('id').range(a, b);
    });
  }

  Future<List<OutdoorNodeModel>> getAllNodes({bool activeOnly = true}) async {
    try {
      List<Map<String, dynamic>> rows;
      try {
        rows = await _selectNodes(_nodeSelectWithBuilding, activeOnly);
      } catch (embedErr) {
        // No FK relationship / column — fall back to a plain select.
        debugPrint('outdoor_nodes embedded select failed ($embedErr); '
            'retrying without buildings join');
        rows = await _selectNodes('*', activeOnly);
      }

      final nodes = rows.map(OutdoorNodeModel.fromJson).toList();
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
      final rows = await fetchAllPages((a, b) =>
          _client.from(_edgesTable).select().order('id').range(a, b));
      final edges = rows.map(OutdoorEdgeModel.fromJson).toList();
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

  /// Deletes a node and every edge it participates in, and clears
  /// `outdoor_node_id` on any indoor node pointing at it. Those links are put
  /// back if the delete fails.
  Future<void> deleteNode(String id) async {
    try {
      final unlinked = await _client
          .from('indoor_nodes')
          .update({'outdoor_node_id': null})
          .eq('outdoor_node_id', id)
          .select('id');
      try {
        await _client
            .from(_edgesTable)
            .delete()
            .or('from_node.eq.$id,to_node.eq.$id');
        final rows = await _client
            .from(_nodesTable)
            .delete()
            .eq('id', id.toString())
            .select('id');
        requireAffected(rows, 'Deleting the node');
      } catch (_) {
        if (unlinked.isNotEmpty) {
          await _client
              .from('indoor_nodes')
              .update({'outdoor_node_id': id})
              .inFilter('id', [for (final r in unlinked) r['id'].toString()]);
        }
        rethrow;
      }
    } on RepositoryException {
      rethrow;
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
      final rows = await _client
          .from(_edgesTable)
          .delete()
          .eq('id', id.toString())
          .select('id');
      requireAffected(rows, 'Deleting the edge');
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException('Failed to delete edge: ${_describe(e)}', e);
    }
  }

  /// Sets (or clears) the `indoor_node_id` link on an outdoor node — the other
  /// half of the outdoor↔indoor entrance connection.
  Future<void> setIndoorLink(String outdoorNodeId, String? indoorNodeId) async {
    try {
      final rows = await _client
          .from(_nodesTable)
          .update({'indoor_node_id': indoorNodeId})
          .eq('id', outdoorNodeId.toString())
          .select('id');
      requireAffected(rows, 'Linking outdoor node $outdoorNodeId');
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException(
          'Failed to link outdoor node: ${_describe(e)}', e);
    }
  }

  Future<List<OutdoorNodeModel>> getEntranceNodesForBuilding(
      int buildingId) async {
    try {
      final rows = await fetchAllPages((a, b) => _client
          .from(_nodesTable)
          .select()
          .eq('building_id', buildingId)
          .eq('is_entrance', true)
          .order('id')
          .range(a, b));
      return rows.map(OutdoorNodeModel.fromJson).toList();
    } catch (e) {
      throw RepositoryException(
          'Failed to load entrance nodes: ${_describe(e)}', e);
    }
  }
}
