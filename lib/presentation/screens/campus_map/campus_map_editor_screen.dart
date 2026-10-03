import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/building_repository.dart';
import '../../../data/repositories/node_repository.dart';
import '../../../domain/models/building_model.dart';
import '../../../domain/models/outdoor_edge_model.dart';
import '../../../domain/models/outdoor_node_model.dart';
import '../../widgets/confirm_dialog.dart';

// --- MapTiler + campus config ---------------------------------------------

const _mapTilerKey = '7IdsZLpK0EDETzZ6ITe6';
const _baseTilesUrl =
    'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=$_mapTilerKey';
const _overlayTilesUrl =
    'https://api.maptiler.com/tiles/019fff21-f053-72a0-838d-683bbccd7aa7/{z}/{x}/{y}.webp?key=$_mapTilerKey';

const _campusCenter = LatLng(7.0673125, 125.5951125);
// Deliberately loose so fullscreen / window resize can never break the camera.
final _campusBounds = LatLngBounds(
  const LatLng(7.030, 125.560),
  const LatLng(7.100, 125.630),
);

const _cGate = Color(0xFF1D9E75);
const _cBuilding = Color(0xFF7B1C1C);
const _cIntersection = Color(0xFF185FA5);
const _cPathway = Color(0xFFC9972C);
const _cRoute = Color(0xFF4285F4);

const _nodeTypes = ['gate', 'building', 'intersection', 'pathway'];
const _walkSpeedMps = 1.35;

Color _nodeColor(String? type) {
  switch ((type ?? '').toLowerCase()) {
    case 'gate':
      return _cGate;
    case 'building':
      return _cBuilding;
    case 'pathway':
      return _cPathway;
    case 'intersection':
    default:
      return _cIntersection;
  }
}

enum _Tab { nodes, edges, route }

enum _EditorMode { none, addNode, addEdge }

enum _RouteTarget { building, node }

/// Result of a route search.
class _RouteResult {
  final List<String> path;
  final double distanceM;
  const _RouteResult(this.path, this.distanceM);
}

class CampusMapEditorScreen extends StatefulWidget {
  const CampusMapEditorScreen({super.key});

  @override
  State<CampusMapEditorScreen> createState() => _CampusMapEditorScreenState();
}

class _CampusMapEditorScreenState extends State<CampusMapEditorScreen> {
  final _repo = NodeRepository();
  final _buildingRepo = BuildingRepository();
  final _mapController = MapController();

  List<OutdoorNodeModel> _nodes = [];
  List<OutdoorEdgeModel> _edges = [];
  List<BuildingModel> _buildings = [];
  bool _loading = true;
  Object? _error;

  _Tab _tab = _Tab.nodes;
  _EditorMode _mode = _EditorMode.none;

  String? _selectedNodeId;
  String _nodeSearch = '';

  // add-edge mode
  String? _edgeFromId;
  String? _edgeToId;

  // test route
  _RouteTarget _routeFromTarget = _RouteTarget.node;
  _RouteTarget _routeToTarget = _RouteTarget.building;
  String? _routeFromNodeId;
  String? _routeFromBuildingId;
  String? _routeToNodeId;
  String? _routeToBuildingId;
  List<LatLng> _routePoints = const [];
  double _routeDistanceM = 0;
  int _routeWaypoints = 0;
  String? _routeStartNodeId;
  String? _routeStartLabel;
  String? _routeDestNodeId;
  String? _routeDestLabel;

  double _currentZoom = 16;
  StreamSubscription<MapEvent>? _mapEventSub;

  // Building labels are static — shown only at/above this zoom, no fade.
  static const double _buildingLabelShowZoom = 17.0;

  // zoom-based node-id-label visibility
  static const double _nodeLabelHideZoom = 17.0;
  static const double _nodeLabelFullShowZoom = 17.8;

  double get _nodeLabelOpacity {
    if (_currentZoom <= _nodeLabelHideZoom) return 0.0;
    if (_currentZoom >= _nodeLabelFullShowZoom) return 1.0;
    return (_currentZoom - _nodeLabelHideZoom) /
        (_nodeLabelFullShowZoom - _nodeLabelHideZoom);
  }

  // building label editing (display name only — position is static)
  String? _selectedBuildingId;

  @override
  void initState() {
    super.initState();
    _load();
    _mapEventSub = _mapController.mapEventStream.listen((event) {
      if (event is MapEventMove ||
          event is MapEventScrollWheelZoom ||
          event is MapEventFlingAnimation) {
        if (mounted) {
          setState(() {
            _currentZoom = _mapController.camera.zoom;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _mapEventSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // --- data --------------------------------------------------------------

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final nodes = await _repo.getAllNodes();
      final edges = await _repo.getAllEdges();
      // Buildings are for the dropdown only — don't fail the whole screen if
      // they can't be read (e.g. missing RLS select policy).
      List<BuildingModel> buildings = [];
      try {
        buildings = await _buildingRepo.getAll();
      } catch (be) {
        debugPrint('buildings fetch failed (dropdown will be empty): $be');
      }
      debugPrint('Fetched ${nodes.length} nodes from Supabase');
      debugPrint('Fetched ${edges.length} edges from Supabase');
      setState(() {
        _nodes = nodes;
        _edges = edges;
        _buildings = buildings;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Campus map load failed: $e');
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    try {
      final nodes = await _repo.getAllNodes();
      final edges = await _repo.getAllEdges();
      setState(() {
        _nodes = nodes;
        _edges = edges;
      });
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  // --- lookups -----------------------------------------------------

  BuildingModel? _buildingById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final b in _buildings) {
      if (b.id?.toString() == id) return b;
    }
    return null;
  }

  String _buildingLabel(OutdoorNodeModel n) {
    final b = _buildingById(n.buildingId);
    return b?.name ?? n.buildingName ?? 'Building ${n.buildingId}';
  }

  // --- building label editing (display name only; position is static) ----

  /// Text shown on the map label: display_name → short_name → name.
  String _buildingDisplayText(BuildingModel b) {
    if ((b.displayName ?? '').isNotEmpty) return b.displayName!;
    if ((b.shortName ?? '').isNotEmpty) return b.shortName!;
    return b.name;
  }

  Future<void> _saveDisplayName(BuildingModel building, String name) async {
    try {
      final updated = await _buildingRepo.update(
        name.isEmpty
            ? building.clearDisplayName()
            : building.copyWith(displayName: name),
      );
      setState(() {
        _buildings = [
          for (final b in _buildings) if (b.id == updated.id) updated else b,
        ];
      });
      if (mounted) context.showSuccess('Display name saved');
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  void _locateBuilding(BuildingModel b) {
    if (b.lat == null || b.lng == null) {
      context.showError('This building has no coordinates yet.');
      return;
    }
    _mapController.move(LatLng(b.lat!, b.lng!), math.max(_currentZoom, 18));
  }

  List<OutdoorNodeModel> _entranceNodesForBuilding(String buildingId) {
    return _nodes
        .where((n) =>
            n.isEntrance &&
            n.buildingId == buildingId &&
            n.lat != null &&
            n.lng != null)
        .toList();
  }

  OutdoorNodeModel? _node(String? id) {
    if (id == null) return null;
    for (final n in _nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  LatLng? _pos(String? id) {
    final n = _node(id);
    if (n?.lat == null || n?.lng == null) return null;
    return LatLng(n!.lat!, n.lng!);
  }

  double _distanceM(String from, String to) {
    final a = _pos(from);
    final b = _pos(to);
    if (a == null || b == null) return 0;
    return const Distance().as(LengthUnit.Meter, a, b);
  }

  // --- mode helpers ----------------------------------------------------

  void _setMode(_EditorMode mode) {
    setState(() {
      _mode = _mode == mode ? _EditorMode.none : mode;
      _edgeFromId = null;
      _edgeToId = null;
    });
  }

  String get _banner {
    switch (_mode) {
      case _EditorMode.addNode:
        return 'Click anywhere on the map to place a new node';
      case _EditorMode.addEdge:
        return _edgeFromId == null
            ? 'Click the FROM node, then click the TO node'
            : 'Now click the TO node';
      case _EditorMode.none:
        return '';
    }
  }

  // --- node CRUD -----------------------------------------------------

  Future<void> _handleMapTap(LatLng point) async {
    if (_mode == _EditorMode.addNode) {
      final model = await showDialog<OutdoorNodeModel>(
        context: context,
        builder: (_) => _NodeDialog(
          point: point,
          buildingRepo: _buildingRepo,
        ),
      );
      if (model == null) return;
      try {
        await _repo.createNode(model);
        if (mounted) context.showSuccess('Node "${model.id}" added');
        setState(() => _mode = _EditorMode.none);
        await _refresh();
      } catch (e) {
        if (mounted) context.showError(e);
      }
      return;
    }
    setState(() => _selectedNodeId = null);
  }

  Future<void> _handleNodeTap(OutdoorNodeModel node) async {
    if (_mode == _EditorMode.addEdge) {
      if (_edgeFromId == null) {
        setState(() => _edgeFromId = node.id);
        return;
      }
      if (node.id == _edgeFromId) return;
      setState(() => _edgeToId = node.id);
      await _promptAddEdge(_edgeFromId!, node.id);
      return;
    }
    setState(() => _selectedNodeId = node.id);
  }

  Future<void> _editNode(OutdoorNodeModel node) async {
    final model = await showDialog<OutdoorNodeModel>(
      context: context,
      builder: (_) => _NodeDialog(
        existing: node,
        buildingRepo: _buildingRepo,
      ),
    );
    if (model == null) return;
    try {
      await _repo.updateNode(model);
      if (mounted) context.showSuccess('Node "${model.id}" updated');
      await _refresh();
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  Future<void> _deleteNode(OutdoorNodeModel node) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Delete node',
      itemName: node.id,
      message:
          'Delete node ${node.id}? This will also delete all connected edges.',
    );
    if (!ok) return;
    try {
      await _repo.deleteNode(node.id);
      if (mounted) context.showSuccess('Node "${node.id}" deleted');
      if (_selectedNodeId == node.id) {
        setState(() => _selectedNodeId = null);
      }
      await _refresh();
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  // --- edge CRUD ---------------------------------------------------

  Future<void> _promptAddEdge(String fromId, String toId) async {
    final isTwoWay = await showDialog<bool>(
      context: context,
      builder: (_) => _EdgeDialog(fromId: fromId, toId: toId),
    );
    if (isTwoWay == null) {
      setState(() {
        _edgeFromId = null;
        _edgeToId = null;
      });
      return;
    }
    final a = _pos(fromId);
    final b = _pos(toId);
    final weight = (a != null && b != null)
        ? const Distance().as(LengthUnit.Meter, a, b)
        : 0.0;
    try {
      await _repo.createEdge(OutdoorEdgeModel(
        fromNode: fromId,
        toNode: toId,
        weight: weight,
        isTwoWay: isTwoWay,
      ));
      if (mounted) context.showSuccess('Edge $fromId → $toId added');
      setState(() {
        _mode = _EditorMode.none;
        _edgeFromId = null;
        _edgeToId = null;
      });
      await _refresh();
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  Future<void> _deleteEdge(OutdoorEdgeModel edge) async {
    if (edge.id == null) return;
    final ok = await ConfirmDialog.show(
      context,
      title: 'Delete edge',
      itemName: '${edge.fromNode} → ${edge.toNode}',
    );
    if (!ok) return;
    try {
      await _repo.deleteEdge(edge.id!);
      if (mounted) context.showSuccess('Edge deleted');
      await _refresh();
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  // --- dijkstra --------------------------------------------------

  /// Directed Dijkstra over [edges]. Two-way edges add both directions;
  /// one-way edges add only `from → to`.
  _RouteResult? _dijkstra(
    String start,
    String goal, {
    required List<OutdoorNodeModel> nodes,
    required List<OutdoorEdgeModel> edges,
  }) {
    final adjacency = <String, List<(String, double)>>{};
    void add(String a, String b, double w) {
      (adjacency[a] ??= <(String, double)>[]).add((b, w));
    }

    double weightOf(OutdoorEdgeModel e) {
      if (e.weight != null && e.weight! > 0) return e.weight!;
      final a = _pos(e.fromNode);
      final b = _pos(e.toNode);
      if (a == null || b == null) return 1;
      return const Distance().as(LengthUnit.Meter, a, b);
    }

    for (final e in edges) {
      final w = weightOf(e);
      add(e.fromNode, e.toNode, w);
      if (e.isTwoWay) add(e.toNode, e.fromNode, w);
    }

    final ids = nodes.map((n) => n.id).toSet();
    if (!ids.contains(start) || !ids.contains(goal)) return null;

    final dist = <String, double>{for (final id in ids) id: double.infinity};
    final prev = <String, String?>{};
    dist[start] = 0;

    final queue = SplayTreeSet<(double, String)>((x, y) {
      final c = x.$1.compareTo(y.$1);
      return c != 0 ? c : x.$2.compareTo(y.$2);
    });
    queue.add((0, start));
    final visited = <String>{};

    while (queue.isNotEmpty) {
      final current = queue.first;
      queue.remove(current);
      final u = current.$2;
      if (!visited.add(u)) continue;
      if (u == goal) break;
      for (final (v, w) in adjacency[u] ?? const <(String, double)>[]) {
        if (visited.contains(v)) continue;
        final nd = current.$1 + w;
        if (nd < (dist[v] ?? double.infinity)) {
          dist[v] = nd;
          prev[v] = u;
          queue.add((nd, v));
        }
      }
    }

    final d = dist[goal] ?? double.infinity;
    if (d == double.infinity) return null;

    final path = <String>[];
    String? step = goal;
    while (step != null) {
      path.insert(0, step);
      step = prev[step];
    }
    return _RouteResult(path, d);
  }

  List<String> _entranceIds(String buildingId) =>
      _entranceNodesForBuilding(buildingId).map((n) => n.id).toList();

  /// Spec helper: shortest path from a single [fromNodeId] to a specific
  /// [toNodeId], or to the closest entrance of [toBuildingId].
  List<LatLng> findShortestPathToBuilding({
    required String fromNodeId,
    required String? toBuildingId,
    required String? toNodeId,
    required List<OutdoorNodeModel> nodes,
    required List<OutdoorEdgeModel> edges,
  }) {
    final goals = (toBuildingId != null && toBuildingId.isNotEmpty)
        ? _entranceIds(toBuildingId)
        : (toNodeId == null ? const <String>[] : [toNodeId]);
    final best = _bestRoutes(starts: [fromNodeId], goals: goals);
    if (best == null) return const [];
    return [
      for (final id in best.route.path)
        if (_node(id)?.lat != null && _node(id)?.lng != null)
          LatLng(_node(id)!.lat!, _node(id)!.lng!),
    ];
  }

  /// Tries every (start, goal) combination and returns the shortest route.
  ({_RouteResult route, String startId, String destId})? _bestRoutes({
    required List<String> starts,
    required List<String> goals,
  }) {
    ({_RouteResult route, String s, String g})? best;
    for (final s in starts) {
      for (final g in goals) {
        if (s == g) continue;
        final r = _dijkstra(s, g, nodes: _nodes, edges: _edges);
        if (r == null || r.path.length < 2) continue;
        if (best == null || r.distanceM < best.route.distanceM) {
          best = (route: r, s: s, g: g);
        }
      }
    }
    if (best == null) return null;
    return (route: best.route, startId: best.s, destId: best.g);
  }

  String _endpointLabel({
    required bool isBuilding,
    required String? buildingId,
    required String nodeId,
  }) {
    final node = _node(nodeId);
    if (isBuilding && buildingId != null) {
      final bname = _buildingById(buildingId)?.name ?? 'Building';
      final ent = node?.entranceLabel?.isNotEmpty == true
          ? node!.entranceLabel!
          : 'Entrance';
      return '$bname — $ent (Node $nodeId)';
    }
    final name = node?.name;
    return 'Node $nodeId${name != null && name.isNotEmpty ? ' ($name)' : ''}';
  }

  void _findRoute() {
    final fromIsBuilding = _routeFromTarget == _RouteTarget.building;
    final toIsBuilding = _routeToTarget == _RouteTarget.building;

    // Resolve start candidates.
    final List<String> starts;
    if (fromIsBuilding) {
      final b = _routeFromBuildingId;
      if (b == null) return;
      starts = _entranceIds(b);
      if (starts.isEmpty) {
        final name = _buildingById(b)?.name ?? 'this building';
        context.showError(
            'No entrance nodes found for $name. Please link entrance nodes '
            'to this building first.');
        return;
      }
    } else {
      if (_routeFromNodeId == null) return;
      starts = [_routeFromNodeId!];
    }

    // Resolve goal candidates.
    final List<String> goals;
    if (toIsBuilding) {
      final b = _routeToBuildingId;
      if (b == null) return;
      goals = _entranceIds(b);
      if (goals.isEmpty) {
        final name = _buildingById(b)?.name ?? 'this building';
        context.showError(
            'No entrance nodes found for $name. Please link entrance nodes '
            'to this building first.');
        return;
      }
    } else {
      if (_routeToNodeId == null) return;
      goals = [_routeToNodeId!];
    }

    final best = _bestRoutes(starts: starts, goals: goals);
    if (best == null) {
      _clearRoute(resetInputs: false);
      context.showError('No route found between these nodes');
      return;
    }

    final points = [
      for (final id in best.route.path)
        if (_pos(id) != null) _pos(id)!,
    ];

    setState(() {
      _routePoints = points;
      _routeDistanceM = best.route.distanceM;
      _routeWaypoints = best.route.path.length;
      _routeStartNodeId = best.startId;
      _routeDestNodeId = best.destId;
      _routeStartLabel = _endpointLabel(
        isBuilding: fromIsBuilding,
        buildingId: _routeFromBuildingId,
        nodeId: best.startId,
      );
      _routeDestLabel = _endpointLabel(
        isBuilding: toIsBuilding,
        buildingId: _routeToBuildingId,
        nodeId: best.destId,
      );
    });

    if (points.length >= 2) {
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.all(50),
          maxZoom: 18,
        ),
      );
    }
  }

  void _clearRoute({bool resetInputs = true}) {
    setState(() {
      _routePoints = const [];
      _routeDistanceM = 0;
      _routeWaypoints = 0;
      _routeStartNodeId = null;
      _routeStartLabel = null;
      _routeDestNodeId = null;
      _routeDestLabel = null;
      if (resetInputs) {
        _routeFromNodeId = null;
        _routeFromBuildingId = null;
        _routeToNodeId = null;
        _routeToBuildingId = null;
      }
    });
  }

  // --- build ---------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 300, child: _leftPanel()),
        const SizedBox(width: 16),
        Expanded(child: _mapPanel()),
      ],
    );
  }

  // --- left panel --------------------------------------------

  Widget _leftPanel() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _tabButton('Nodes', _Tab.nodes),
              _tabButton('Edges', _Tab.edges),
              _tabButton('Test Route', _Tab.route),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: switch (_tab) {
              _Tab.nodes => _nodesTab(),
              _Tab.edges => _edgesTab(),
              _Tab.route => _routeTab(),
            },
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, _Tab tab) {
    final active = _tab == tab;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? _cBuilding : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: active ? _cBuilding : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _maroonButton(String label, VoidCallback onPressed, {bool on = false}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: on ? _cPathway : _cBuilding,
          foregroundColor: on ? _cBuilding : _cPathway,
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }

  Widget _nodesTab() {
    final q = _nodeSearch.toLowerCase();
    final list = _nodes.where((n) {
      if (q.isEmpty) return true;
      return n.id.toLowerCase().contains(q) ||
          (n.name ?? '').toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              _maroonButton(
                _mode == _EditorMode.addNode ? 'Cancel Add Node' : 'Add Node',
                () => _setMode(_EditorMode.addNode),
                on: _mode == _EditorMode.addNode,
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search by id or name…',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onChanged: (v) => setState(() => _nodeSearch = v),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            children: [
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: Text('No nodes',
                          style:
                              TextStyle(color: AppColors.textSecondary))),
                )
              else
                for (final n in list) ...[
                  _nodeRow(n),
                  const Divider(height: 1),
                ],
              _entrancesPanel(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _entrancesPanel() {
    final entrances =
        _nodes.where((n) => n.isEntrance && n.buildingId != null).toList();
    final grouped = <String, List<OutdoorNodeModel>>{};
    for (final n in entrances) {
      grouped.putIfAbsent(n.buildingId!, () => []).add(n);
    }
    final buildingIds = grouped.keys.toList()
      ..sort((a, b) => (_buildingById(a)?.name ?? a)
          .toLowerCase()
          .compareTo((_buildingById(b)?.name ?? b).toLowerCase()));

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: entrances.isNotEmpty,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text('Building Entrances (${entrances.length})',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold)),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          if (buildingIds.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text('No entrance nodes yet.',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            )
          else
            for (final bid in buildingIds) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
                child: Text(_buildingById(bid)?.name ?? 'Building $bid',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _cBuilding)),
              ),
              for (final n in grouped[bid]!)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 1, 12, 1),
                  child: Text(
                    '${n.id} · ${n.entranceLabel ?? 'Entrance'} · '
                    'floor ${n.floor}'
                    '${n.indoorNodeId != null ? ' · indoor ${n.indoorNodeId}' : ''}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ],
        ],
      ),
    );
  }

  Widget _nodeRow(OutdoorNodeModel n) {
    return InkWell(
      onTap: () {
        setState(() => _selectedNodeId = n.id);
        final p = _pos(n.id);
        if (p != null) {
          _mapController.move(p, math.max(_currentZoom, 18));
        }
      },
      child: Container(
        color: _selectedNodeId == n.id
            ? _cPathway.withValues(alpha: 0.12)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: _nodeColor(n.type), shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(n.id,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (n.isEntrance) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: _cGate.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text('Entrance',
                              style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  color: _cGate)),
                        ),
                      ],
                      if (n.indoorNodeId != null &&
                          n.indoorNodeId!.isNotEmpty) ...[
                        const SizedBox(width: 3),
                        const Icon(Icons.link, size: 12, color: _cIntersection),
                      ],
                    ],
                  ),
                  Text(n.name ?? '—',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis),
                  if (n.isEntrance && n.buildingId != null)
                    Row(
                      children: [
                        const Icon(Icons.apartment,
                            size: 11, color: _cBuilding),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(_buildingLabel(n),
                              style: const TextStyle(
                                  fontSize: 10, color: _cBuilding),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _cPathway.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(n.type ?? '—',
                  style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: _cPathway)),
            ),
            IconButton(
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit, size: 16),
              onPressed: () => _editNode(n),
            ),
            IconButton(
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline,
                  size: 16, color: AppColors.errorRed),
              onPressed: () => _deleteNode(n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _edgesTab() {
    final list = [..._edges]..sort((a, b) {
        final c = a.fromNode.compareTo(b.fromNode);
        return c != 0 ? c : a.toNode.compareTo(b.toNode);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: _maroonButton(
            _mode == _EditorMode.addEdge ? 'Cancel Add Edge' : 'Add Edge',
            () => _setMode(_EditorMode.addEdge),
            on: _mode == _EditorMode.addEdge,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            children: [
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: Text('No edges',
                          style:
                              TextStyle(color: AppColors.textSecondary))),
                )
              else
                for (final e in list) ...[
                  _edgeRow(e),
                  const Divider(height: 1),
                ],
              _buildingsPanel(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _edgeRow(OutdoorEdgeModel e) {
    final dist = (e.weight != null && e.weight! > 0)
        ? e.weight!
        : _distanceM(e.fromNode, e.toNode);
    return ListTile(
      dense: true,
      title: Text('${e.fromNode}  →  ${e.toNode}',
          style: const TextStyle(fontSize: 12)),
      subtitle: Row(
        children: [
          Text('${dist.toStringAsFixed(0)} m',
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary)),
          if (!e.isTwoWay) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.warningAmber.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text('One Way',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warningAmber)),
            ),
          ],
        ],
      ),
      trailing: IconButton(
        tooltip: 'Delete',
        icon: const Icon(Icons.delete_outline,
            size: 18, color: AppColors.errorRed),
        onPressed: () => _deleteEdge(e),
      ),
    );
  }

  // --- buildings panel (labels) ----------------------------------------

  Widget _buildingsPanel() {
    final list = [..._buildings]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final selected = _buildingById(_selectedBuildingId);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: _selectedBuildingId != null,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text('Buildings (${list.length})',
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          if (selected != null)
            _SelectedBuildingPanel(
              key: ValueKey('bld-${selected.id}'),
              building: selected,
              onDeselect: () => setState(() => _selectedBuildingId = null),
              onSaveDisplayName: (name) => _saveDisplayName(selected, name),
            ),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text('No buildings yet.',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            )
          else
            for (final b in list) _buildingRow(b),
        ],
      ),
    );
  }

  Widget _buildingRow(BuildingModel b) {
    final display = _buildingDisplayText(b);
    final showDisplay = display != b.name;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 3, 6, 3),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration:
                const BoxDecoration(color: _cBuilding, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.name,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
                if (showDisplay)
                  Text(display,
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit, size: 15),
            onPressed: () =>
                setState(() => _selectedBuildingId = b.id?.toString()),
          ),
          IconButton(
            tooltip: 'Locate',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.my_location, size: 15),
            onPressed: () => _locateBuilding(b),
          ),
        ],
      ),
    );
  }

  Widget _routeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _endpointSelector(
            heading: 'From',
            target: _routeFromTarget,
            onTarget: (t) => setState(() => _routeFromTarget = t),
            nodeValue: _routeFromNodeId,
            onNode: (v) => setState(() => _routeFromNodeId = v),
            buildingValue: _routeFromBuildingId,
            onBuilding: (v) => setState(() => _routeFromBuildingId = v),
            buildingHint: 'Start from Building',
          ),
          const SizedBox(height: 14),
          _endpointSelector(
            heading: 'To',
            target: _routeToTarget,
            onTarget: (t) => setState(() => _routeToTarget = t),
            nodeValue: _routeToNodeId,
            onNode: (v) => setState(() => _routeToNodeId = v),
            buildingValue: _routeToBuildingId,
            onBuilding: (v) => setState(() => _routeToBuildingId = v),
            buildingHint: 'Navigate to Building',
          ),
          const SizedBox(height: 16),
          _maroonButton('Find Route', _findRoute),
          if (_routePoints.length >= 2) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _cRoute.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_routeStartLabel != null)
                    Text('From: $_routeStartLabel',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                  if (_routeDestLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('To: $_routeDestLabel',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  const SizedBox(height: 6),
                  Text('Distance: ${_routeDistanceM.toStringAsFixed(0)} m',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    'Estimated time: ~${(_routeDistanceM / _walkSpeedMps / 60).ceil()} min walk',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text('Waypoints: $_routeWaypoints nodes',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: _cBuilding,
                side: const BorderSide(color: _cBuilding),
              ),
              onPressed: () => _clearRoute(),
              child: const Text('Clear Route'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _endpointSelector({
    required String heading,
    required _RouteTarget target,
    required ValueChanged<_RouteTarget> onTarget,
    required String? nodeValue,
    required ValueChanged<String?> onNode,
    required String? buildingValue,
    required ValueChanged<String?> onBuilding,
    required String buildingHint,
  }) {
    final nodes = [..._nodes]..sort((a, b) => a.id.compareTo(b.id));
    // ALL buildings, unfiltered, alphabetical.
    final buildings = [..._buildings]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    String nodeLabel(OutdoorNodeModel n) =>
        n.name == null || n.name!.isEmpty ? n.id : '${n.id} · ${n.name}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(heading,
            style:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        SegmentedButton<_RouteTarget>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11)),
          ),
          segments: const [
            ButtonSegment(
                value: _RouteTarget.building, label: Text('Building')),
            ButtonSegment(value: _RouteTarget.node, label: Text('Node')),
          ],
          selected: {target},
          onSelectionChanged: (s) => onTarget(s.first),
        ),
        const SizedBox(height: 8),
        if (target == _RouteTarget.building) ...[
          DropdownButton<String>(
            isExpanded: true,
            value: buildings.any((b) => b.id?.toString() == buildingValue)
                ? buildingValue
                : null,
            hint: Text(buildingHint),
            items: [
              for (final b in buildings)
                DropdownMenuItem(
                    value: b.id?.toString(), child: Text(b.name)),
            ],
            onChanged: onBuilding,
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              '→ closest linked entrance node is used automatically',
              style:
                  TextStyle(fontSize: 10, color: AppColors.textSecondary),
            ),
          ),
        ] else
          DropdownButton<String>(
            isExpanded: true,
            value:
                nodes.any((n) => n.id == nodeValue) ? nodeValue : null,
            hint: const Text('Select a node'),
            items: [
              for (final n in nodes)
                DropdownMenuItem(value: n.id, child: Text(nodeLabel(n))),
            ],
            onChanged: onNode,
          ),
      ],
    );
  }

  // --- map --------------------------------------------------

  Widget _mapPanel() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off,
                size: 40, color: AppColors.textSecondary),
            const SizedBox(height: 10),
            Text('Could not load the campus graph.\n$_error',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          Positioned.fill(child: _map()),
          if (_loading)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x88FFFFFF),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          if (_banner.isNotEmpty)
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _cBuilding,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 6),
                    ],
                  ),
                  child: Text(
                    _banner,
                    style: const TextStyle(
                        color: _cPathway,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                ),
              ),
            ),
          Positioned(left: 12, bottom: 12, child: _Legend()),
          if (!_loading && _error == null && _mappableNodeCount == 0)
            Positioned(
              top: 56,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    _nodes.isEmpty
                        ? 'No active nodes in outdoor_nodes.'
                        : '${_nodes.length} nodes loaded but none have lat/lng.',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  int get _mappableNodeCount =>
      _nodes.where((n) => n.lat != null && n.lng != null).length;

  Widget _map() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _campusCenter,
        initialZoom: 16,
        minZoom: 13,
        maxZoom: 19,
        cameraConstraint: CameraConstraint.contain(bounds: _campusBounds),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onTap: (_, point) => _handleMapTap(point),
        onPositionChanged: (camera, _) {
          if ((camera.zoom - _currentZoom).abs() > 0.15) {
            setState(() => _currentZoom = camera.zoom);
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: _baseTilesUrl,
          userAgentPackageName: 'com.umindanao.um_ar_admin',
          maxNativeZoom: 20,
        ),
        TileLayer(
          urlTemplate: _overlayTilesUrl,
          userAgentPackageName: 'com.umindanao.um_ar_admin',
          maxNativeZoom: 20,
        ),
        PolylineLayer(polylines: _polylines()),
        MarkerLayer(markers: _arrowMarkers()),
        MarkerLayer(markers: _nodeMarkers()),
        if (_currentZoom >= _buildingLabelShowZoom)
          MarkerLayer(markers: _buildingLabelMarkers()),
      ],
    );
  }

  /// Static building name labels — always at the building's own lat/lng, no
  /// dragging, no fade; shown only when zoomed in (see [_map]). Google-Maps
  /// style: no border/background box, just text with a white halo so it
  /// reads against any tile underneath.
  List<Marker> _buildingLabelMarkers() {
    final markers = <Marker>[];
    for (final b in _buildings) {
      if (b.lat == null || b.lng == null) continue;
      final text = _buildingDisplayText(b);
      markers.add(Marker(
        point: LatLng(b.lat!, b.lng!),
        width: 140,
        height: 40,
        alignment: Alignment.center,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF3D3D3D),
            letterSpacing: 0.2,
            shadows: [
              Shadow(color: Colors.white, blurRadius: 2, offset: Offset(1, 1)),
              Shadow(
                  color: Colors.white, blurRadius: 2, offset: Offset(-1, -1)),
              Shadow(
                  color: Colors.white, blurRadius: 2, offset: Offset(1, -1)),
              Shadow(
                  color: Colors.white, blurRadius: 2, offset: Offset(-1, 1)),
              Shadow(color: Colors.white, blurRadius: 4, offset: Offset(0, 0)),
            ],
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ));
    }
    return markers;
  }

  List<Polyline> _polylines() {
    final lines = <Polyline>[];
    for (final e in _edges) {
      final a = _pos(e.fromNode);
      final b = _pos(e.toNode);
      if (a == null || b == null) continue;
      if (e.isTwoWay) {
        lines.add(Polyline(
          points: [a, b],
          strokeWidth: 2,
          color: Colors.grey.withValues(alpha: 0.7),
        ));
      } else {
        lines.add(Polyline(
          points: [a, b],
          strokeWidth: 2,
          color: Colors.orange,
          pattern: StrokePattern.dashed(segments: const [8.0, 6.0]),
        ));
      }
    }
    if (_routePoints.length >= 2) {
      lines.add(Polyline(
        points: _routePoints,
        strokeWidth: 5,
        color: _cRoute,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
      ));
    }
    return lines;
  }

  List<Marker> _arrowMarkers() {
    final markers = <Marker>[];
    for (final e in _edges) {
      if (e.isTwoWay) continue;
      final a = _pos(e.fromNode);
      final b = _pos(e.toNode);
      if (a == null || b == null) continue;
      final mid = LatLng(
        (a.latitude + b.latitude) / 2,
        (a.longitude + b.longitude) / 2,
      );
      final bearing = _bearing(a, b);
      markers.add(Marker(
        point: mid,
        width: 20,
        height: 20,
        alignment: Alignment.center,
        child: Transform.rotate(
          angle: bearing,
          child: const Icon(Icons.navigation, size: 14, color: Colors.orange),
        ),
      ));
    }
    return markers;
  }

  double _bearing(LatLng a, LatLng b) {
    final lat1 = a.latitudeInRad;
    final lat2 = b.latitudeInRad;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return math.atan2(y, x);
  }

  List<Marker> _nodeMarkers() {
    final showIds = _nodeLabelOpacity > 0;
    final markers = <Marker>[];
    for (final n in _nodes) {
      if (n.lat == null || n.lng == null) continue;
      final selected = n.id == _selectedNodeId;
      final isFrom = n.id == _edgeFromId;
      final isTo = n.id == _edgeToId;
      final isRouteStart = n.id == _routeStartNodeId;
      final isRouteDest = n.id == _routeDestNodeId;
      final isRoutePin = isRouteStart || isRouteDest;
      final highlighted = selected || isFrom || isTo || isRoutePin;
      final ringColor = isFrom || isRouteStart
          ? _cGate
          : isTo
              ? AppColors.errorRed
              : isRouteDest
                  ? _cRoute
                  : selected
                      ? _cPathway
                      : Colors.white;
      final size = isRoutePin ? 16.0 : (highlighted ? 14.0 : 8.0);
      final showLabel = showIds || isRoutePin;
      markers.add(Marker(
        point: LatLng(n.lat!, n.lng!),
        width: 100,
        height: 48,
        // Center the marker box on the exact coordinate…
        alignment: Alignment.center,
        child: IgnorePointer(
          ignoring: _mode == _EditorMode.addNode,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _handleNodeTap(n),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // …and center the dot in the box, so the dot's centre sits
                // exactly on the coordinate no matter what the label does.
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: _nodeColor(n.type),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: ringColor,
                      width: highlighted ? 3 : 1.5,
                    ),
                  ),
                ),
                if (showLabel)
                  Positioned(
                    top: 30,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: isRoutePin ? 1.0 : _nodeLabelOpacity,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 3, vertical: 1),
                          color: Colors.white.withValues(alpha: 0.75),
                          child: Text(n.id,
                              style: const TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ));
    }
    return markers;
  }
}

// --- legend --------------------------------------------------------------

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget row(Color c, String label) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 10)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row(_cGate, 'Gate'),
          row(_cBuilding, 'Building'),
          row(_cIntersection, 'Intersection'),
          row(_cPathway, 'Pathway'),
        ],
      ),
    );
  }
}

// --- selected-building edit panel ----------------------------------------

class _SelectedBuildingPanel extends StatefulWidget {
  final BuildingModel building;
  final VoidCallback onDeselect;
  final Future<void> Function(String displayName) onSaveDisplayName;

  const _SelectedBuildingPanel({
    super.key,
    required this.building,
    required this.onDeselect,
    required this.onSaveDisplayName,
  });

  @override
  State<_SelectedBuildingPanel> createState() =>
      _SelectedBuildingPanelState();
}

class _SelectedBuildingPanelState extends State<_SelectedBuildingPanel> {
  late final TextEditingController _displayName;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _displayName = TextEditingController(
        text: widget.building.displayName ?? widget.building.shortName ?? '');
  }

  @override
  void dispose() {
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    await widget.onSaveDisplayName(_displayName.text.trim());
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.building;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cPathway.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _cPathway.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('Selected Building',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const Spacer(),
              InkWell(
                onTap: widget.onDeselect,
                child: const Icon(Icons.close, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(b.name,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _cBuilding)),
          const SizedBox(height: 10),
          TextField(
            controller: _displayName,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Display Name',
              hintText: 'e.g. BE Bldg, Library, Gym',
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _cBuilding,
                foregroundColor: _cPathway,
              ),
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _cPathway),
                    )
                  : const Text('Save Display Name'),
            ),
          ),
          const Divider(height: 18),
          Text(
            'Building: ${b.lat?.toStringAsFixed(6) ?? '—'}, '
            '${b.lng?.toStringAsFixed(6) ?? '—'}',
            style:
                const TextStyle(fontSize: 10, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// --- node dialog -------------------------------------------------------

class _NodeDialog extends StatefulWidget {
  final LatLng? point;
  final OutdoorNodeModel? existing;
  final BuildingRepository buildingRepo;

  const _NodeDialog({this.point, this.existing, required this.buildingRepo});

  @override
  State<_NodeDialog> createState() => _NodeDialogState();
}

class _NodeDialogState extends State<_NodeDialog> {
  late final TextEditingController _id;
  late final TextEditingController _name;
  late final TextEditingController _entranceLabel;
  late final TextEditingController _indoorNodeId;
  late final TextEditingController _floor;
  late String _type;
  late bool _isActive;
  late bool _isEntrance;
  String? _buildingId;
  String? _qrCodeValue;
  bool _generatingQr = false;
  final _nodeRepo = NodeRepository();

  // Building dropdown data — fetched by the dialog itself, unfiltered.
  List<BuildingModel> _buildings = [];
  bool _loadingBuildings = true;
  Object? _buildingsError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _id = TextEditingController(
        text: e?.id ?? 'p${DateTime.now().millisecondsSinceEpoch}');
    _name = TextEditingController(text: e?.name ?? '');
    _entranceLabel = TextEditingController(text: e?.entranceLabel ?? '');
    _indoorNodeId = TextEditingController(text: e?.indoorNodeId ?? '');
    _floor = TextEditingController(text: (e?.floor ?? 1).toString());
    _type = _nodeTypes.contains(e?.type) ? e!.type! : _nodeTypes.first;
    _isActive = e?.isActive ?? true;
    _isEntrance = e?.isEntrance ?? false;
    _buildingId = e?.buildingId;
    _qrCodeValue = e?.qrCodeValue;
    _fetchBuildings();
  }

  /// Builds the deep-link value, saves it immediately if this node already
  /// exists in Supabase, and shows the QR right away either way — a
  /// brand-new (not-yet-saved) node has it written when the node itself is
  /// first saved via the dialog's Save button.
  Future<void> _generateQr() async {
    final id = _id.text.trim();
    if (id.isEmpty) return;
    if (_buildingId == null || _buildingId!.isEmpty) {
      context.showError('Select a building first');
      return;
    }
    final value = 'UM_AR://$_buildingId/entrance/$id';
    setState(() => _generatingQr = true);
    try {
      if (_isEdit) {
        await _nodeRepo
            .updateNode(widget.existing!.copyWith(qrCodeValue: value));
      }
      if (!mounted) return;
      setState(() => _qrCodeValue = value);
      context.showSuccess(_isEdit
          ? 'QR code generated and saved'
          : 'QR code generated — save the node to store it');
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      if (mounted) setState(() => _generatingQr = false);
    }
  }

  Future<void> _downloadQr() async {
    final value = _qrCodeValue;
    if (value == null || value.isEmpty) return;
    try {
      final painter = QrPainter(
        data: value,
        version: QrVersions.auto,
        gapless: true,
      );
      final imageData = await painter.toImageData(600);
      if (imageData == null) {
        throw Exception('Could not render the QR code image');
      }
      final bytes = imageData.buffer.asUint8List();
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save QR Code',
        fileName: '${_id.text.trim()}_qr.png',
        type: FileType.custom,
        allowedExtensions: const ['png'],
        bytes: bytes,
      );
      if (path == null) return;
      // Some desktop platforms return the chosen path without writing bytes.
      final file = File(path);
      if (!await file.exists() || (await file.length()) == 0) {
        await file.writeAsBytes(bytes, flush: true);
      }
      if (mounted) context.showSuccess('QR code saved to $path');
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  Future<void> _fetchBuildings() async {
    setState(() {
      _loadingBuildings = true;
      _buildingsError = null;
    });
    try {
      // ALL buildings, no noRoomsBuildings filtering.
      final list = await widget.buildingRepo.getAll();
      list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _buildings = list;
        _loadingBuildings = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _buildingsError = e;
        _loadingBuildings = false;
      });
    }
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _entranceLabel.dispose();
    _indoorNodeId.dispose();
    _floor.dispose();
    super.dispose();
  }

  Widget _buildingField() {
    if (_loadingBuildings) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Loading buildings…', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
    }
    if (_buildingsError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Expanded(
              child: Text('Could not load buildings',
                  style: TextStyle(fontSize: 12, color: AppColors.errorRed)),
            ),
            TextButton(
                onPressed: _fetchBuildings, child: const Text('Retry')),
          ],
        ),
      );
    }
    final matches =
        _buildings.any((b) => b.id?.toString() == _buildingId);
    return DropdownButtonFormField<String>(
      // Rebuild the form field once buildings arrive so a pre-linked building
      // is actually shown as selected.
      key: ValueKey('building-dd-${_buildings.length}'),
      initialValue: matches ? _buildingId : null,
      decoration: const InputDecoration(labelText: 'Building'),
      isExpanded: true,
      items: [
        for (final b in _buildings)
          DropdownMenuItem(value: b.id?.toString(), child: Text(b.name)),
      ],
      onChanged: (v) => setState(() => _buildingId = v),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lat = widget.existing?.lat ?? widget.point?.latitude;
    final lng = widget.existing?.lng ?? widget.point?.longitude;
    return AlertDialog(
      title: Text(_isEdit ? 'Edit node ${widget.existing!.id}' : 'New node'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _id,
                readOnly: _isEdit,
                decoration: const InputDecoration(labelText: 'Node ID'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Node Name'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Node Type'),
                items: [
                  for (final t in _nodeTypes)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Is Active'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Is Building Entrance'),
                value: _isEntrance,
                onChanged: (v) => setState(() => _isEntrance = v),
              ),
              if (_isEntrance) ...[
                const SizedBox(height: 4),
                _buildingField(),
                const SizedBox(height: 10),
                TextField(
                  controller: _entranceLabel,
                  decoration: const InputDecoration(
                    labelText: 'Entrance Label',
                    hintText: 'e.g. Main Entrance, Side Entrance, Gate 1',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _floor,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Floor (which floor this entrance leads to)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _indoorNodeId,
                  decoration: const InputDecoration(
                    labelText: 'Links to Indoor Node (optional)',
                    hintText: 'Indoor node id e.g. n1',
                  ),
                ),
                const Divider(height: 24),
                const Text('QR Code',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (_qrCodeValue != null && _qrCodeValue!.isNotEmpty) ...[
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: QrImageView(
                        data: _qrCodeValue!,
                        version: QrVersions.auto,
                        size: 140,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _qrCodeValue!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _cBuilding,
                          side: const BorderSide(color: _cBuilding),
                        ),
                        onPressed: _generatingQr ? null : _generateQr,
                        icon: _generatingQr
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: _cBuilding),
                              )
                            : const Icon(Icons.qr_code, size: 16),
                        label: const Text('Generate QR'),
                      ),
                    ),
                    if (_qrCodeValue != null &&
                        _qrCodeValue!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _cPathway,
                            side: const BorderSide(color: _cPathway),
                          ),
                          onPressed: _downloadQr,
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('Download QR'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              if (lat != null && lng != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Lat ${lat.toStringAsFixed(6)}, Lng ${lng.toStringAsFixed(6)}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final id = _id.text.trim();
            if (id.isEmpty) return;
            Navigator.pop(
              context,
              OutdoorNodeModel(
                id: id,
                name: _name.text.trim().isEmpty ? null : _name.text.trim(),
                type: _type,
                lat: lat,
                lng: lng,
                buildingId: _isEntrance ? _buildingId : null,
                isEntrance: _isEntrance,
                entranceLabel: _isEntrance && _entranceLabel.text.trim().isNotEmpty
                    ? _entranceLabel.text.trim()
                    : null,
                indoorNodeId: _isEntrance && _indoorNodeId.text.trim().isNotEmpty
                    ? _indoorNodeId.text.trim()
                    : null,
                floor: int.tryParse(_floor.text.trim()) ?? 1,
                qrCodeValue: _isEntrance ? _qrCodeValue : null,
                isActive: _isActive,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// --- edge dialog -----------------------------------------------------

class _EdgeDialog extends StatefulWidget {
  final String fromId;
  final String toId;

  const _EdgeDialog({required this.fromId, required this.toId});

  @override
  State<_EdgeDialog> createState() => _EdgeDialogState();
}

class _EdgeDialogState extends State<_EdgeDialog> {
  bool _isTwoWay = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New edge'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _readonlyRow('From', widget.fromId),
            const SizedBox(height: 6),
            _readonlyRow('To', widget.toId),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Is Two Way'),
              value: _isTwoWay,
              onChanged: (v) => setState(() => _isTwoWay = v),
            ),
            if (!_isTwoWay)
              Text(
                'Direction: ${widget.fromId} → ${widget.toId} only',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.warningAmber,
                    fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _isTwoWay),
          child: const Text('Add Edge'),
        ),
      ],
    );
  }

  Widget _readonlyRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}
