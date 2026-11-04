import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../domain/models/outdoor_ar_edge_model.dart';
import '../../domain/models/outdoor_ar_node_model.dart';
import 'paged_query.dart';
import 'repository_exception.dart';

/// The independent Outdoor AR path network (`outdoor_ar_nodes` /
/// `outdoor_ar_edges`, see db/outdoor_ar_v2.sql). Never reads the campus
/// map's outdoor_nodes / outdoor_edges.
class OutdoorArRepository {
  final _client = SupabaseConfig.client;
  static const _nodesTable = 'outdoor_ar_nodes';
  static const _edgesTable = 'outdoor_ar_edges';

  String _describe(Object e) =>
      e is PostgrestException ? e.message : e.toString();

  /// Every row of [table], one page at a time, ordered by [orderBy] then
  /// `id` so pages don't overlap or skip rows.
  Future<List<Map<String, dynamic>>> _selectAll(
      String table, String orderBy) {
    return fetchAllPages((a, b) => _client
        .from(table)
        .select()
        .order(orderBy)
        .order('id')
        .range(a, b));
  }

  Future<List<OutdoorArNodeModel>> getNodes() async {
    try {
      final rows = await _selectAll(_nodesTable, 'created_at');
      debugPrint('Fetched ${rows.length} outdoor AR nodes');
      return rows.map(OutdoorArNodeModel.fromJson).toList();
    } catch (e) {
      debugPrint('outdoor_ar_nodes fetch failed: $e');
      throw RepositoryException(
          'Failed to load AR nodes: ${_describe(e)}', e);
    }
  }

  Future<List<OutdoorArEdgeModel>> getEdges() async {
    try {
      final rows = await _selectAll(_edgesTable, 'from_node');
      debugPrint('Fetched ${rows.length} outdoor AR edges');
      return rows.map(OutdoorArEdgeModel.fromJson).toList();
    } catch (e) {
      debugPrint('outdoor_ar_edges fetch failed: $e');
      throw RepositoryException(
          'Failed to load AR edges: ${_describe(e)}', e);
    }
  }

  Future<OutdoorArNodeModel> createNode(OutdoorArNodeModel node) async {
    try {
      final row = await _client
          .from(_nodesTable)
          .insert(node.toJson()..remove('id'))
          .select()
          .single();
      return OutdoorArNodeModel.fromJson(row);
    } catch (e) {
      throw RepositoryException('Failed to add AR node: ${_describe(e)}', e);
    }
  }

  Future<OutdoorArNodeModel> updateNode(OutdoorArNodeModel node) async {
    final id = node.id;
    if (id == null) {
      throw RepositoryException('Cannot update an AR node without an id');
    }
    try {
      final rows = await _client
          .from(_nodesTable)
          .update(node.toJson()..remove('id'))
          .eq('id', id)
          .select();
      if (rows.isEmpty) {
        throw RepositoryException(
            'Update affected 0 rows (AR node missing or blocked by RLS).');
      }
      return OutdoorArNodeModel.fromJson(rows.first);
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException(
          'Failed to update AR node: ${_describe(e)}', e);
    }
  }

  /// Deletes a node; its edges go with it (`on delete cascade`).
  Future<void> deleteNode(String id) async {
    try {
      final rows =
          await _client.from(_nodesTable).delete().eq('id', id).select('id');
      requireAffected(rows, 'Deleting the AR node');
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException(
          'Failed to delete AR node: ${_describe(e)}', e);
    }
  }

  Future<OutdoorArEdgeModel> createEdge(OutdoorArEdgeModel edge) async {
    try {
      final row = await _client
          .from(_edgesTable)
          .insert(edge.toJson()..remove('id'))
          .select()
          .single();
      return OutdoorArEdgeModel.fromJson(row);
    } catch (e) {
      throw RepositoryException('Failed to add AR edge: ${_describe(e)}', e);
    }
  }

  Future<void> updateEdgeWeight(String id, double weightM) async {
    try {
      final rows = await _client
          .from(_edgesTable)
          .update({'weight_m': weightM})
          .eq('id', id)
          .select('id');
      requireAffected(rows, 'Updating the AR edge length');
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException(
          'Failed to update AR edge length: ${_describe(e)}', e);
    }
  }

  Future<void> deleteEdge(String id) async {
    try {
      final rows =
          await _client.from(_edgesTable).delete().eq('id', id).select('id');
      requireAffected(rows, 'Deleting the AR edge');
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException(
          'Failed to delete AR edge: ${_describe(e)}', e);
    }
  }
}
