import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../core/utils/entrance_links.dart';
import '../../domain/models/floor_plan_model.dart';
import '../../domain/models/indoor_node_model.dart';
import '../../domain/models/outdoor_node_model.dart';
import 'node_repository.dart';
import 'paged_query.dart';
import 'repository_exception.dart';

/// What the entrance form needs to know about one building.
class BuildingEntranceData {
  /// Floor plans of the building, by id.
  final Map<int, FloorPlanModel> plans;

  /// The building's indoor nodes that an entrance can lead into.
  final List<IndoorNodeModel> entranceNodes;

  /// Every outdoor entrance, to see which indoor nodes are taken.
  final List<OutdoorNodeModel> entrances;

  const BuildingEntranceData({
    required this.plans,
    required this.entranceNodes,
    required this.entrances,
  });
}

/// Keeps the two sides of an entrance link in step:
/// `outdoor_nodes.indoor_node_id` and `indoor_nodes.outdoor_node_id`.
class EntranceLinkRepository {
  final _client = SupabaseConfig.client;
  final _nodeRepo = NodeRepository();
  static const _outdoorTable = 'outdoor_nodes';
  static const _indoorTable = 'indoor_nodes';
  static const _plansTable = 'building_floors';

  String? _targetOf(OutdoorNodeModel? node) {
    if (node == null || !node.isEntrance) return null;
    final id = node.indoorNodeId ?? '';
    return id.isEmpty ? null : id;
  }

  Future<List<OutdoorNodeModel>> _allEntrances() async {
    final rows = await fetchAllPages((a, b) => _client
        .from(_outdoorTable)
        .select()
        .eq('is_entrance', true)
        .order('id')
        .range(a, b));
    return rows.map(OutdoorNodeModel.fromJson).toList();
  }

  Future<Map<int, FloorPlanModel>> _plans({int? buildingId}) async {
    final rows = await fetchAllPages((a, b) {
      var query = _client.from(_plansTable).select();
      if (buildingId != null) query = query.eq('building_id', buildingId);
      return query.order('id').range(a, b);
    });
    final plans = rows.map(FloorPlanModel.fromJson);
    return {for (final p in plans) if (p.id != null) p.id!: p};
  }

  /// Everything the entrance form shows for [buildingId]. Indoor nodes are
  /// matched by `building_id` and by floor plan, as `building_id` can be
  /// empty.
  Future<BuildingEntranceData> loadForBuilding(int buildingId) async {
    try {
      final plans = await _plans(buildingId: buildingId);
      final byBuilding = await fetchAllPages((a, b) => _client
          .from(_indoorTable)
          .select()
          .eq('building_id', buildingId)
          .order('id')
          .range(a, b));
      final byPlan = plans.isEmpty
          ? const <Map<String, dynamic>>[]
          : await fetchAllPages((a, b) => _client
              .from(_indoorTable)
              .select()
              .inFilter('floor_plan_id', plans.keys.toList())
              .order('id')
              .range(a, b));
      final nodes = <String, IndoorNodeModel>{
        for (final r in [...byBuilding, ...byPlan])
          r['id'].toString(): IndoorNodeModel.fromJson(r),
      };
      final entranceNodes = [
        for (final n in nodes.values)
          if (isIndoorEntranceNode(n)) n,
      ]..sort((a, b) {
          final byFloor =
              indoorNodeFloor(a, plans).compareTo(indoorNodeFloor(b, plans));
          return byFloor != 0 ? byFloor : a.id.compareTo(b.id);
        });
      return BuildingEntranceData(
        plans: plans,
        entranceNodes: entranceNodes,
        entrances: await _allEntrances(),
      );
    } catch (e) {
      throw RepositoryException(
          'Failed to load the building\'s indoor entrances: '
          '${describeError(e)}',
          e);
    }
  }

  /// Checks [node] against the database as it is now, so two admins (or a
  /// stale form) can't get past the rules. Throws a [RepositoryException]
  /// naming the problem.
  Future<void> checkLink(OutdoorNodeModel node) async {
    final formError = entranceFormError(
      isEntrance: node.isEntrance,
      buildingId: node.buildingId,
      indoorNodeId: node.indoorNodeId,
    );
    if (formError != null) throw RepositoryException(formError);
    final targetId = _targetOf(node);
    if (targetId == null) return;

    final String? blocker;
    try {
      final row = await _client
          .from(_indoorTable)
          .select()
          .eq('id', targetId)
          .maybeSingle();
      final target = row == null ? null : IndoorNodeModel.fromJson(row);
      final planRow = target?.floorPlanId == null
          ? null
          : await _client
              .from(_plansTable)
              .select()
              .eq('id', target!.floorPlanId!)
              .maybeSingle();
      final plan = planRow == null ? null : FloorPlanModel.fromJson(planRow);
      final holders = await fetchAllPages((a, b) => _client
          .from(_outdoorTable)
          .select()
          .eq('indoor_node_id', targetId)
          .order('id')
          .range(a, b));
      blocker = entranceLinkBlocker(
        outdoorId: node.id,
        buildingId: int.tryParse(node.buildingId ?? ''),
        indoorNodeId: targetId,
        target: target,
        plans: {if (plan?.id != null) plan!.id!: plan},
        entrances: holders.map(OutdoorNodeModel.fromJson),
      );
    } catch (e) {
      throw RepositoryException(
          'Failed to check the indoor node: ${describeError(e)}', e);
    }
    if (blocker != null) throw RepositoryException(blocker);
  }

  /// Saves outdoor node [node] and the indoor side of its link. [previous] is
  /// the saved row when editing, null when creating.
  ///
  /// Supabase has no client-side transactions: if the indoor side fails, the
  /// outdoor write is undone, so nothing changes and the whole save can be
  /// retried.
  Future<OutdoorNodeModel> save(
    OutdoorNodeModel node, {
    OutdoorNodeModel? previous,
  }) async {
    await checkLink(node);
    final oldTarget = _targetOf(previous);
    final newTarget = _targetOf(node);

    final saved = previous == null
        ? await _nodeRepo.createNode(node)
        : await _nodeRepo.updateNode(node);

    var clearedOld = false;
    try {
      if (oldTarget != null && oldTarget != newTarget) {
        clearedOld = await _clearIndoorSide(oldTarget, node.id);
      }
      if (newTarget != null) {
        final rows = await _client
            .from(_indoorTable)
            .update({'outdoor_node_id': node.id, 'is_entrance': true})
            .eq('id', newTarget)
            .select('id');
        requireAffected(rows, 'Linking indoor node $newTarget');
      }
      return saved;
    } catch (e) {
      await _undoSave(node, previous, oldTarget, clearedOld);
      if (e is RepositoryException) {
        throw RepositoryException('Nothing was changed: ${e.message}', e);
      }
      throw RepositoryException(
          'Nothing was changed: could not update the indoor node '
          '(${describeError(e)}).',
          e);
    }
  }

  /// Clears `outdoor_node_id` on [indoorId] if it still points at
  /// [outdoorId]. True when it did.
  Future<bool> _clearIndoorSide(String indoorId, String outdoorId) async {
    final rows = await _client
        .from(_indoorTable)
        .update({'outdoor_node_id': null})
        .eq('id', indoorId)
        .eq('outdoor_node_id', outdoorId)
        .select('id');
    return rows.isNotEmpty;
  }

  Future<void> _undoSave(
    OutdoorNodeModel node,
    OutdoorNodeModel? previous,
    String? oldTarget,
    bool clearedOld,
  ) async {
    try {
      if (previous == null) {
        // Not NodeRepository.deleteNode: that writes to indoor_nodes first,
        // the table that just failed, and a new node has nothing to clear.
        await _client.from(_outdoorTable).delete().eq('id', node.id);
      } else {
        await _nodeRepo.updateNode(previous);
      }
      if (clearedOld) {
        await _client
            .from(_indoorTable)
            .update({'outdoor_node_id': node.id})
            .eq('id', oldTarget!);
      }
    } catch (e) {
      throw RepositoryException(
          'The indoor link failed, and outdoor node ${node.id} could not be '
          'put back. Open it in the campus map editor and save it again.',
          e);
    }
  }

  /// Checks the link the floor plan editor is about to save on [node]. Run it
  /// before writing, as that form writes `outdoor_node_id` directly.
  Future<void> checkIndoorSide(IndoorNodeModel node) async {
    final outdoorId = node.outdoorNodeId ?? '';
    if (outdoorId.isEmpty) return;
    final String? blocker;
    try {
      final row = await _client
          .from(_outdoorTable)
          .select()
          .eq('id', outdoorId)
          .maybeSingle();
      final outdoor = row == null ? null : OutdoorNodeModel.fromJson(row);
      final others = await fetchAllPages((a, b) => _client
          .from(_indoorTable)
          .select('id')
          .eq('outdoor_node_id', outdoorId)
          .neq('id', node.id)
          .order('id')
          .range(a, b));
      blocker = _indoorSideBlocker(node, outdoorId, outdoor, others);
    } catch (e) {
      throw RepositoryException(
          'Failed to check the outdoor node: ${describeError(e)}', e);
    }
    if (blocker != null) throw RepositoryException(blocker);
  }

  String? _indoorSideBlocker(
    IndoorNodeModel node,
    String outdoorId,
    OutdoorNodeModel? outdoor,
    List<Map<String, dynamic>> others,
  ) {
    if (outdoor == null) return 'Outdoor node $outdoorId does not exist.';
    if (!outdoor.isEntrance) {
      return 'Outdoor node $outdoorId is not a building entrance.';
    }
    if (int.tryParse(outdoor.buildingId ?? '') != node.buildingId) {
      return 'Outdoor node $outdoorId belongs to a different building.';
    }
    final current = outdoor.indoorNodeId ?? '';
    if (current.isNotEmpty && current != node.id) {
      return 'Outdoor entrance $outdoorId is already linked to indoor node '
          '$current. Change it in the campus map editor.';
    }
    if (others.isNotEmpty) {
      return 'Outdoor entrance $outdoorId is already claimed by indoor node '
          '${others.first['id']}.';
    }
    return null;
  }

  /// Writes the outdoor side after the floor plan editor saved [node].
  Future<void> syncFromIndoor(
    IndoorNodeModel node, {
    IndoorNodeModel? previous,
  }) async {
    final oldOutdoor = previous?.outdoorNodeId ?? '';
    final newOutdoor = node.outdoorNodeId ?? '';
    try {
      if (oldOutdoor.isNotEmpty && oldOutdoor != newOutdoor) {
        await _client
            .from(_outdoorTable)
            .update({'indoor_node_id': null})
            .eq('id', oldOutdoor)
            .eq('indoor_node_id', node.id)
            .select('id');
      }
      if (newOutdoor.isNotEmpty) {
        await _nodeRepo.setIndoorLink(newOutdoor, node.id);
      }
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException(
          'Failed to update the outdoor entrance: ${describeError(e)}', e);
    }
  }

  /// Clears `indoor_node_id` on every outdoor node pointing at deleted indoor
  /// node [indoorId]. They then show as missing an indoor node.
  Future<void> clearLinksToIndoorNode(String indoorId) async {
    try {
      await _client
          .from(_outdoorTable)
          .update({'indoor_node_id': null})
          .eq('indoor_node_id', indoorId)
          .select('id');
    } catch (e) {
      throw RepositoryException(
          'Node deleted, but the outdoor entrance pointing at it was not '
          'updated: ${describeError(e)}',
          e);
    }
  }

  /// Every entrance's status, for the AR network check. See
  /// [entranceStatusList] for [activeBuildingIds].
  Future<List<EntranceStatusRow>> getStatusList({
    Set<int>? activeBuildingIds,
  }) async {
    try {
      final entrances = await _allEntrances();
      final plans = await _plans();
      final indoorRows = await fetchAllPages((a, b) => _client
          .from(_indoorTable)
          .select()
          .order('id')
          .range(a, b));
      return entranceStatusList(
        entrances: entrances,
        indoorNodes: indoorRows.map(IndoorNodeModel.fromJson),
        plans: plans,
        activeBuildingIds: activeBuildingIds,
      );
    } on PostgrestException catch (e) {
      throw RepositoryException(
          'Failed to load building entrances: ${e.message}', e);
    } catch (e) {
      throw RepositoryException('Failed to load building entrances', e);
    }
  }
}
