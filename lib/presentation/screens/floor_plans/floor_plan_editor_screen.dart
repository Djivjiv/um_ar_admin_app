import 'dart:collection';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/building_repository.dart';
import '../../../data/repositories/facility_repository.dart';
import '../../../data/repositories/floor_plan_repository.dart';
import '../../../data/repositories/node_repository.dart';
import '../../../data/repositories/room_repository.dart';
import '../../../domain/models/building_model.dart';
import '../../../domain/models/facility_model.dart';
import '../../../domain/models/floor_plan_model.dart';
import '../../../domain/models/indoor_edge_model.dart';
import '../../../domain/models/indoor_node_model.dart';
import '../../../domain/models/outdoor_node_model.dart';
import '../../../domain/models/room_model.dart';
import '../../widgets/confirm_dialog.dart';

// --- label config ------------------------------------------------------------

const _navLabels = [
  'entrance',
  'pathway',
  'stairs',
  'elevator',
  'girlsRestroom',
  'boyRestroom',
];
const _infoLabels = [
  'room',
  'fireExit',
  'fireExtinguisher',
  'firstAid',
  'laboratory',
  'office',
  'classroom',
  'clinic',
  'library',
  'chapel',
  'cafeteria',
  'parking',
  'emergency',
];
const _allLabels = [..._navLabels, ..._infoLabels];

bool labelIsNavigable(String? label) => _navLabels.contains(label);

/// "Ground Floor", "2nd Floor", "3rd Floor"… from a floor number.
String _floorName(int f) {
  if (f <= 1) return 'Ground Floor';
  final mod100 = f % 100;
  final mod10 = f % 10;
  final suffix = (mod100 >= 11 && mod100 <= 13)
      ? 'th'
      : mod10 == 1
          ? 'st'
          : mod10 == 2
              ? 'nd'
              : mod10 == 3
                  ? 'rd'
                  : 'th';
  return '$f$suffix Floor';
}

Color labelColor(String? label) {
  switch (label) {
    case 'entrance':
      return const Color(0xFF1D9E75);
    case 'pathway':
      return const Color(0xFFC9972C);
    case 'stairs':
      return const Color(0xFF7B1C1C);
    case 'elevator':
      return const Color(0xFF185FA5);
    case 'girlsRestroom':
      return const Color(0xFFE91E8C);
    case 'boyRestroom':
      return const Color(0xFF185FA5);
    case 'room':
      return const Color(0xFF534AB7);
    case 'fireExit':
      return const Color(0xFFD32F2F);
    case 'fireExtinguisher':
      return const Color(0xFFFF6D00);
    case 'firstAid':
      return const Color(0xFFD32F2F);
    case 'laboratory':
      return const Color(0xFF4A148C);
    case 'office':
      return const Color(0xFF0D47A1);
    case 'classroom':
      return const Color(0xFF00897B);
    case 'clinic':
      return const Color(0xFFD32F2F);
    case 'library':
      return const Color(0xFF1565C0);
    case 'chapel':
      return const Color(0xFFC9972C);
    case 'cafeteria':
      return const Color(0xFFFF6D00);
    case 'parking':
      return const Color(0xFF757575);
    case 'emergency':
      return const Color(0xFFFF1744);
    default:
      return const Color(0xFF9E9E9E);
  }
}

/// Text colour for informational (text-only) node labels.
Color infoTextColor(String? label) {
  switch (label) {
    case 'fireExit':
    case 'firstAid':
      return const Color(0xFFD32F2F);
    case 'fireExtinguisher':
      return const Color(0xFFFF5722);
    case 'laboratory':
      return const Color(0xFF4527A0);
    case 'clinic':
      return const Color(0xFFC62828);
    case 'library':
      return const Color(0xFF01579B);
    case 'chapel':
      return const Color(0xFF7B1C1C);
    case 'cafeteria':
      return const Color(0xFFE65100);
    case 'emergency':
      return const Color(0xFFB71C1C);
    case 'room':
    case 'office':
    case 'classroom':
    default:
      return const Color(0xFF1A1A1A);
  }
}

/// camelCase label → Title Case words, e.g. "fireExit" → "Fire Exit".
String prettyLabel(String? label) {
  final s = (label ?? '').trim();
  if (s.isEmpty) return '';
  final spaced = s
      .replaceAllMapped(RegExp(r'(?<=[a-z0-9])(?=[A-Z])'), (_) => ' ')
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .trim();
  return spaced
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

const _cCharcoal = Color(0xFF1A1A1A);
const _cMaroon = Color(0xFF7B1C1C);
const _cGold = Color(0xFFC9972C);
const _cGreen = Color(0xFF1D9E75);
const _cRoute = Color(0xFF4285F4);

// --- combined rooms + facilities link value: "<id>|<table>" ------------------

String? linkValue(String? id, String? table) =>
    (id == null || id.isEmpty || table == null || table.isEmpty)
        ? null
        : '$id|$table';

/// Returns (id, table) or null.
(String, String)? parseLink(String? v) {
  if (v == null || !v.contains('|')) return null;
  final i = v.lastIndexOf('|');
  return (v.substring(0, i), v.substring(i + 1));
}

/// Non-selectable header + one item per room, then per facility.
List<DropdownMenuItem<String>> roomFacilityItems(
  List<RoomModel> rooms,
  List<FacilityModel> facilities,
) {
  DropdownMenuItem<String> header(String text) => DropdownMenuItem<String>(
        enabled: false,
        child: Text(text,
            style: const TextStyle(
                fontStyle: FontStyle.italic,
                color: AppColors.textSecondary,
                fontSize: 12)),
      );
  return [
    if (rooms.isNotEmpty) header('── Rooms ──'),
    for (final r in rooms)
      if (r.id != null)
        DropdownMenuItem(
          value: '${r.id}|rooms',
          child: Text(r.roomname.isEmpty ? 'Room ${r.id}' : r.roomname,
              overflow: TextOverflow.ellipsis),
        ),
    if (facilities.isNotEmpty) header('── Facilities ──'),
    for (final f in facilities)
      if (f.id != null)
        DropdownMenuItem(
          value: '${f.id}|facilities',
          child: Text('${f.roomNumber ?? f.id} — ${f.roomname ?? ''}',
              overflow: TextOverflow.ellipsis),
        ),
  ];
}

bool linkExists(
  String? value,
  List<RoomModel> rooms,
  List<FacilityModel> facilities,
) {
  if (value == null) return false;
  final all = <String>{
    for (final r in rooms) if (r.id != null) '${r.id}|rooms',
    for (final f in facilities) if (f.id != null) '${f.id}|facilities',
  };
  return all.contains(value);
}

/// "301 — Dean's Office" style caption for a linked room/facility.
String linkedCaption(
  String? linkedRoomId,
  String? linkedTable,
  List<RoomModel> rooms,
  List<FacilityModel> facilities,
) {
  if (linkedRoomId == null) return '';
  if (linkedTable == 'facilities') {
    final f = facilities.where((f) => f.id?.toString() == linkedRoomId);
    if (f.isEmpty) return 'Facility $linkedRoomId';
    final ff = f.first;
    return [ff.roomNumber ?? '', ff.roomname ?? '']
        .where((s) => s.isNotEmpty)
        .join(' — ');
  }
  final r = rooms.where((r) => r.id?.toString() == linkedRoomId);
  return r.isEmpty ? 'Room $linkedRoomId' : r.first.roomname;
}

enum _RtTarget { roomFacility, node }

enum _Tab { nodes, edges, route }

enum _Mode { none, addNode, addEdge }

enum _NavFilter { all, navigation, informational }

class FloorPlanEditorScreen extends StatefulWidget {
  final int floorPlanId;

  const FloorPlanEditorScreen({super.key, required this.floorPlanId});

  @override
  State<FloorPlanEditorScreen> createState() => _FloorPlanEditorScreenState();
}

class _FloorPlanEditorScreenState extends State<FloorPlanEditorScreen> {
  final _repo = FloorPlanRepository();
  final _nodeRepo = NodeRepository();
  final _roomRepo = RoomRepository();
  final _facilityRepo = FacilityRepository();
  final _buildingRepo = BuildingRepository();
  final _transform = TransformationController();

  FloorPlanModel? _plan;
  BuildingModel? _building;
  List<IndoorNodeModel> _nodes = [];
  List<IndoorEdgeModel> _edges = [];
  List<OutdoorNodeModel> _outdoorEntrances = [];
  List<RoomModel> _rooms = [];
  List<FacilityModel> _facilities = [];

  /// Floor plans of this node's building, keyed by id → for the Stair Groups
  /// panel's per-floor labels.
  final Map<int, FloorPlanModel> _buildingPlans = {};

  /// Every stair/elevator node in the building that has a stair_group set.
  List<IndoorNodeModel> _stairGroupNodes = [];

  bool _loading = true;
  bool _saving = false;
  Object? _error;

  Size? _imageSize;
  double _scale = 1;

  _Tab _tab = _Tab.nodes;
  _Mode _mode = _Mode.none;
  _NavFilter _navFilter = _NavFilter.all;

  String? _selectedNodeId;
  String _search = '';

  String? _edgeFromId;
  String? _edgeToId;

  // test route
  _RtTarget _routeFromTarget = _RtTarget.node;
  _RtTarget _routeToTarget = _RtTarget.roomFacility;
  String? _routeFromNodeId;
  String? _routeToNodeId;
  String? _routeFromLink; // "<id>|<table>"
  String? _routeToLink;
  List<String> _routePath = const [];
  double _routeDistance = 0;
  bool _routeIsMeters = false;
  String? _routeArrivingLabel;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
    _load();
  }

  void _onTransform() {
    if (!mounted) return;
    setState(() => _scale = _transform.value.getMaxScaleOnAxis());
  }

  /// Google-Maps-style: labels stay readable on screen. They are drawn inside
  /// the scaled InteractiveViewer child, so dividing by [_scale] and clamping
  /// keeps their on-screen size sane.
  double get _dynamicFontSize => (16.0 / _scale).clamp(11.0, 26.0);

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    super.dispose();
  }

  // --- data ---------------------------------------------------------------

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plans = await _repo.getAll();
      final plan = plans.firstWhere((p) => p.id == widget.floorPlanId);
      final nodes = await _repo.getIndoorNodes(widget.floorPlanId);
      final edges = await _repo.getIndoorEdges(widget.floorPlanId);

      BuildingModel? building;
      List<OutdoorNodeModel> entrances = [];
      List<RoomModel> rooms = [];
      List<FacilityModel> facilities = [];
      List<IndoorNodeModel> stairGroupNodes = [];
      final buildingPlans = <int, FloorPlanModel>{};
      final bid = plan.buildingId;
      if (bid != null) {
        for (final p in plans) {
          if (p.buildingId == bid && p.id != null) buildingPlans[p.id!] = p;
        }
        try {
          final all = await _buildingRepo.getAll();
          building = all.firstWhere((b) => b.id == bid,
              orElse: () => all.isEmpty
                  ? const BuildingModel(name: 'Building')
                  : all.first);
        } catch (_) {}
        try {
          entrances = await _nodeRepo.getEntranceNodesForBuilding(bid);
        } catch (_) {}
        try {
          rooms = await _roomRepo.getByBuilding(bid);
        } catch (_) {}
        try {
          facilities = await _facilityRepo.getByBuilding(bid);
        } catch (_) {}
        try {
          final all = await _repo.getIndoorNodesForBuilding(bid);
          stairGroupNodes = all
              .where((n) => (n.stairGroup?.isNotEmpty ?? false))
              .toList();
        } catch (_) {}
      }

      setState(() {
        _plan = plan;
        _building = building;
        _nodes = nodes;
        _edges = edges;
        _outdoorEntrances = entrances;
        _rooms = rooms;
        _facilities = facilities;
        _stairGroupNodes = stairGroupNodes;
        _buildingPlans
          ..clear()
          ..addAll(buildingPlans);
        _loading = false;
      });
      final url = plan.imageUrl;
      if (url != null && url.isNotEmpty) _resolveImage(url);
    } catch (e) {
      debugPrint('floor plan editor load failed: $e');
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    try {
      final nodes = await _repo.getIndoorNodes(widget.floorPlanId);
      final edges = await _repo.getIndoorEdges(widget.floorPlanId);
      final bid = _plan?.buildingId;
      final stairNodes = bid == null
          ? _stairGroupNodes
          : (await _repo.getIndoorNodesForBuilding(bid))
              .where((n) => (n.stairGroup?.isNotEmpty ?? false))
              .toList();
      setState(() {
        _nodes = nodes;
        _edges = edges;
        _stairGroupNodes = stairNodes;
      });
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  void _resolveImage(String url) {
    final stream = NetworkImage(url).resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (mounted && info.image.height != 0) {
          setState(() => _imageSize = Size(
                info.image.width.toDouble(),
                info.image.height.toDouble(),
              ));
        }
        stream.removeListener(listener);
      },
      onError: (_, _) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  // --- lookups -----------------------------------------------------------

  IndoorNodeModel? _node(String? id) {
    if (id == null) return null;
    for (final n in _nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  Offset? _posOf(String? id) {
    final n = _node(id);
    if (n?.x == null || n?.y == null) return null;
    return Offset(n!.x!, n.y!);
  }

  double _pixelDist(String from, String to) {
    final a = _posOf(from);
    final b = _posOf(to);
    if (a == null || b == null) return 0;
    return (a - b).distance;
  }

  /// Converts a pixel position on the floor plan image to a real-world
  /// GPS coordinate, bilinearly interpolated from the plan's four
  /// georeferenced corners. Returns null if the plan isn't georeferenced.
  LatLng? _pixelToLatLng(double? tapX, double? tapY) {
    final plan = _plan;
    final size = _imageSize;
    if (plan == null ||
        size == null ||
        tapX == null ||
        tapY == null ||
        !plan.isGeoreferenced ||
        plan.nwLat == null ||
        plan.nwLng == null ||
        plan.neLat == null ||
        plan.neLng == null ||
        plan.swLat == null ||
        plan.swLng == null ||
        plan.seLat == null ||
        plan.seLng == null ||
        size.width <= 0 ||
        size.height <= 0) {
      return null;
    }

    final relX = (tapX / size.width).clamp(0.0, 1.0);
    final relY = (tapY / size.height).clamp(0.0, 1.0);

    final topLat = plan.nwLat! + relX * (plan.neLat! - plan.nwLat!);
    final topLng = plan.nwLng! + relX * (plan.neLng! - plan.nwLng!);
    final botLat = plan.swLat! + relX * (plan.seLat! - plan.swLat!);
    final botLng = plan.swLng! + relX * (plan.seLng! - plan.swLng!);

    final lat = topLat + relY * (botLat - topLat);
    final lng = topLng + relY * (botLng - topLng);
    return LatLng(lat, lng);
  }

  /// Edge weight in meters (via [Distance]) when both endpoints have real
  /// GPS coordinates (georeferenced floor plan); otherwise falls back to the
  /// original pixel distance, unchanged from before georeferencing existed.
  double _edgeWeight(String fromId, String toId) {
    final from = _node(fromId);
    final to = _node(toId);
    if (from?.lat != null &&
        from?.lng != null &&
        to?.lat != null &&
        to?.lng != null) {
      return const Distance().as(
        LengthUnit.Meter,
        LatLng(from!.lat!, from.lng!),
        LatLng(to!.lat!, to.lng!),
      );
    }
    final a = _posOf(fromId);
    final b = _posOf(toId);
    return (a != null && b != null) ? (a - b).distance : 1.0;
  }

  // --- canvas tap ------------------------------------------------------

  void _handleCanvasTap(Offset viewportPoint) {
    final inverse = Matrix4.inverted(_transform.value);
    final scene = MatrixUtils.transformPoint(inverse, viewportPoint);

    if (_mode == _Mode.addNode) {
      _openNodeDialog(x: scene.dx, y: scene.dy);
      return;
    }

    final scale = _transform.value.getMaxScaleOnAxis();
    final s = scale <= 0 ? 1.0 : scale;
    IndoorNodeModel? hit;
    var bestD = double.infinity;
    for (final n in _nodes) {
      if (n.x == null || n.y == null) continue;
      // Text-only info nodes have a bigger tap target than the 10px dots.
      final hitR = (n.isNavigable ? 22.0 : 55.0) / s;
      final d = (Offset(n.x!, n.y!) - scene).distance;
      if (d < hitR && d < bestD) {
        bestD = d;
        hit = n;
      }
    }
    if (hit != null) {
      _onNodeTapped(hit);
      return;
    }
    setState(() => _selectedNodeId = null);
  }

  Future<void> _onNodeTapped(IndoorNodeModel node) async {
    if (_mode == _Mode.addEdge) {
      if (_edgeFromId == null) {
        setState(() => _edgeFromId = node.id);
        return;
      }
      if (node.id == _edgeFromId) return;
      setState(() => _edgeToId = node.id);
      await _promptAddEdge(_edgeFromId!, node.id);
      return;
    }
    setState(() {
      _selectedNodeId = node.id;
      _tab = _Tab.nodes;
    });
  }

  // --- node CRUD -----------------------------------------------------

  Future<void> _openNodeDialog({
    double? x,
    double? y,
    IndoorNodeModel? existing,
  }) async {
    final result = await showDialog<IndoorNodeModel>(
      context: context,
      builder: (_) => _IndoorNodeDialog(
        existing: existing,
        x: x ?? existing?.x,
        y: y ?? existing?.y,
        floorPlanId: widget.floorPlanId,
        buildingId: _plan?.buildingId,
        outdoorEntrances: _outdoorEntrances,
        rooms: _rooms,
        facilities: _facilities,
      ),
    );
    if (result == null) return;
    // Stamp real GPS coordinates onto the node when the floor plan has been
    // georeferenced — used for lat/lng-based edge weights and future
    // outdoor↔indoor distance calculations. x/y (pixel position) is still
    // the source of truth for where the node is drawn on the image.
    final latLng = _pixelToLatLng(result.x, result.y);
    final toSave = latLng == null
        ? result
        : result.copyWith(lat: latLng.latitude, lng: latLng.longitude);
    setState(() => _saving = true);
    try {
      final IndoorNodeModel saved;
      if (existing == null) {
        saved = await _repo.createIndoorNode(toSave);
        setState(() {
          _nodes = [..._nodes, saved];
          _mode = _Mode.none;
          _selectedNodeId = saved.id;
        });
        if (mounted) context.showSuccess('Node "${saved.id}" added');
      } else {
        saved = await _repo.updateIndoorNode(toSave);
        setState(() {
          _nodes = [
            for (final n in _nodes) if (n.id == saved.id) saved else n,
          ];
        });
        if (mounted) context.showSuccess('Node "${saved.id}" updated');
      }
      await _syncOutdoorLink(saved, previous: existing);
      await _refresh();
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Keeps the outdoor↔indoor entrance link in sync on `outdoor_nodes`.
  Future<void> _syncOutdoorLink(
    IndoorNodeModel node, {
    IndoorNodeModel? previous,
  }) async {
    try {
      final prevOut = previous?.outdoorNodeId;
      final newOut = node.outdoorNodeId;
      if (prevOut != null && prevOut != newOut) {
        await _nodeRepo.setIndoorLink(prevOut, null);
      }
      if (newOut != null && newOut.isNotEmpty) {
        await _nodeRepo.setIndoorLink(newOut, node.id);
      }
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  Future<void> _deleteNode(IndoorNodeModel node) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Delete node',
      itemName: node.id,
      message: 'Delete node ${node.id}? Connected edges will also be deleted.',
    );
    if (!ok) return;
    try {
      await _repo.deleteIndoorNode(node.id);
      if (node.outdoorNodeId != null && node.outdoorNodeId!.isNotEmpty) {
        await _nodeRepo.setIndoorLink(node.outdoorNodeId!, null);
      }
      setState(() {
        _nodes = _nodes.where((n) => n.id != node.id).toList();
        _edges = _edges
            .where((e) => e.fromNode != node.id && e.toNode != node.id)
            .toList();
        if (_selectedNodeId == node.id) _selectedNodeId = null;
      });
      if (mounted) context.showSuccess('Node "${node.id}" deleted');
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  // --- edge CRUD ---------------------------------------------------

  Future<void> _promptAddEdge(String fromId, String toId) async {
    final twoWay = await showDialog<bool>(
      context: context,
      builder: (_) => _EdgeDialog(fromId: fromId, toId: toId),
    );
    if (twoWay == null) {
      setState(() {
        _edgeFromId = null;
        _edgeToId = null;
      });
      return;
    }
    final weight = _edgeWeight(fromId, toId);
    try {
      final edge = await _repo.createIndoorEdge(IndoorEdgeModel(
        fromNode: fromId,
        toNode: toId,
        floorPlanId: widget.floorPlanId,
        weight: weight,
        isTwoWay: twoWay,
      ));
      setState(() {
        _edges = [..._edges, edge];
        _mode = _Mode.none;
        _edgeFromId = null;
        _edgeToId = null;
      });
      if (mounted) context.showSuccess('Edge $fromId → $toId added');
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  Future<void> _deleteEdge(IndoorEdgeModel edge) async {
    if (edge.id == null) return;
    final ok = await ConfirmDialog.show(
      context,
      title: 'Delete edge',
      itemName: '${edge.fromNode} → ${edge.toNode}',
    );
    if (!ok) return;
    try {
      await _repo.deleteIndoorEdge(edge.id!);
      setState(() => _edges = _edges.where((e) => e.id != edge.id).toList());
      if (mounted) context.showSuccess('Edge deleted');
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  // --- dijkstra (navigable nodes only) -----------------------------

  List<String>? _dijkstra(String start, String goal) {
    final navIds = {
      for (final n in _nodes)
        if (n.isNavigable) n.id,
    };
    if (!navIds.contains(start) || !navIds.contains(goal)) return null;

    final adjacency = <String, List<(String, double)>>{};
    void add(String a, String b, double w) {
      (adjacency[a] ??= <(String, double)>[]).add((b, w));
    }

    for (final e in _edges) {
      if (!navIds.contains(e.fromNode) || !navIds.contains(e.toNode)) continue;
      final w = (e.weight != null && e.weight! > 0)
          ? e.weight!
          : _pixelDist(e.fromNode, e.toNode);
      add(e.fromNode, e.toNode, w);
      if (e.isTwoWay) add(e.toNode, e.fromNode, w);
    }

    final dist = <String, double>{for (final id in navIds) id: double.infinity};
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

    if ((dist[goal] ?? double.infinity) == double.infinity) return null;
    final path = <String>[];
    String? step = goal;
    while (step != null) {
      path.insert(0, step);
      step = prev[step];
    }
    return path;
  }

  /// Navigable indoor nodes linked to a given room/facility.
  List<IndoorNodeModel> _entranceNodesForLink(String id, String table) {
    return _nodes
        .where((n) =>
            n.isNavigable &&
            n.linkedRoomId == id &&
            (n.linkedTable ?? 'rooms') == table)
        .toList();
  }

  /// True when every consecutive pair of nodes along [path] has real GPS
  /// coordinates, so the whole route can be measured in meters.
  bool _pathIsGeoreferenced(List<String> path) {
    for (var i = 1; i < path.length; i++) {
      final a = _node(path[i - 1]);
      final b = _node(path[i]);
      if (a?.lat == null || a?.lng == null || b?.lat == null || b?.lng == null) {
        return false;
      }
    }
    return true;
  }

  double _segmentMeters(String from, String to) {
    final a = _node(from);
    final b = _node(to);
    return const Distance()
        .as(LengthUnit.Meter, LatLng(a!.lat!, a.lng!), LatLng(b!.lat!, b.lng!));
  }

  ({List<String> path, double dist, bool isMeters})? _bestRoutes(
    List<String> starts,
    List<String> goals,
  ) {
    ({List<String> path, double d, bool m})? best;
    for (final s in starts) {
      for (final g in goals) {
        if (s == g) continue;
        final path = _dijkstra(s, g);
        if (path == null || path.length < 2) continue;
        final isMeters = _pathIsGeoreferenced(path);
        var d = 0.0;
        for (var i = 1; i < path.length; i++) {
          d += isMeters
              ? _segmentMeters(path[i - 1], path[i])
              : _pixelDist(path[i - 1], path[i]);
        }
        if (best == null || d < best.d) best = (path: path, d: d, m: isMeters);
      }
    }
    if (best == null) return null;
    return (path: best.path, dist: best.d, isMeters: best.m);
  }

  void _findRoute() {
    final fromIsLink = _routeFromTarget == _RtTarget.roomFacility;
    final toIsLink = _routeToTarget == _RtTarget.roomFacility;

    final List<String> starts;
    if (fromIsLink) {
      final parsed = parseLink(_routeFromLink);
      if (parsed == null) return;
      final ns = _entranceNodesForLink(parsed.$1, parsed.$2);
      if (ns.isEmpty) {
        context.showError(
            'No entrance nodes linked to this room yet. Please link entrance '
            'nodes to this room first.');
        return;
      }
      starts = ns.map((n) => n.id).toList();
    } else {
      if (_routeFromNodeId == null) return;
      starts = [_routeFromNodeId!];
    }

    final List<String> goals;
    String? arriving;
    if (toIsLink) {
      final parsed = parseLink(_routeToLink);
      if (parsed == null) return;
      final ns = _entranceNodesForLink(parsed.$1, parsed.$2);
      if (ns.isEmpty) {
        context.showError(
            'No entrance nodes linked to this room yet. Please link entrance '
            'nodes to this room first.');
        return;
      }
      goals = ns.map((n) => n.id).toList();
      arriving = linkedCaption(parsed.$1, parsed.$2, _rooms, _facilities);
    } else {
      if (_routeToNodeId == null) return;
      goals = [_routeToNodeId!];
      final n = _node(_routeToNodeId);
      arriving = 'Node ${n?.id}${n?.name != null ? ' (${n!.name})' : ''}';
    }

    final best = _bestRoutes(starts, goals);
    if (best == null) {
      _clearRoute(resetInputs: false);
      context.showError('No route found between these nodes');
      return;
    }
    setState(() {
      _routePath = best.path;
      _routeDistance = best.dist;
      _routeIsMeters = best.isMeters;
      _routeArrivingLabel = arriving;
    });
  }

  void _clearRoute({bool resetInputs = true}) {
    setState(() {
      _routePath = const [];
      _routeDistance = 0;
      _routeIsMeters = false;
      _routeArrivingLabel = null;
      if (resetInputs) {
        _routeFromNodeId = null;
        _routeToNodeId = null;
        _routeFromLink = null;
        _routeToLink = null;
      }
    });
  }

  String get _banner {
    switch (_mode) {
      case _Mode.addNode:
        return 'Tap on the floor plan to place a node';
      case _Mode.addEdge:
        return _edgeFromId == null
            ? 'Tap FROM node then tap TO node on the floor plan'
            : 'Now tap the TO node';
      case _Mode.none:
        return '';
    }
  }

  // --- build ---------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _topBar(),
        if (!_loading && _error == null && _plan?.isGeoreferenced == false)
          _georeferenceWarningBanner(),
        const SizedBox(height: 12),
        Expanded(
          child: _error != null
              ? _errorView()
              : _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 300, child: _leftPanel()),
                        const SizedBox(width: 16),
                        Expanded(child: _canvasPanel()),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _topBar() {
    final title = [
      _building?.name ?? 'Floor Plan',
      _plan?.floorName ?? (_plan?.floorNumber != null
          ? 'Floor ${_plan!.floorNumber}'
          : ''),
    ].where((s) => s.isNotEmpty).join('  ·  ');
    return Row(
      children: [
        IconButton(
          onPressed: () => context.go('/floor-plans'),
          icon: const Icon(Icons.arrow_back),
        ),
        Expanded(
          child: Text(title,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis),
        ),
        ElevatedButton.icon(
          onPressed: _saving ? null : _load,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save, size: 16),
          label: const Text('Save'),
        ),
      ],
    );
  }

  Widget _georeferenceWarningBanner() {
    final plan = _plan;
    return InkWell(
      onTap: plan == null
          ? null
          : () => context.go('/floor-plans/georeference', extra: {
                'building': _building ??
                    BuildingModel(id: plan.buildingId, name: 'Building'),
                'floorNumber': plan.floorNumber ?? 1,
                'floorLabel':
                    plan.floorName ?? 'Floor ${plan.floorNumber ?? 1}',
                'imageFile': null,
                'existingFloorPlan': plan,
              }),
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.warningAmber.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.warningAmber),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                size: 18, color: AppColors.warningAmber),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'This floor plan is not georeferenced. Nodes will be saved '
                'without GPS coordinates. Tap here to georeference first.',
                style: TextStyle(fontSize: 12, color: _cCharcoal),
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.warningAmber),
          ],
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 40, color: AppColors.textSecondary),
          const SizedBox(height: 10),
          Text('Could not load the floor plan.\n$_error',
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
                color: active ? _cMaroon : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: active ? _cMaroon : AppColors.textSecondary,
              )),
        ),
      ),
    );
  }

  Widget _maroonButton(String label, VoidCallback onPressed, {bool on = false}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: on ? _cGold : _cMaroon,
          foregroundColor: on ? _cMaroon : _cGold,
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }

  Widget _nodesTab() {
    final q = _search.toLowerCase();
    final list = _nodes.where((n) {
      switch (_navFilter) {
        case _NavFilter.navigation:
          if (!n.isNavigable) return false;
        case _NavFilter.informational:
          if (n.isNavigable) return false;
        case _NavFilter.all:
          break;
      }
      if (q.isEmpty) return true;
      return n.id.toLowerCase().contains(q) ||
          (n.name ?? '').toLowerCase().contains(q) ||
          (n.roomName ?? '').toLowerCase().contains(q);
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
                _mode == _Mode.addNode ? 'Cancel Add Node' : 'Add Node',
                () => setState(() {
                  _mode = _mode == _Mode.addNode ? _Mode.none : _Mode.addNode;
                  _edgeFromId = null;
                  _edgeToId = null;
                }),
                on: _mode == _Mode.addNode,
              ),
              const SizedBox(height: 8),
              SegmentedButton<_NavFilter>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 10)),
                ),
                segments: const [
                  ButtonSegment(value: _NavFilter.all, label: Text('All')),
                  ButtonSegment(
                      value: _NavFilter.navigation, label: Text('Nav')),
                  ButtonSegment(
                      value: _NavFilter.informational, label: Text('Info')),
                ],
                selected: {_navFilter},
                onSelectionChanged: (s) =>
                    setState(() => _navFilter = s.first),
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search id / name / room…',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            children: [
              if (_node(_selectedNodeId) != null)
                _SelectedNodePanel(
                  key: ValueKey('sel-$_selectedNodeId'),
                  node: _node(_selectedNodeId)!,
                  rooms: _rooms,
                  facilities: _facilities,
                  saving: _saving,
                  onDeselect: () =>
                      setState(() => _selectedNodeId = null),
                  onSaveEntrance: _saveEntranceLink,
                  onEdit: () => _openNodeDialog(existing: _node(_selectedNodeId)),
                  onDelete: () => _deleteNode(_node(_selectedNodeId)!),
                ),
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

  Future<void> _saveEntranceLink(
    IndoorNodeModel node,
    String? linkedRoomId,
    String? linkedTable,
    String entranceLabel,
  ) async {
    setState(() => _saving = true);
    try {
      final updated = node.copyWith(
        isEntrance: true,
        linkedRoomId: linkedRoomId,
        linkedTable: linkedRoomId == null ? null : (linkedTable ?? 'rooms'),
        entranceLabel: entranceLabel.trim().isEmpty ? null : entranceLabel.trim(),
      );
      final saved = await _repo.updateIndoorNode(updated);
      setState(() {
        _nodes = [
          for (final n in _nodes) if (n.id == saved.id) saved else n,
        ];
      });
      if (mounted) context.showSuccess('Node "${saved.id}" saved');
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _nodeRow(IndoorNodeModel n) {
    final color = labelColor(n.label);
    return InkWell(
      onTap: () => setState(() => _selectedNodeId = n.id),
      child: Container(
        color: _selectedNodeId == n.id
            ? _cGold.withValues(alpha: 0.12)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            // Navigation nodes get a coloured dot; informational nodes don't.
            if (n.isNavigable) ...[
              Container(
                width: 12,
                height: 12,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: n.isNavigable
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(n.id,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis),
                        if ((n.label == 'stairs' || n.label == 'elevator') &&
                            (n.stairGroup?.isNotEmpty ?? false))
                          Text('Group: ${n.stairGroup}',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: _cGold,
                                  fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          n.roomNumber?.isNotEmpty == true
                              ? n.roomNumber!
                              : (n.roomName?.isNotEmpty == true
                                  ? n.roomName!
                                  : (n.name ?? n.id)),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (n.roomName?.isNotEmpty == true &&
                            n.roomNumber?.isNotEmpty == true)
                          Text(n.roomName!,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary),
                              overflow: TextOverflow.ellipsis),
                      ],
                    ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(n.label ?? '—',
                  style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ),
            IconButton(
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit, size: 16),
              onPressed: () => _openNodeDialog(existing: n),
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

  Widget _entrancesPanel() {
    final entrances = _nodes.where((n) => n.isEntrance).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: entrances.isNotEmpty,
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            title: Text('Floor Entrances (${entrances.length})',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold)),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: [
          if (entrances.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text('No entrance nodes on this floor.',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            )
          else
            for (final n in entrances)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${n.id} · ${n.entranceLabel ?? 'Entrance'}',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    if (n.outdoorNodeId != null &&
                        n.outdoorNodeId!.isNotEmpty)
                      Text('→ Outdoor: ${n.outdoorNodeId}',
                          style: const TextStyle(
                              fontSize: 10,
                              color: _cGold,
                              fontWeight: FontWeight.w600))
                    else
                      const Text('→ No outdoor link',
                          style: TextStyle(
                              fontSize: 10,
                              color: AppColors.errorRed,
                              fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
        _stairGroupsPanel(),
      ],
    );
  }

  Widget _stairGroupsPanel() {
    // Group every stair/elevator node in the building by its stair_group.
    final groups = <String, List<IndoorNodeModel>>{};
    for (final n in _stairGroupNodes) {
      groups.putIfAbsent(n.stairGroup!.trim(), () => []).add(n);
    }
    final groupIds = groups.keys.toList()..sort();

    int floorNumberOf(IndoorNodeModel n) {
      final plan = n.floorPlanId == null ? null : _buildingPlans[n.floorPlanId];
      return plan?.floorNumber ?? n.floor;
    }

    String floorLabelOf(IndoorNodeModel n) {
      final plan = n.floorPlanId == null ? null : _buildingPlans[n.floorPlanId];
      if (plan?.floorName != null && plan!.floorName!.isNotEmpty) {
        return plan.floorName!;
      }
      return _floorName(floorNumberOf(n));
    }

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: groupIds.isNotEmpty,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text('Stair/Elevator Groups (${groupIds.length})',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          if (groupIds.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                'No stair_group set on any stairs/elevator node yet.',
                style:
                    TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            )
          else
            for (final gid in groupIds) ...[
              () {
                final nodes = [...groups[gid]!]
                  ..sort((a, b) =>
                      floorNumberOf(a).compareTo(floorNumberOf(b)));
                final floorsLinked =
                    nodes.map(floorNumberOf).toSet().length;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(gid,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _cGold)),
                      for (final n in nodes)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 1),
                          child: Text(
                            '${floorLabelOf(n)} → node ${n.id}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      if (floorsLinked < 2)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '⚠️ $gid only linked to $floorsLinked floor',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.warningAmber,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }(),
            ],
        ],
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
            _mode == _Mode.addEdge ? 'Cancel Add Edge' : 'Add Edge',
            () => setState(() {
              _mode = _mode == _Mode.addEdge ? _Mode.none : _Mode.addEdge;
              _edgeFromId = null;
              _edgeToId = null;
            }),
            on: _mode == _Mode.addEdge,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: list.isEmpty
              ? const Center(
                  child: Text('No edges',
                      style: TextStyle(color: AppColors.textSecondary)))
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = list[i];
                    final dist = (e.weight != null && e.weight! > 0)
                        ? e.weight!
                        : _pixelDist(e.fromNode, e.toNode);
                    return ListTile(
                      dense: true,
                      title: Text('${e.fromNode}  →  ${e.toNode}',
                          style: const TextStyle(fontSize: 12)),
                      subtitle: Row(
                        children: [
                          Text('${dist.toStringAsFixed(0)} px',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textSecondary)),
                          if (!e.isTwoWay) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.warningAmber
                                    .withValues(alpha: 0.18),
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
                  },
                ),
        ),
      ],
    );
  }

  Widget _routeTab() {
    final walkSeconds = _routeIsMeters ? (_routeDistance / 1.4) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _routeEndpoint(
            heading: 'From',
            target: _routeFromTarget,
            onTarget: (t) => setState(() => _routeFromTarget = t),
            nodeValue: _routeFromNodeId,
            onNode: (v) => setState(() => _routeFromNodeId = v),
            linkValue: _routeFromLink,
            onLink: (v) => setState(() => _routeFromLink = v),
          ),
          const SizedBox(height: 14),
          _routeEndpoint(
            heading: 'To',
            target: _routeToTarget,
            onTarget: (t) => setState(() => _routeToTarget = t),
            nodeValue: _routeToNodeId,
            onNode: (v) => setState(() => _routeToNodeId = v),
            linkValue: _routeToLink,
            onLink: (v) => setState(() => _routeToLink = v),
          ),
          const SizedBox(height: 16),
          _maroonButton('Find Route', _findRoute),
          if (_routePath.length >= 2) ...[
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
                  if (_routeArrivingLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('Arriving at: $_routeArrivingLabel',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  Text(
                    _routeIsMeters
                        ? 'Distance: ${_routeDistance.toStringAsFixed(1)} meters'
                        : 'Distance: ${_routeDistance.toStringAsFixed(0)} px',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  if (_routeIsMeters)
                    Text(
                      'Estimated time: ~${walkSeconds.ceil()} seconds walk',
                      style: const TextStyle(fontSize: 12),
                    )
                  else
                    const Text(
                      '(Georeference floor plan for real distances)',
                      style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: AppColors.warningAmber),
                    ),
                  const SizedBox(height: 2),
                  Text('Waypoints: ${_routePath.length} nodes',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: _cMaroon,
                side: const BorderSide(color: _cMaroon),
              ),
              onPressed: () => _clearRoute(),
              child: const Text('Clear Route'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _routeEndpoint({
    required String heading,
    required _RtTarget target,
    required ValueChanged<_RtTarget> onTarget,
    required String? nodeValue,
    required ValueChanged<String?> onNode,
    required String? linkValue,
    required ValueChanged<String?> onLink,
  }) {
    final navNodes = _nodes.where((n) => n.isNavigable).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    String labelFor(IndoorNodeModel n) =>
        n.name == null || n.name!.isEmpty ? n.id : '${n.id} · ${n.name}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(heading,
            style:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        SegmentedButton<_RtTarget>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 10)),
          ),
          segments: const [
            ButtonSegment(
                value: _RtTarget.roomFacility, label: Text('Room/Facility')),
            ButtonSegment(value: _RtTarget.node, label: Text('Node')),
          ],
          selected: {target},
          onSelectionChanged: (s) => onTarget(s.first),
        ),
        const SizedBox(height: 8),
        if (target == _RtTarget.roomFacility) ...[
          DropdownButton<String>(
            isExpanded: true,
            value: linkExists(linkValue, _rooms, _facilities)
                ? linkValue
                : null,
            hint: const Text('Select a room / facility'),
            items: roomFacilityItems(_rooms, _facilities),
            onChanged: onLink,
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('nearest entrance node used automatically',
                style: TextStyle(
                    fontSize: 10, color: AppColors.textSecondary)),
          ),
        ] else
          DropdownButton<String>(
            isExpanded: true,
            value: navNodes.any((n) => n.id == nodeValue) ? nodeValue : null,
            hint: const Text('Select a node'),
            items: [
              for (final n in navNodes)
                DropdownMenuItem(value: n.id, child: Text(labelFor(n))),
            ],
            onChanged: onNode,
          ),
      ],
    );
  }

  // --- canvas -------------------------------------------------

  Widget _canvasPanel() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: _canvas()),
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
                    color: _cMaroon,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 6),
                    ],
                  ),
                  child: Text(_banner,
                      style: const TextStyle(
                          color: _cGold,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ),
              ),
            ),
          Positioned(left: 12, bottom: 12, right: 12, child: _Legend()),
          if (_saving)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x22000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _canvas() {
    final url = _plan?.imageUrl;
    if (url == null || url.isEmpty) {
      return const Center(child: Text('This floor plan has no image'));
    }
    if (_imageSize == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final size = _imageSize!;
    final byId = {for (final n in _nodes) n.id: n};

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => _handleCanvasTap(d.localPosition),
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 0.3,
        maxScale: 5.0,
        boundaryMargin: const EdgeInsets.all(100),
        constrained: false,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CachedNetworkImage(imageUrl: url, fit: BoxFit.fill),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _IndoorEdgePainter(
                    byId: byId,
                    edges: _edges,
                    routePath: _routePath,
                  ),
                ),
              ),
              // Navigation nodes → coloured circle dots (unchanged).
              for (final n in _nodes)
                if (n.isNavigable && n.x != null && n.y != null)
                  Positioned(
                    left: n.x! - 12,
                    top: n.y! - 12,
                    width: 24,
                    height: 24,
                    child: _NodeDot(
                      color: labelColor(n.label),
                      selected: n.id == _selectedNodeId,
                      highlight: n.id == _edgeFromId
                          ? _cGreen
                          : n.id == _edgeToId
                              ? AppColors.errorRed
                              : null,
                    ),
                  ),
              // Navigation node id labels — only when zoomed in past 1.5x.
              if (_scale > 1.5)
                for (final n in _nodes)
                  if (n.isNavigable && n.x != null && n.y != null)
                    Positioned(
                      left: n.x!,
                      top: n.y! + 8,
                      child: FractionalTranslation(
                        translation: const Offset(-0.5, 0),
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: const [
                                BoxShadow(
                                    color: Colors.black26, blurRadius: 3),
                              ],
                            ),
                            child: Text(
                              n.name?.isNotEmpty == true ? n.name! : n.id,
                              style: TextStyle(
                                fontSize: _dynamicFontSize * (12.0 / 16.0),
                                fontWeight: FontWeight.bold,
                                color: _cCharcoal,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
              // Informational nodes → text only, no dot.
              for (final n in _nodes)
                if (!n.isNavigable && n.x != null && n.y != null)
                  Positioned(
                    left: n.x!,
                    top: n.y!,
                    child: FractionalTranslation(
                      translation: const Offset(-0.5, -0.5),
                      child: _infoLabel(n),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoLabel(IndoorNodeModel n) {
    final color = infoTextColor(n.label);
    final num = n.roomNumber?.trim() ?? '';
    final name = n.roomName?.trim() ?? '';
    final fs = _dynamicFontSize; // base 16 → clamp(11, 26)
    final selected = n.id == _selectedNodeId;

    // Text priority: room number → room name → nicely-formatted label.
    final text = num.isNotEmpty
        ? num
        : name.isNotEmpty
            ? name
            : prettyLabel(n.label ?? n.id);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 3),
        ],
        border: selected ? Border.all(color: _cGold, width: 1.5) : null,
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: fs, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

// --- node dot -----------------------------------------------------------

class _NodeDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final Color? highlight;

  const _NodeDot({
    required this.color,
    required this.selected,
    this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    final ring = highlight ?? (selected ? _cGold : Colors.white);
    final ringW = highlight != null || selected ? 3.0 : 1.5;
    // alignment: center — the 24x24 box is centred on (x, y), and the 10px
    // circle is centred in the box, so its centre sits on the coordinate.
    return Align(
      alignment: Alignment.center,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: ring, width: ringW),
        ),
      ),
    );
  }
}

// --- edge painter -----------------------------------------------------

class _IndoorEdgePainter extends CustomPainter {
  final Map<String, IndoorNodeModel> byId;
  final List<IndoorEdgeModel> edges;
  final List<String> routePath;

  _IndoorEdgePainter({
    required this.byId,
    required this.edges,
    required this.routePath,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Offset? p(String id) {
      final n = byId[id];
      if (n?.x == null || n?.y == null) return null;
      return Offset(n!.x!, n.y!);
    }

    final solid = Paint()
      ..color = Colors.grey.withValues(alpha: 0.75)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final oneWay = Paint()
      ..color = Colors.orange
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final e in edges) {
      final a = p(e.fromNode);
      final b = p(e.toNode);
      if (a == null || b == null) continue;
      if (e.isTwoWay) {
        canvas.drawLine(a, b, solid);
      } else {
        _dashed(canvas, a, b, oneWay);
      }
    }

    if (routePath.length >= 2) {
      final route = Paint()
        ..color = _cRoute
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path();
      var started = false;
      for (final id in routePath) {
        final pt = p(id);
        if (pt == null) continue;
        if (!started) {
          path.moveTo(pt.dx, pt.dy);
          started = true;
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(path, route);
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 8.0;
    const gap = 5.0;
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final start = a + dir * d;
      final end = a + dir * math.min(d + dash, total);
      canvas.drawLine(start, end, paint);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _IndoorEdgePainter old) =>
      old.edges != edges ||
      old.byId != byId ||
      old.routePath != routePath;
}

// --- legend -----------------------------------------------------------

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget dotItem(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 9,
                height: 9,
                decoration:
                    BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 9)),
          ],
        );
    Widget textItem(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('A',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: c)),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 9)),
          ],
        );
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 10, runSpacing: 3, children: [
            dotItem(_cGreen, 'Entrance'),
            dotItem(_cGold, 'Pathway'),
            dotItem(_cMaroon, 'Stairs'),
            dotItem(const Color(0xFF185FA5), 'Elevator'),
            dotItem(const Color(0xFFE91E8C), 'Restroom'),
          ]),
          const SizedBox(height: 3),
          Wrap(spacing: 10, runSpacing: 3, children: [
            textItem(_cCharcoal, 'Room/Office'),
            textItem(const Color(0xFFD32F2F), 'Fire Exit'),
            textItem(const Color(0xFFFF5722), 'Fire Extinguisher'),
            textItem(const Color(0xFF4527A0), 'Laboratory'),
          ]),
        ],
      ),
    );
  }
}

// --- selected-node left-panel details -----------------------------------

class _SelectedNodePanel extends StatefulWidget {
  final IndoorNodeModel node;
  final List<RoomModel> rooms;
  final List<FacilityModel> facilities;
  final bool saving;
  final VoidCallback onDeselect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Future<void> Function(
    IndoorNodeModel node,
    String? linkedRoomId,
    String? linkedTable,
    String entranceLabel,
  ) onSaveEntrance;

  const _SelectedNodePanel({
    super.key,
    required this.node,
    required this.rooms,
    required this.facilities,
    required this.saving,
    required this.onDeselect,
    required this.onEdit,
    required this.onDelete,
    required this.onSaveEntrance,
  });

  @override
  State<_SelectedNodePanel> createState() => _SelectedNodePanelState();
}

class _SelectedNodePanelState extends State<_SelectedNodePanel> {
  late final TextEditingController _entranceLabel;
  late bool _isRoomEntrance;
  String? _link;

  IndoorNodeModel get _n => widget.node;

  @override
  void initState() {
    super.initState();
    _entranceLabel = TextEditingController(text: _n.entranceLabel ?? '');
    _isRoomEntrance = _n.linkedRoomId != null && _n.linkedRoomId!.isNotEmpty;
    _link = linkValue(_n.linkedRoomId, _n.linkedTable ?? 'rooms');
  }

  @override
  void dispose() {
    _entranceLabel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = _n;
    final color = labelColor(n.label);
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _cGold.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('Selected Node',
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
          Text(n.id,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold)),
          if (n.name?.isNotEmpty == true)
            Text(n.name!, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(n.label ?? '—',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ),
          ),
          const SizedBox(height: 4),
          if (n.lat != null && n.lng != null)
            Text(
              'GPS: ${n.lat!.toStringAsFixed(6)}, ${n.lng!.toStringAsFixed(6)}',
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary),
            )
          else ...[
            Text(
              'Position: x=${n.x?.toStringAsFixed(1) ?? '—'}, '
              'y=${n.y?.toStringAsFixed(1) ?? '—'}',
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary),
            ),
            const Text(
              '⚠ No GPS — georeference floor plan first',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.warningAmber),
            ),
          ],
          Text(
            'Is Navigable: ${n.isNavigable ? 'Yes (navigation node)' : 'No (informational)'}',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: n.isNavigable ? _cGreen : AppColors.infoBlue),
          ),
          const Divider(height: 16),

          if (n.isNavigable) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Is Room Entrance'),
              value: _isRoomEntrance,
              onChanged: (v) => setState(() {
                _isRoomEntrance = v;
                if (!v) _link = null;
              }),
            ),
            if (_isRoomEntrance) ...[
              TextField(
                controller: _entranceLabel,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Entrance Label',
                  hintText: 'e.g. Main Door, Back Door, Side Entrance',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue:
                    linkExists(_link, widget.rooms, widget.facilities)
                        ? _link
                        : null,
                isExpanded: true,
                decoration: const InputDecoration(
                    isDense: true, labelText: 'Link to Room / Facility'),
                items: roomFacilityItems(widget.rooms, widget.facilities),
                onChanged: (v) => setState(() => _link = v),
              ),
              const SizedBox(height: 12),
              _maroonSaveButton(),
            ],
          ] else ...[
            if (n.roomNumber?.isNotEmpty == true)
              Text(n.roomNumber!,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold)),
            if (n.roomName?.isNotEmpty == true)
              Text(n.roomName!, style: const TextStyle(fontSize: 12)),
            if (n.nodeDescription?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(n.nodeDescription!,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ],
            if (n.operatingHours?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  const Icon(Icons.schedule,
                      size: 12, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(n.operatingHours!,
                          style: const TextStyle(fontSize: 11))),
                ]),
              ),
            if (n.contact?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  const Icon(Icons.phone,
                      size: 12, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(n.contact!,
                          style: const TextStyle(fontSize: 11))),
                ]),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _cMaroon,
                side: const BorderSide(color: _cMaroon),
              ),
              onPressed: widget.onEdit,
              icon: const Icon(Icons.edit, size: 14),
              label: const Text('Edit'),
            ),
          ],

          const Divider(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _cMaroon,
                    side: const BorderSide(color: _cMaroon),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  onPressed: widget.onEdit,
                  icon: const Icon(Icons.edit, size: 14),
                  label: const Text('Edit Node',
                      style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.errorRed,
                    side: const BorderSide(color: AppColors.errorRed),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline, size: 14),
                  label: const Text('Delete Node',
                      style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _maroonSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _cMaroon,
          foregroundColor: _cGold,
        ),
        onPressed: widget.saving
            ? null
            : () {
                final parsed = parseLink(_link);
                widget.onSaveEntrance(
                  _n,
                  parsed?.$1,
                  parsed?.$2,
                  _entranceLabel.text,
                );
              },
        child: widget.saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _cGold))
            : const Text('Save Node'),
      ),
    );
  }
}

// --- edge dialog ----------------------------------------------------

class _EdgeDialog extends StatefulWidget {
  final String fromId;
  final String toId;
  const _EdgeDialog({required this.fromId, required this.toId});

  @override
  State<_EdgeDialog> createState() => _EdgeDialogState();
}

class _EdgeDialogState extends State<_EdgeDialog> {
  bool _twoWay = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New edge'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('From', widget.fromId),
            const SizedBox(height: 6),
            _row('To', widget.toId),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Is Two Way'),
              value: _twoWay,
              onChanged: (v) => setState(() => _twoWay = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _twoWay),
          child: const Text('Add Edge'),
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      );
}

// --- node dialog --------------------------------------------------

class _IndoorNodeDialog extends StatefulWidget {
  final IndoorNodeModel? existing;
  final double? x;
  final double? y;
  final int floorPlanId;
  final int? buildingId;
  final List<OutdoorNodeModel> outdoorEntrances;
  final List<RoomModel> rooms;
  final List<FacilityModel> facilities;

  const _IndoorNodeDialog({
    this.existing,
    this.x,
    this.y,
    required this.floorPlanId,
    required this.buildingId,
    required this.outdoorEntrances,
    required this.rooms,
    required this.facilities,
  });

  @override
  State<_IndoorNodeDialog> createState() => _IndoorNodeDialogState();
}

class _IndoorNodeDialogState extends State<_IndoorNodeDialog> {
  late final TextEditingController _id;
  late final TextEditingController _name;
  late final TextEditingController _entranceLabel;
  late final TextEditingController _outdoorNodeId;
  late final TextEditingController _roomName;
  late final TextEditingController _roomNumber;
  late final TextEditingController _description;
  late final TextEditingController _floor;
  late final TextEditingController _hours;
  late final TextEditingController _contact;
  late final TextEditingController _stairGroup;
  late final TextEditingController _unityX;
  late final TextEditingController _unityY;
  late final TextEditingController _unityZ;

  late String _label;
  late bool _isNavigable;
  late bool _isEntrance;
  late bool _isRoomEntrance;
  String? _outdoorEntranceId;

  /// Combined dropdown value: `<id>|rooms` or `<id>|facilities`.
  String? _linkSelection;

  final _roomRepo = RoomRepository();
  final _facilityRepo = FacilityRepository();
  late List<RoomModel> _rooms;
  late List<FacilityModel> _facilities;
  bool _loadingLinks = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _rooms = widget.rooms;
    _facilities = widget.facilities;
    _id = TextEditingController(
        text: e?.id ?? 'n${DateTime.now().millisecondsSinceEpoch}');
    _name = TextEditingController(text: e?.name ?? '');
    _entranceLabel = TextEditingController(text: e?.entranceLabel ?? '');
    _outdoorNodeId = TextEditingController(text: e?.outdoorNodeId ?? '');
    _roomName = TextEditingController(text: e?.roomName ?? '');
    _roomNumber = TextEditingController(text: e?.roomNumber ?? '');
    _description = TextEditingController(text: e?.nodeDescription ?? '');
    _floor = TextEditingController(text: (e?.floor ?? 1).toString());
    _hours = TextEditingController(text: e?.operatingHours ?? '');
    _contact = TextEditingController(text: e?.contact ?? '');
    _stairGroup = TextEditingController(text: e?.stairGroup ?? '');
    _unityX = TextEditingController(text: e?.unityX?.toString() ?? '');
    _unityY = TextEditingController(text: e?.unityY?.toString() ?? '');
    _unityZ = TextEditingController(text: e?.unityZ?.toString() ?? '');
    _label = _allLabels.contains(e?.label) ? e!.label! : _allLabels.first;
    _isNavigable = e?.isNavigable ?? labelIsNavigable(_label);
    _isEntrance = e?.isEntrance ?? false;
    _isRoomEntrance =
        e?.linkedRoomId != null && e!.linkedRoomId!.isNotEmpty;
    _outdoorEntranceId = e?.outdoorNodeId;
    _linkSelection = linkValue(e?.linkedRoomId, e?.linkedTable ?? 'rooms');
    if (widget.buildingId != null) _fetchLinks();
  }

  Future<void> _fetchLinks() async {
    setState(() => _loadingLinks = true);
    try {
      final rooms = await _roomRepo.getByBuilding(widget.buildingId!);
      final facilities =
          await _facilityRepo.getByBuilding(widget.buildingId!);
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _facilities = facilities;
        _loadingLinks = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingLinks = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _id, _name, _entranceLabel, _outdoorNodeId, _roomName, _roomNumber,
      _description, _floor, _hours, _contact, _stairGroup,
      _unityX, _unityY, _unityZ,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onLabelChanged(String? v) {
    if (v == null) return;
    setState(() {
      _label = v;
      // Changing the label re-applies the label's default navigability.
      _isNavigable = labelIsNavigable(v);
      if (!_isNavigable) _isEntrance = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final x = widget.x;
    final y = widget.y;
    return AlertDialog(
      title: Text(_isEdit ? 'Edit node ${widget.existing!.id}' : 'New node'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                initialValue: _label,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Label'),
                items: [
                  for (final l in _allLabels)
                    DropdownMenuItem(value: l, child: Text(l)),
                ],
                onChanged: _onLabelChanged,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (_isNavigable ? _cGreen : AppColors.infoBlue)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _isNavigable ? 'Navigation Node' : 'Informational Node',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _isNavigable ? _cGreen : AppColors.infoBlue,
                    ),
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Navigable (used in pathfinding)'),
                value: _isNavigable,
                onChanged: (v) => setState(() {
                  _isNavigable = v;
                  if (!v) _isEntrance = false;
                }),
              ),
              if (x != null && y != null)
                Text('x ${x.toStringAsFixed(1)}, y ${y.toStringAsFixed(1)}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),

              // ---- stair / elevator group (label == stairs|elevator) ----
              if (_label == 'stairs' || _label == 'elevator') ...[
                const Divider(height: 20),
                TextField(
                  controller: _stairGroup,
                  decoration: const InputDecoration(
                    labelText: 'Stair/Elevator Group ID',
                    hintText: 'e.g. BE_STAIRS_A, BE_ELEVATOR_1',
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Use the same group ID for the same staircase/elevator '
                    'across all floors.\n'
                    'e.g. Left staircase on every floor = BE_STAIRS_A',
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _cGold.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _cGold),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: _cGold, size: 16),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Use consistent naming across floors:\n'
                          'Stairs: {BUILDING}_STAIRS_{A/B/C}\n'
                          'Elevator: {BUILDING}_ELEVATOR_{1/2}',
                          style: TextStyle(fontSize: 11, color: _cGold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ---- entrance fields (navigation + label == entrance) ----
              if (_isNavigable && _label == 'entrance') ...[
                const Divider(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Is Building Entrance'),
                  value: _isEntrance,
                  onChanged: (v) => setState(() => _isEntrance = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Is Room Entrance'),
                  value: _isRoomEntrance,
                  onChanged: (v) => setState(() {
                    _isRoomEntrance = v;
                    if (!v) _linkSelection = null;
                  }),
                ),
                if (_isEntrance || _isRoomEntrance) ...[
                  const SizedBox(height: 4),
                  TextField(
                    controller: _entranceLabel,
                    decoration: const InputDecoration(
                      labelText: 'Entrance Label',
                      hintText: 'e.g. Main Door, Back Door, Side Entrance',
                    ),
                  ),
                ],
                if (_isEntrance) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _outdoorNodeId,
                    decoration: const InputDecoration(
                      labelText: 'Links to Outdoor Node',
                      hintText: 'Outdoor node id e.g. p45',
                    ),
                    onChanged: (v) => setState(() {
                      final match = widget.outdoorEntrances
                          .any((n) => n.id == v.trim());
                      _outdoorEntranceId = match ? v.trim() : _outdoorEntranceId;
                    }),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: widget.outdoorEntrances
                            .any((n) => n.id == _outdoorEntranceId)
                        ? _outdoorEntranceId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Outdoor Node (building entrances)'),
                    items: [
                      for (final n in widget.outdoorEntrances)
                        DropdownMenuItem(
                          value: n.id,
                          child: Text(
                              '${n.id} · ${n.entranceLabel ?? n.name ?? ''}'),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      _outdoorEntranceId = v;
                      _outdoorNodeId.text = v ?? '';
                    }),
                  ),
                ],
                if (_isRoomEntrance) ...[
                  const SizedBox(height: 10),
                  _linkToRoomDropdown(),
                ],
              ],

              // ---- informational fields ----
              if (!_isNavigable) ...[
                const Divider(height: 20),

                // Link to Room/Facility (optional) — always visible, sits
                // below the Label dropdown and above Room Number.
                _linkToRoomDropdown(),
                const SizedBox(height: 12),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Is Room Entrance'),
                  value: _isRoomEntrance,
                  onChanged: (v) => setState(() => _isRoomEntrance = v),
                ),
                if (_isRoomEntrance) ...[
                  const SizedBox(height: 4),
                  TextField(
                    controller: _entranceLabel,
                    decoration: const InputDecoration(
                      labelText: 'Entrance Label',
                      hintText: 'e.g. Main Door, Back Door, Side Entrance',
                    ),
                  ),
                ],

                // ---- room detail fields (always shown) ----
                const Divider(height: 20),
                TextField(
                  controller: _roomNumber,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Room Number',
                    hintText: 'e.g. 301, 102-A',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _roomName,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Room Name',
                    hintText: 'e.g. Computer Laboratory 1',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _description,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'e.g. 40-seat computer lab',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _floor,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Floor'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _hours,
                  decoration: const InputDecoration(
                    labelText: 'Operating Hours',
                    hintText: 'e.g. 8AM - 5PM Mon-Fri',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _contact,
                  decoration: const InputDecoration(
                    labelText: 'Contact',
                    hintText: 'e.g. (082) XXX-XXXX',
                  ),
                ),
              ],

              // ---- AR settings (Unity coordinates, any node) ----
              const SizedBox(height: 8),
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('AR Settings',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _unityX,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            decoration:
                                const InputDecoration(labelText: 'Unity X'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _unityY,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            decoration:
                                const InputDecoration(labelText: 'Unity Y'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _unityZ,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            decoration:
                                const InputDecoration(labelText: 'Unity Z'),
                          ),
                        ),
                      ],
                    ),
                  ],
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
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save() {
    final id = _id.text.trim();
    if (id.isEmpty) return;
    final nav = _isNavigable;
    final labelIsEntrance = _label == 'entrance';
    final buildingEntrance = nav && labelIsEntrance && _isEntrance;
    // Room entrance applies to informational nodes and entrance nav nodes.
    final roomEntrance = _isRoomEntrance && (!nav || labelIsEntrance);
    final isEntrance = buildingEntrance || roomEntrance;
    final outId = buildingEntrance
        ? (_outdoorNodeId.text.trim().isEmpty
            ? null
            : _outdoorNodeId.text.trim())
        : null;
    // Informational nodes link via the always-visible dropdown; entrance nav
    // nodes link only when the Is Room Entrance toggle is on.
    final link = (!nav || roomEntrance) ? parseLink(_linkSelection) : null;
    Navigator.pop(
      context,
      IndoorNodeModel(
        id: id,
        floorPlanId: widget.floorPlanId,
        buildingId: widget.buildingId,
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        label: _label,
        x: widget.x ?? widget.existing?.x,
        y: widget.y ?? widget.existing?.y,
        isNavigable: nav,
        isEntrance: isEntrance,
        entranceLabel: isEntrance && _entranceLabel.text.trim().isNotEmpty
            ? _entranceLabel.text.trim()
            : null,
        outdoorNodeId: outId,
        roomName: !nav && _roomName.text.trim().isNotEmpty
            ? _roomName.text.trim()
            : null,
        roomNumber: !nav && _roomNumber.text.trim().isNotEmpty
            ? _roomNumber.text.trim()
            : null,
        nodeDescription: !nav && _description.text.trim().isNotEmpty
            ? _description.text.trim()
            : null,
        floor: int.tryParse(_floor.text.trim()) ?? 1,
        linkedRoomId: link?.$1,
        linkedTable: link?.$2,
        operatingHours: !nav && _hours.text.trim().isNotEmpty
            ? _hours.text.trim()
            : null,
        contact:
            !nav && _contact.text.trim().isNotEmpty ? _contact.text.trim() : null,
        stairGroup: (_label == 'stairs' || _label == 'elevator') &&
                _stairGroup.text.trim().isNotEmpty
            ? _stairGroup.text.trim()
            : null,
        unityX: double.tryParse(_unityX.text.trim()),
        unityY: double.tryParse(_unityY.text.trim()),
        unityZ: double.tryParse(_unityZ.text.trim()),
      ),
    );
  }

  Widget _linkToRoomDropdown() {
    final rooms = _rooms;
    final facilities = _facilities;
    if (_loadingLinks) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Loading rooms & facilities…',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      );
    }
    const noneValue = '__none__';
    return DropdownButtonFormField<String>(
      initialValue: linkExists(_linkSelection, rooms, facilities)
          ? _linkSelection
          : noneValue,
      isExpanded: true,
      decoration: const InputDecoration(
          labelText: 'Link to Room/Facility (optional)'),
      items: [
        const DropdownMenuItem<String>(
          value: noneValue,
          child: Text('None — label only'),
        ),
        ...roomFacilityItems(rooms, facilities),
      ],
      onChanged: (v) {
        setState(() {
          if (v == null || v == noneValue) {
            _linkSelection = null;
            _roomNumber.clear();
            _roomName.clear();
            return;
          }
          _linkSelection = v;
          final parts = parseLink(v);
          if (parts == null) return;
          if (parts.$2 == 'rooms') {
            final r = rooms.firstWhere(
              (r) => r.id?.toString() == parts.$1,
              orElse: () => const RoomModel(roomname: ''),
            );
            _roomName.text = r.roomname;
            _roomNumber.text = (r.floor ?? '').isNotEmpty
                ? 'Floor ${r.floor}'
                : '';
          } else {
            final f = facilities.firstWhere(
              (f) => f.id?.toString() == parts.$1,
              orElse: () => const FacilityModel(),
            );
            _roomName.text = f.roomname ?? '';
            _roomNumber.text = f.roomNumber ?? '';
          }
        });
      },
    );
  }
}
