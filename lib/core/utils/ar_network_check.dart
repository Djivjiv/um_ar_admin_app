import '../../domain/models/outdoor_ar_edge_model.dart';
import '../../domain/models/outdoor_ar_node_model.dart';

/// Health of the Outdoor AR path network, as the user app will route on it:
/// only active nodes and active edges between them count.
class ArNetworkReport {
  /// Connected groups of active node ids, largest first. Groups of one are
  /// isolated nodes (also listed in [isolatedNodeIds]).
  final List<List<String>> components;

  /// Active nodes with no active edge to another active node.
  final List<String> isolatedNodeIds;

  /// Buildings with no active AR node linked by `building_id`, so no AR
  /// route can end at them.
  final List<int> buildingsWithoutNode;

  /// Buildings whose linked nodes all lie outside the largest group, so a
  /// route from the main network can't reach them.
  final List<int> buildingsOffMainNetwork;

  const ArNetworkReport({
    this.components = const [],
    this.isolatedNodeIds = const [],
    this.buildingsWithoutNode = const [],
    this.buildingsOffMainNetwork = const [],
  });

  /// True when there is one piece and every building has a reachable node.
  bool get isHealthy =>
      components.length <= 1 &&
      buildingsWithoutNode.isEmpty &&
      buildingsOffMainNetwork.isEmpty;
}

/// Checks [nodes] and [edges] against [buildingIds] (the buildings that
/// should be reachable, e.g. the active ones).
ArNetworkReport checkArNetwork({
  required Iterable<OutdoorArNodeModel> nodes,
  required Iterable<OutdoorArEdgeModel> edges,
  required Iterable<int> buildingIds,
}) {
  final active = <String, OutdoorArNodeModel>{
    for (final n in nodes)
      if (n.isActive && n.id != null) n.id!: n,
  };

  final adjacency = <String, Set<String>>{
    for (final id in active.keys) id: <String>{},
  };
  for (final e in edges) {
    if (!e.isActive || e.fromNode == e.toNode) continue;
    final a = adjacency[e.fromNode];
    final b = adjacency[e.toNode];
    if (a == null || b == null) continue; // an end is inactive or missing
    a.add(e.toNode);
    b.add(e.fromNode);
  }

  final components = <List<String>>[];
  final seen = <String>{};
  for (final start in active.keys) {
    if (!seen.add(start)) continue;
    final group = <String>[];
    final stack = [start];
    while (stack.isNotEmpty) {
      final u = stack.removeLast();
      group.add(u);
      for (final v in adjacency[u]!) {
        if (seen.add(v)) stack.add(v);
      }
    }
    components.add(group);
  }
  // Largest first; ties keep discovery order (List.sort is not stable, so
  // compare the original index too).
  final order = {for (var i = 0; i < components.length; i++) components[i]: i};
  components.sort((a, b) {
    final bySize = b.length.compareTo(a.length);
    return bySize != 0 ? bySize : order[a]!.compareTo(order[b]!);
  });

  final main = components.isEmpty ? const <String>{} : components.first.toSet();
  final linked = <int, List<String>>{};
  for (final n in active.values) {
    final b = n.buildingId;
    if (b != null) (linked[b] ??= []).add(n.id!);
  }

  final wanted = buildingIds.toSet().toList();
  return ArNetworkReport(
    components: components,
    isolatedNodeIds: [
      for (final g in components)
        if (g.length == 1) g.first,
    ],
    buildingsWithoutNode: [
      for (final b in wanted)
        if (!linked.containsKey(b)) b,
    ],
    buildingsOffMainNetwork: [
      for (final b in wanted)
        if (linked.containsKey(b) && !linked[b]!.any(main.contains)) b,
    ],
  );
}
