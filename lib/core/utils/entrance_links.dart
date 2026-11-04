import '../../domain/models/floor_plan_model.dart';
import '../../domain/models/indoor_node_model.dart';
import '../../domain/models/outdoor_node_model.dart';

/// Rules for the pair an entrance must be: an outdoor node
/// (`outdoor_nodes.indoor_node_id`) and the indoor node it leads into
/// (`indoor_nodes.outdoor_node_id`, the reverse side).

/// An indoor node an entrance can lead into. The floor plan editor only keeps
/// `outdoor_node_id` on navigable nodes labelled `entrance`, so a link to any
/// other node would be wiped the next time that node is edited there.
bool isIndoorEntranceNode(IndoorNodeModel n) =>
    n.isActive && n.isNavigable && n.label == 'entrance';

/// The node's building, falling back to its floor plan's: `building_id` can
/// be empty on nodes where only `floor_plan_id` was set.
int? indoorNodeBuilding(IndoorNodeModel n, Map<int, FloorPlanModel> plans) =>
    n.buildingId ?? plans[n.floorPlanId]?.buildingId;

/// The node's floor, from its floor plan when there is one.
int indoorNodeFloor(IndoorNodeModel n, Map<int, FloorPlanModel> plans) =>
    plans[n.floorPlanId]?.floorNumber ?? n.floor;

/// "Floor 1 · Main Door (n12)".
String entranceNodeLabel(IndoorNodeModel n, Map<int, FloorPlanModel> plans) {
  final name = [n.entranceLabel, n.name]
      .map((s) => s?.trim() ?? '')
      .firstWhere((s) => s.isNotEmpty, orElse: () => '');
  final title = name.isEmpty ? n.id : '$name (${n.id})';
  return 'Floor ${indoorNodeFloor(n, plans)} · $title';
}

/// Why the form can't save as filled in, or null when it can.
String? entranceFormError({
  required bool isEntrance,
  required String? buildingId,
  required String? indoorNodeId,
}) {
  if (!isEntrance) return null;
  if ((buildingId ?? '').isEmpty) return 'Select the building first.';
  if ((indoorNodeId ?? '').isEmpty) {
    return 'Choose the indoor entrance node this entrance leads into.';
  }
  return null;
}

/// Why outdoor node [outdoorId] of building [buildingId] may not link to
/// [indoorNodeId], or null when it may. [target] is that indoor node, null
/// if it doesn't exist. [entrances] needs the outdoor entrances that target
/// it, active or not, as an inactive one still holds the link.
String? entranceLinkBlocker({
  required String outdoorId,
  required int? buildingId,
  required String indoorNodeId,
  required IndoorNodeModel? target,
  required Map<int, FloorPlanModel> plans,
  required Iterable<OutdoorNodeModel> entrances,
}) {
  if (target == null) return 'Indoor node $indoorNodeId no longer exists.';
  if (!isIndoorEntranceNode(target)) {
    return 'Indoor node ${target.id} is not an active entrance node.';
  }
  if (indoorNodeBuilding(target, plans) != buildingId) {
    return 'Indoor node ${target.id} is in a different building from this '
        'entrance.';
  }
  for (final e in entrances) {
    if (e.id != outdoorId && e.isEntrance && e.indoorNodeId == target.id) {
      return 'Indoor node ${target.id} is already linked to outdoor entrance '
          '${e.id}. Each indoor node can have only one.';
    }
  }
  return null;
}

/// A warning when [target] isn't on the lowest floor of the building's
/// entrance nodes. Only a warning: on a slope, a door can really be upstairs.
String? entranceFloorWarning({
  required IndoorNodeModel target,
  required Iterable<IndoorNodeModel> buildingNodes,
  required Map<int, FloorPlanModel> plans,
}) {
  final floors = [
    for (final n in buildingNodes)
      if (isIndoorEntranceNode(n)) indoorNodeFloor(n, plans),
  ];
  if (floors.isEmpty) return null;
  final lowest = floors.reduce((a, b) => a < b ? a : b);
  final floor = indoorNodeFloor(target, plans);
  if (floor <= lowest) return null;
  return 'This node is on floor $floor, but this building has an entrance on '
      'floor $lowest. Check that this door is really on floor $floor.';
}

/// Which outdoor entrance holds each indoor node, for the form to mark nodes
/// that are taken.
Map<String, String> indoorNodesInUse(
  Iterable<OutdoorNodeModel> entrances, {
  required String exceptOutdoorId,
}) =>
    {
      for (final e in entrances)
        if (e.isEntrance &&
            e.id != exceptOutdoorId &&
            (e.indoorNodeId ?? '').isNotEmpty)
          e.indoorNodeId!: e.id,
    };

enum EntranceStatus {
  linked('Linked'),
  missingIndoorNode('Missing indoor node'),
  differentBuilding('Indoor node in a different building'),
  sharedIndoorNode('Indoor node shared with another entrance');

  final String label;
  const EntranceStatus(this.label);
}

/// One outdoor entrance and how its link stands.
class EntranceStatusRow {
  final OutdoorNodeModel entrance;

  /// The entrance's building; null when it has none.
  final int? buildingId;
  final EntranceStatus status;

  /// What exactly is wrong, for rows that aren't [EntranceStatus.linked].
  final String? detail;

  const EntranceStatusRow({
    required this.entrance,
    required this.buildingId,
    required this.status,
    this.detail,
  });

  bool get isLinked => status == EntranceStatus.linked;
}

/// The status of each active entrance in [entrances], ordered by building
/// then id. With [activeBuildingIds], entrances of other buildings are left
/// out, so inactive buildings stay hidden; one with no building stays in,
/// because it needs fixing.
List<EntranceStatusRow> entranceStatusList({
  required Iterable<OutdoorNodeModel> entrances,
  required Iterable<IndoorNodeModel> indoorNodes,
  required Map<int, FloorPlanModel> plans,
  Set<int>? activeBuildingIds,
}) {
  final byId = {for (final n in indoorNodes) n.id: n};
  final holders = <String, List<String>>{};
  for (final e in entrances) {
    final target = e.indoorNodeId ?? '';
    if (e.isEntrance && target.isNotEmpty) {
      (holders[target] ??= []).add(e.id);
    }
  }

  EntranceStatusRow rowFor(OutdoorNodeModel e, int? buildingId) {
    EntranceStatusRow row(EntranceStatus status, [String? detail]) =>
        EntranceStatusRow(
          entrance: e,
          buildingId: buildingId,
          status: status,
          detail: detail,
        );

    final targetId = e.indoorNodeId ?? '';
    if (targetId.isEmpty) {
      return row(EntranceStatus.missingIndoorNode, 'No indoor node chosen');
    }
    final target = byId[targetId];
    if (target == null) {
      return row(EntranceStatus.missingIndoorNode,
          'Indoor node $targetId no longer exists');
    }
    if (!isIndoorEntranceNode(target)) {
      return row(EntranceStatus.missingIndoorNode,
          'Indoor node $targetId is not an active entrance node');
    }
    if (indoorNodeBuilding(target, plans) != buildingId) {
      return row(EntranceStatus.differentBuilding,
          'Indoor node $targetId belongs to another building');
    }
    final others = holders[targetId]!.where((id) => id != e.id).toList();
    if (others.isNotEmpty) {
      return row(EntranceStatus.sharedIndoorNode,
          'Indoor node $targetId is also used by ${others.join(', ')}');
    }
    return row(EntranceStatus.linked);
  }

  final rows = <EntranceStatusRow>[];
  for (final e in entrances) {
    if (!e.isEntrance || !e.isActive) continue;
    final buildingId = int.tryParse(e.buildingId ?? '');
    if (buildingId != null &&
        activeBuildingIds != null &&
        !activeBuildingIds.contains(buildingId)) {
      continue;
    }
    rows.add(rowFor(e, buildingId));
  }
  rows.sort((a, b) {
    final byBuilding = (a.buildingId ?? -1).compareTo(b.buildingId ?? -1);
    return byBuilding != 0
        ? byBuilding
        : a.entrance.id.compareTo(b.entrance.id);
  });
  return rows;
}

/// The rows that aren't linked, grouped by building. Its length is the
/// "Buildings with unlinked entrances" count.
Map<int?, List<EntranceStatusRow>> unlinkedByBuilding(
  Iterable<EntranceStatusRow> rows,
) {
  final grouped = <int?, List<EntranceStatusRow>>{};
  for (final r in rows) {
    if (!r.isLinked) (grouped[r.buildingId] ??= []).add(r);
  }
  return grouped;
}
