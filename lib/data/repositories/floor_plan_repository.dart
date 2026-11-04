import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../core/utils/floor_scale.dart';
import '../../domain/models/floor_plan_model.dart';
import '../../domain/models/indoor_edge_model.dart';
import '../../domain/models/indoor_node_model.dart';
import 'paged_query.dart';
import 'repository_exception.dart';

/// One side of the entrance links on a floor: the table, the link column, and
/// the rows as read before clearing.
typedef _EntranceLinks = (
  String table,
  String column,
  List<Map<String, dynamic>> rows,
);

class FloorPlanRepository {
  final _client = SupabaseConfig.client;
  static const _table = 'building_floors';
  static const _bucket = 'floorplans';
  static const _indoorNodesTable = 'indoor_nodes';
  static const _indoorEdgesTable = 'indoor_edges';
  static const _outdoorNodesTable = 'outdoor_nodes';

  /// Turns a Supabase/Postgrest/Storage error into a human-readable message.
  String _describe(Object e) {
    if (e is PostgrestException && e.message.contains('meters_per_pixel')) {
      return 'The building_floors.meters_per_pixel column is missing. '
          'Run db/floor_plan_pixel_scale.sql in the Supabase SQL editor.';
    }
    if (e is PostgrestException) return e.message;
    if (e is StorageException) return e.message;
    return e.toString();
  }

  Future<List<FloorPlanModel>> getAll() async {
    try {
      final rows = await fetchAllPages((a, b) => _client
          .from(_table)
          .select()
          .order('building_id')
          .order('floor_number')
          .order('id')
          .range(a, b));
      return rows.map(FloorPlanModel.fromJson).toList();
    } catch (e) {
      throw RepositoryException('Failed to load floor plans', e);
    }
  }

  Future<List<FloorPlanModel>> getByBuilding(int buildingId) async {
    try {
      final rows = await fetchAllPages((a, b) => _client
          .from(_table)
          .select()
          .eq('building_id', buildingId)
          .order('floor_number')
          .order('id')
          .range(a, b));
      return rows.map(FloorPlanModel.fromJson).toList();
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

  /// Writes [metersPerPixel] to the floor plan, then reads the row back and
  /// returns it, so the screen shows what the database really holds. Only
  /// this column is written, so a stale copy of the plan can't undo anything.
  Future<FloorPlanModel> saveScale(int id, double metersPerPixel) async {
    try {
      final written = await _client
          .from(_table)
          .update({'meters_per_pixel': metersPerPixel})
          .eq('id', id)
          .select('id');
      requireAffected(written, 'Saving the scale for floor plan $id');

      final row = await _client.from(_table).select().eq('id', id).single();
      final saved = FloorPlanModel.fromJson(row);
      if (saved.metersPerPixel != metersPerPixel) {
        throw RepositoryException(
          'The scale was sent, but floor plan $id reloaded with '
          '${saved.scaleLabel} instead of $metersPerPixel m/px. A database '
          'trigger or another admin may have changed it.',
        );
      }
      return saved;
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException('Failed to save scale: ${_describe(e)}', e);
    }
  }

  /// Deletes the floor plan and clears the entrance links to its nodes on
  /// both sides, as deleting a single node does. Supabase has no client-side
  /// transactions: if any later step fails, whatever was cleared is put back
  /// and the floor plan stays.
  Future<void> delete(int id) async {
    try {
      final nodes = await _selectAll(_indoorNodesTable, 'id, outdoor_node_id',
          column: 'floor_plan_id', value: id);
      final outdoorLinks = await _outdoorNodesPointingAt(
          [for (final n in nodes) n['id'].toString()]);
      final indoorLinks = [
        for (final n in nodes)
          if ((n['outdoor_node_id']?.toString() ?? '').isNotEmpty) n,
      ];

      final outdoor = (_outdoorNodesTable, 'indoor_node_id', outdoorLinks);
      final indoor = (_indoorNodesTable, 'outdoor_node_id', indoorLinks);

      await _clearLink(outdoor);
      final cleared = [outdoor];
      try {
        await _clearLink(indoor);
        cleared.add(indoor);
        final rows =
            await _client.from(_table).delete().eq('id', id).select('id');
        requireAffected(rows, 'Deleting the floor plan');
      } catch (e) {
        await _restoreLinks(cleared);
        if (e is RepositoryException) rethrow;
        throw RepositoryException(
            'Nothing was deleted, and the entrance links were put back: '
            '${_describe(e)}',
            e);
      }
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException(
          'Failed to delete floor plan: ${_describe(e)}', e);
    }
  }

  /// `id` and `indoor_node_id` of outdoor nodes pointing at [indoorIds]. In
  /// batches, as ids go in the URL and a floor can have hundreds of nodes.
  Future<List<Map<String, dynamic>>> _outdoorNodesPointingAt(
      List<String> indoorIds) async {
    const batch = 200;
    final found = <Map<String, dynamic>>[];
    for (var i = 0; i < indoorIds.length; i += batch) {
      final ids = indoorIds.sublist(
          i, i + batch < indoorIds.length ? i + batch : indoorIds.length);
      found.addAll(await _client
          .from(_outdoorNodesTable)
          .select('id, indoor_node_id')
          .inFilter('indoor_node_id', ids));
    }
    return found;
  }

  /// Sets the link column to null on [links]' rows, checking every row really
  /// changed. A partial clear is put back, so a failure here changes nothing.
  Future<void> _clearLink(_EntranceLinks links) async {
    final (table, column, rows) = links;
    if (rows.isEmpty) return;
    final cleared = await _client
        .from(table)
        .update({column: null})
        .inFilter('id', [for (final r in rows) r['id'].toString()])
        .select('id');
    if (cleared.length < rows.length) {
      await _restoreLinks([links]);
      throw RepositoryException(
          'Nothing was deleted: only ${cleared.length} of ${rows.length} '
          'entrance links on $table could be cleared, so they were put back. '
          'Row Level Security may be blocking this account.');
    }
  }

  /// Writes each row's old link value back, as read before clearing. Tries
  /// every row, so one failure doesn't leave the others cleared, then names
  /// the ones that are still cleared.
  Future<void> _restoreLinks(List<_EntranceLinks> cleared) async {
    final notRestored = <String>[];
    Object? cause;
    for (final (table, column, rows) in cleared) {
      for (final r in rows) {
        try {
          await _client
              .from(table)
              .update({column: r[column]})
              .eq('id', r['id'].toString());
        } catch (e) {
          cause = e;
          notRestored.add('${r['id']} ($table)');
        }
      }
    }
    if (notRestored.isEmpty) return;
    throw RepositoryException(
        'Nothing was deleted, but these entrance links could not be put back: '
        '${notRestored.join(', ')}. Re-link them in the campus map editor.',
        cause);
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
  /// Floor Plans upload so files land in a per-building folder.
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

  /// Every row of [table] (paged, ordered by `id`), optionally only rows
  /// where [column] equals [value].
  Future<List<Map<String, dynamic>>> _selectAll(
    String table,
    String columns, {
    String? column,
    Object? value,
  }) {
    return fetchAllPages((a, b) {
      var query = _client.from(table).select(columns);
      if (column != null) query = query.eq(column, value!);
      return query.order('id').range(a, b);
    });
  }

  /// Node/edge counts and routing health for every floor plan, keyed by
  /// floor plan id.
  Future<Map<int, FloorGraphStats>> getGraphStats() async {
    try {
      final results = await Future.wait([
        _selectAll(_indoorNodesTable,
            'id, floor_plan_id, is_navigable, cross_building_ref'),
        _selectAll(_indoorEdgesTable, 'id, from_node, to_node, floor_plan_id'),
      ]);
      final navByPlan = <int, Set<String>>{};
      final nodeCount = <int, int>{};
      final refsByPlan = <int, List<String>>{};
      final refTotals = <String, int>{};
      for (final row in results[0] as List) {
        final planId = (row['floor_plan_id'] as num?)?.toInt();
        if (planId == null) continue;
        nodeCount[planId] = (nodeCount[planId] ?? 0) + 1;
        if (row['is_navigable'] != false) {
          (navByPlan[planId] ??= {}).add(row['id'].toString());
        }
        final ref = row['cross_building_ref']?.toString().trim() ?? '';
        if (ref.isNotEmpty) {
          (refsByPlan[planId] ??= []).add(ref);
          refTotals[ref] = (refTotals[ref] ?? 0) + 1;
        }
      }
      // A ref is "linked" once some other node carries the same ref.
      int linked(int planId) =>
          (refsByPlan[planId] ?? const []).where((r) => refTotals[r]! > 1).length;
      final edgesByPlan = <int, List<(String, String)>>{};
      for (final row in results[1] as List) {
        final planId = (row['floor_plan_id'] as num?)?.toInt();
        if (planId == null) continue;
        (edgesByPlan[planId] ??= [])
            .add((row['from_node'].toString(), row['to_node'].toString()));
      }
      return {
        for (final planId in {...nodeCount.keys, ...edgesByPlan.keys})
          planId: FloorGraphStats.compute(
            nodeCount: nodeCount[planId] ?? 0,
            navigableIds: navByPlan[planId] ?? const {},
            edges: edgesByPlan[planId] ?? const [],
            crossBuildingLinks: linked(planId),
            crossBuildingPending:
                (refsByPlan[planId]?.length ?? 0) - linked(planId),
          ),
      };
    } catch (e) {
      throw RepositoryException(
          'Failed to load node/edge counts: ${_describe(e)}', e);
    }
  }

  // ---- Cross-building links ----------------------------------------------

  /// Every node (any building) that has a `cross_building_ref`.
  Future<List<IndoorNodeModel>> getCrossBuildingNodes() async {
    try {
      final rows = await fetchAllPages((a, b) => _client
          .from(_indoorNodesTable)
          .select()
          .not('cross_building_ref', 'is', null)
          .order('id')
          .range(a, b));
      return rows
          .map(IndoorNodeModel.fromJson)
          .where((n) => (n.crossBuildingRef ?? '').isNotEmpty)
          .toList();
    } catch (e) {
      throw RepositoryException(
          'Failed to load cross-building links: ${_describe(e)}', e);
    }
  }

  /// Other nodes carrying [ref], excluding the node [excludeId].
  Future<List<IndoorNodeModel>> findCrossBuildingPartners(
    String ref, {
    String? excludeId,
  }) async {
    try {
      final rows = await fetchAllPages((a, b) {
        var query = _client
            .from(_indoorNodesTable)
            .select()
            .eq('cross_building_ref', ref);
        if (excludeId != null) query = query.neq('id', excludeId);
        return query.order('id').range(a, b);
      });
      return rows.map(IndoorNodeModel.fromJson).toList();
    } catch (e) {
      throw RepositoryException(
          'Failed to search for connected node: ${_describe(e)}', e);
    }
  }

  String _betweenFilter(String a, String b) =>
      'and(from_node.eq.$a,to_node.eq.$b),and(from_node.eq.$b,to_node.eq.$a)';

  /// True if an edge joins [a] and [b] in either direction.
  Future<bool> edgeExistsBetween(String a, String b) async {
    try {
      final rows = await _client
          .from(_indoorEdgesTable)
          .select('id')
          .or(_betweenFilter(a, b))
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (e) {
      throw RepositoryException(
          'Failed to check existing edges: ${_describe(e)}', e);
    }
  }

  /// Removes every edge joining [a] and [b] (either direction).
  Future<void> deleteEdgesBetween(String a, String b) async {
    try {
      await _client.from(_indoorEdgesTable).delete().or(_betweenFilter(a, b));
    } catch (e) {
      throw RepositoryException(
          'Failed to remove old cross-building edge: ${_describe(e)}', e);
    }
  }

  Future<List<IndoorNodeModel>> getIndoorNodes(int floorPlanId) async {
    try {
      final rows = await _selectAll(_indoorNodesTable, '*',
          column: 'floor_plan_id', value: floorPlanId);
      return rows.map(IndoorNodeModel.fromJson).toList();
    } catch (e) {
      throw RepositoryException(
          'Failed to load indoor nodes: ${_describe(e)}', e);
    }
  }

  /// Every indoor node in a building (across all its floor plans) — used to
  /// verify that a stair/elevator group is linked on more than one floor.
  Future<List<IndoorNodeModel>> getIndoorNodesForBuilding(int buildingId) async {
    try {
      final rows = await _selectAll(_indoorNodesTable, '*',
          column: 'building_id', value: buildingId);
      return rows.map(IndoorNodeModel.fromJson).toList();
    } catch (e) {
      throw RepositoryException(
          'Failed to load the building\'s stair links: ${_describe(e)}', e);
    }
  }

  Future<List<IndoorEdgeModel>> getIndoorEdges(int floorPlanId) async {
    try {
      final rows = await _selectAll(_indoorEdgesTable, '*',
          column: 'floor_plan_id', value: floorPlanId);
      return rows.map(IndoorEdgeModel.fromJson).toList();
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

  /// Saves dragged nodes and the new lengths of their edges. Only `x`, `y` and
  /// `weight` are written, so a stale copy can't undo anything. Supabase has
  /// no client-side transactions: if a write fails, the ones before it are
  /// put back.
  Future<void> saveNodeMoves(
    List<NodeMove> moves,
    List<EdgeLengthChange> edges,
  ) async {
    final undo = <(String, Future<void> Function())>[];
    try {
      for (final m in moves) {
        final rows = await _client
            .from(_indoorNodesTable)
            .update({'x': m.toX, 'y': m.toY})
            .eq('id', m.id)
            .select('id');
        requireAffected(rows, 'Moving node ${m.id}');
        undo.add(('node ${m.id}', () async {
          await _client
              .from(_indoorNodesTable)
              .update({'x': m.fromX, 'y': m.fromY})
              .eq('id', m.id);
        }));
      }
      for (final e in edges) {
        final rows = await _client
            .from(_indoorEdgesTable)
            .update({'weight': e.newWeight})
            .eq('id', e.id)
            .select('id');
        requireAffected(rows, 'Updating the length of edge ${e.id}');
        undo.add(('edge ${e.id}', () async {
          await _client
              .from(_indoorEdgesTable)
              .update({'weight': e.oldWeight})
              .eq('id', e.id);
        }));
      }
    } catch (e) {
      final notRestored = <String>[];
      for (final (what, restore) in undo.reversed) {
        try {
          await restore();
        } catch (_) {
          notRestored.add(what);
        }
      }
      final reason = e is RepositoryException ? e.message : _describe(e);
      throw RepositoryException(
          notRestored.isEmpty
              ? 'Nothing was moved, and any saved changes were put back: '
                  '$reason'
              : 'The move failed ($reason), and these could not be put back: '
                  '${notRestored.join(', ')}. Reload and check them.',
          e);
    }
  }

  /// Removes the room/facility link from the nodes [ids]; the nodes stay.
  Future<void> clearNodeLinks(List<String> ids) async {
    try {
      final rows = await _client
          .from(_indoorNodesTable)
          .update({'linked_room_id': null, 'linked_table': null})
          .inFilter('id', ids)
          .select('id');
      if (rows.length < ids.length) {
        throw RepositoryException(
          'Only ${rows.length} of ${ids.length} node links were cleared. '
          'Row Level Security may be blocking updates to indoor_nodes.',
        );
      }
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException(
          'Failed to clear node links: ${_describe(e)}', e);
    }
  }

  Future<void> deleteIndoorNode(String id) async {
    try {
      await _client
          .from(_indoorEdgesTable)
          .delete()
          .or('from_node.eq.$id,to_node.eq.$id');
      final rows = await _client
          .from(_indoorNodesTable)
          .delete()
          .eq('id', id)
          .select('id');
      requireAffected(rows, 'Deleting the node');
    } on RepositoryException {
      rethrow;
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
      final rows = await _client
          .from(_indoorEdgesTable)
          .delete()
          .eq('id', id)
          .select('id');
      requireAffected(rows, 'Deleting the edge');
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException('Failed to delete indoor edge', e);
    }
  }
}

/// Whether a floor's indoor graph can be used for routing.
enum RoutingStatus {
  /// No nodes placed yet.
  empty,

  /// Fewer than 2 navigable nodes, or no edges between them.
  notRoutable,

  /// Edges exist, but some navigable nodes can't be reached from the rest.
  partial,

  /// Every navigable node is reachable from every other.
  ready,
}

class FloorGraphStats {
  final int nodeCount;
  final int edgeCount;
  final int navigableCount;

  /// Navigable nodes outside the largest connected group.
  final int disconnectedCount;
  final RoutingStatus status;

  /// Nodes on this floor whose `cross_building_ref` is shared with another
  /// node (linked), or not yet matched by any other node (pending).
  final int crossBuildingLinks;
  final int crossBuildingPending;

  const FloorGraphStats({
    this.nodeCount = 0,
    this.edgeCount = 0,
    this.navigableCount = 0,
    this.disconnectedCount = 0,
    this.status = RoutingStatus.empty,
    this.crossBuildingLinks = 0,
    this.crossBuildingPending = 0,
  });

  /// Edges are treated as undirected for the connectivity check.
  factory FloorGraphStats.compute({
    required int nodeCount,
    required Set<String> navigableIds,
    required List<(String, String)> edges,
    int crossBuildingLinks = 0,
    int crossBuildingPending = 0,
  }) {
    final adjacency = <String, Set<String>>{
      for (final id in navigableIds) id: <String>{},
    };
    for (final (a, b) in edges) {
      if (!adjacency.containsKey(a) || !adjacency.containsKey(b)) continue;
      adjacency[a]!.add(b);
      adjacency[b]!.add(a);
    }

    var largest = 0;
    final seen = <String>{};
    for (final start in navigableIds) {
      if (!seen.add(start)) continue;
      var size = 0;
      final stack = [start];
      while (stack.isNotEmpty) {
        final u = stack.removeLast();
        size++;
        for (final v in adjacency[u]!) {
          if (seen.add(v)) stack.add(v);
        }
      }
      if (size > largest) largest = size;
    }

    final nav = navigableIds.length;
    final RoutingStatus status;
    if (nodeCount == 0) {
      status = RoutingStatus.empty;
    } else if (nav < 2 || largest < 2) {
      status = RoutingStatus.notRoutable;
    } else if (largest < nav) {
      status = RoutingStatus.partial;
    } else {
      status = RoutingStatus.ready;
    }
    return FloorGraphStats(
      nodeCount: nodeCount,
      edgeCount: edges.length,
      navigableCount: nav,
      disconnectedCount: nav - largest,
      status: status,
      crossBuildingLinks: crossBuildingLinks,
      crossBuildingPending: crossBuildingPending,
    );
  }
}
