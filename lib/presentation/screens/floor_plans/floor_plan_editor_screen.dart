import 'dart:collection';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/floor_scale.dart';
import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/building_repository.dart';
import '../../../data/repositories/entrance_link_repository.dart';
import '../../../data/repositories/facility_repository.dart';
import '../../../data/repositories/floor_distance_repository.dart';
import '../../../data/repositories/floor_plan_repository.dart';
import '../../../data/repositories/indoor_link_cleanup.dart';
import '../../../data/repositories/node_repository.dart';
import '../../../data/repositories/paged_query.dart';
import '../../../data/repositories/room_repository.dart';
import '../../../domain/models/building_model.dart';
import '../../../domain/models/facility_model.dart';
import '../../../domain/models/floor_distance_model.dart';
import '../../../domain/models/floor_plan_model.dart';
import '../../../domain/models/indoor_edge_model.dart';
import '../../../domain/models/indoor_node_model.dart';
import '../../../domain/models/outdoor_node_model.dart';
import '../../../domain/models/room_model.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_banner.dart';
import 'floor_distance_panel.dart';

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

enum _Mode { none, addNode, addEdge, addDistance, moveNodes }

enum _NavFilter { all, navigation, informational }

class FloorPlanEditorScreen extends StatefulWidget {
  final int floorPlanId;

  /// Stands in for the plan image, which a widget test can't download.
  @visibleForTesting
  final Size? testImageSize;

  const FloorPlanEditorScreen({
    super.key,
    required this.floorPlanId,
    this.testImageSize,
  });

  @override
  State<FloorPlanEditorScreen> createState() => _FloorPlanEditorScreenState();
}

class _FloorPlanEditorScreenState extends State<FloorPlanEditorScreen> {
  final _repo = FloorPlanRepository();
  final _nodeRepo = NodeRepository();
  final _entranceRepo = EntranceLinkRepository();
  final _roomRepo = RoomRepository();
  final _facilityRepo = FacilityRepository();
  final _buildingRepo = BuildingRepository();
  final _distanceRepo = FloorDistanceRepository();
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

  /// All buildings and floor plans — for the cross-building dropdowns and
  /// "Connected to GET Building Floor 1" captions.
  List<BuildingModel> _allBuildings = [];
  final Map<int, FloorPlanModel> _allPlans = {};

  /// Every node (any building) carrying a cross_building_ref.
  List<IndoorNodeModel> _crossNodes = [];

  bool _loading = true;
  bool _saving = false;
  Object? _error;

  /// Secondary data (rooms, facilities, …) that failed in the last [_load].
  List<String> _loadFailures = const [];

  late Size? _imageSize = widget.testImageSize;
  double _scale = 1;

  _Tab _tab = _Tab.nodes;
  _Mode _mode = _Mode.none;
  _NavFilter _navFilter = _NavFilter.all;

  String? _selectedNodeId;
  String _search = '';

  String? _edgeFromId;
  String? _edgeToId;

  // distance measurements
  List<FloorDistanceModel> _distances = [];

  /// db/floor_plan_distances.sql hasn't been run yet.
  bool _distancesMissing = false;
  bool _showDistances = false;
  String? _distanceFromId;
  String? _distanceToId;

  /// The row tapped in Check distance; its two nodes are highlighted.
  String? _selectedDistanceId;

  /// Measurements affected by the last saved move, marked in Check distance.
  Set<String> _movedDistanceIds = const {};

  // dragging nodes: positions in [_nodes] change straight away, and nothing
  // is written until Save Moves
  final _moveLog = NodeMoveLog();
  int? _dragPointer;
  String? _dragNodeId;
  Offset _dragStartPos = Offset.zero;

  /// From the pointer to the node's centre, so a node doesn't jump on grab.
  Offset _dragGrabOffset = Offset.zero;

  // test route
  _RtTarget _routeFromTarget = _RtTarget.node;
  _RtTarget _routeToTarget = _RtTarget.roomFacility;
  String? _routeFromNodeId;
  String? _routeToNodeId;
  String? _routeFromLink; // "<id>|<table>"
  String? _routeToLink;
  List<String> _routePath = const [];
  double _routeDistance = 0; // pixels
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
      List<BuildingModel> allBuildings = [];
      List<IndoorNodeModel> crossNodes = [];
      // Secondary data: the editor still opens without it, but the admin
      // must see what is missing instead of silently empty lists.
      final failed = <String>[];
      Future<void> tryLoad(String what, Future<void> Function() load) async {
        try {
          await load();
        } catch (e) {
          debugPrint('floor plan editor: $what failed to load: $e');
          failed.add(what);
        }
      }

      await tryLoad('cross-building links', () async {
        crossNodes = await _repo.getCrossBuildingNodes();
      });
      var distances = <FloorDistanceModel>[];
      var distancesMissing = false;
      await tryLoad('distances', () async {
        try {
          distances = await _distanceRepo.getForFloor(widget.floorPlanId);
        } on FloorDistancesMissing {
          distancesMissing = true;
        }
      });
      final buildingPlans = <int, FloorPlanModel>{};
      final bid = plan.buildingId;
      if (bid != null) {
        for (final p in plans) {
          if (p.buildingId == bid && p.id != null) buildingPlans[p.id!] = p;
        }
        await tryLoad('buildings', () async {
          // Every building, for names; the cross-building picker narrows it.
          final all = await _buildingRepo.getAll(status: ActiveFilter.all);
          allBuildings = all;
          building = all.firstWhere((b) => b.id == bid,
              orElse: () => all.isEmpty
                  ? const BuildingModel(name: 'Building')
                  : all.first);
        });
        await tryLoad('outdoor entrances', () async {
          entrances = await _nodeRepo.getEntranceNodesForBuilding(bid);
        });
        await tryLoad('rooms', () async {
          rooms = await _roomRepo.getByBuilding(bid);
        });
        await tryLoad('facilities', () async {
          facilities = await _facilityRepo.getByBuilding(bid);
        });
        await tryLoad('stair links', () async {
          final all = await _repo.getIndoorNodesForBuilding(bid);
          stairGroupNodes = all
              .where((n) => (n.stairGroup?.isNotEmpty ?? false))
              .toList();
        });
      }

      if (!mounted) return;
      setState(() {
        _loadFailures = failed;
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
        _allBuildings = allBuildings;
        _allPlans
          ..clear()
          ..addAll({for (final p in plans) if (p.id != null) p.id!: p});
        _crossNodes = crossNodes;
        _distances = distances;
        _distancesMissing = distancesMissing;
        _loading = false;
      });
      final url = plan.imageUrl;
      if (url != null && url.isNotEmpty && _imageSize == null) {
        _resolveImage(url);
      }
    } catch (e) {
      debugPrint('floor plan editor load failed: $e');
      if (!mounted) return;
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
      final crossNodes = await _repo.getCrossBuildingNodes();
      if (!mounted) return;
      setState(() {
        _nodes = nodes;
        _edges = edges;
        _crossNodes = crossNodes;
      });
    } catch (e) {
      if (mounted) context.showError(e, onRetry: _refresh);
      return;
    }
    // Stair links are secondary: a failure shows in the banner (with Retry)
    // without throwing away the nodes and edges refreshed above.
    final bid = _plan?.buildingId;
    if (bid == null) return;
    const what = 'stair links';
    try {
      final all = await _repo.getIndoorNodesForBuilding(bid);
      if (!mounted) return;
      setState(() {
        _stairGroupNodes = all
            .where((n) => (n.stairGroup?.isNotEmpty ?? false))
            .toList();
        _loadFailures = [..._loadFailures.where((f) => f != what)];
      });
    } catch (e) {
      debugPrint('floor plan editor: $what failed to refresh: $e');
      if (!mounted) return;
      setState(() => _loadFailures = {..._loadFailures, what}.toList());
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

  /// The floor's scale, or the estimate while it is not calibrated (see
  /// [_scaleCalibrated]) — distances shown with it are marked as estimates.
  double get _metersPerPixel =>
      _plan?.effectiveMetersPerPixel ?? kDefaultMetersPerPixel;

  bool get _scaleCalibrated => _plan?.isScaleCalibrated ?? false;

  double _toMeters(double pixels) => pixels * _metersPerPixel;

  /// Nodes linked to a deleted or inactive room/facility. [_rooms] and
  /// [_facilities] hold the active rows; if either failed to load, every
  /// link would look broken, so nothing is reported until they load.
  List<IndoorNodeModel> get _danglingNodes {
    if (_plan?.buildingId == null ||
        _loadFailures.contains('rooms') ||
        _loadFailures.contains('facilities')) {
      return const [];
    }
    return danglingLinkedNodes(_nodes, _rooms, _facilities);
  }

  Future<void> _clearDanglingLinks() async {
    final nodes = _danglingNodes;
    final ok = await ConfirmDialog.show(
      context,
      title: 'Clear broken links',
      verb: 'clear the room/facility link on',
      itemName: '${nodes.length} '
          '${nodes.length == 1 ? 'node' : 'nodes'}',
      message: 'The rooms or facilities they point at are deleted or '
          'inactive. The nodes stay on the floor plan.',
      confirmLabel: 'Clear links',
    );
    if (!ok) return;
    try {
      await _repo.clearNodeLinks([for (final n in nodes) n.id]);
      await _refresh();
      if (mounted) context.showSuccess('Links cleared');
    } catch (e) {
      if (mounted) context.showError(e, onRetry: _clearDanglingLinks);
    }
  }

  /// Length of an edge in image pixels. Computed from the two nodes' current
  /// positions so routing stays correct even for edges saved by the old
  /// georeferencing workflow (whose stored weight is in meters).
  double _edgePixels(IndoorEdgeModel e) {
    final d = _pixelDist(e.fromNode, e.toNode);
    if (d > 0) return d;
    return (e.weight != null && e.weight! > 0) ? e.weight! : 1.0;
  }

  // --- cross-building links ---------------------------------------------

  /// Weight of the edge joining two cross-building nodes, in pixels.
  static const double _crossBuildingEdgeWeight = 50;

  String _buildingNameOf(int? id) {
    for (final b in _allBuildings) {
      if (b.id == id) return b.name;
    }
    return 'Building #$id';
  }

  /// "GET Building Floor 1".
  String _placeOf(IndoorNodeModel n) {
    final plan = n.floorPlanId == null ? null : _allPlans[n.floorPlanId];
    final floor = plan?.floorNumber ?? n.floor;
    return '${_buildingNameOf(n.buildingId ?? plan?.buildingId)} Floor $floor';
  }

  List<IndoorNodeModel> _crossPartners(IndoorNodeModel n) {
    final ref = n.crossBuildingRef?.trim() ?? '';
    if (ref.isEmpty) return const [];
    return _crossNodes
        .where((o) => o.id != n.id && o.crossBuildingRef?.trim() == ref)
        .toList();
  }

  /// Tooltip/caption for a node's cross-building link; null if it has none.
  String? _crossLinkCaption(IndoorNodeModel n) {
    final ref = n.crossBuildingRef?.trim() ?? '';
    if (ref.isEmpty) return null;
    final partners = _crossPartners(n);
    if (partners.isEmpty) return 'Ref $ref — not linked yet';
    if (partners.length > 1) {
      return 'Ref $ref is used by ${partners.length} other nodes — '
          'make it unique';
    }
    return 'Connected to ${_placeOf(partners.first)}';
  }

  /// After a save: links the node to the other node sharing its
  /// cross_building_ref with one two-way edge, and removes the edge to the
  /// old partner if the ref was changed or cleared.
  Future<void> _syncCrossBuildingLink(
    IndoorNodeModel saved, {
    IndoorNodeModel? previous,
  }) async {
    final ref = saved.crossBuildingRef?.trim() ?? '';
    final oldRef = previous?.crossBuildingRef?.trim() ?? '';
    try {
      if (oldRef.isNotEmpty && oldRef != ref) {
        final oldPartners =
            await _repo.findCrossBuildingPartners(oldRef, excludeId: saved.id);
        for (final p in oldPartners) {
          await _repo.deleteEdgesBetween(saved.id, p.id);
        }
      }
      if (ref.isEmpty) return;

      final partners =
          await _repo.findCrossBuildingPartners(ref, excludeId: saved.id);
      if (!mounted) return;
      if (partners.isEmpty) {
        context.showInfo('Ref ID saved. Connect the other building node with '
            'the same ID to complete the link');
        return;
      }
      if (partners.length > 1) {
        context.showError(
            'Ref ID "$ref" is already used by ${partners.length} other nodes '
            '(${partners.map((p) => p.id).join(', ')}). Use a unique ID per '
            'connection — no edge was created.');
        return;
      }
      final partner = partners.first;
      final where = '${partner.name?.isNotEmpty == true ? partner.name : partner.id}'
          ' in ${_placeOf(partner)}';
      if (await _repo.edgeExistsBetween(saved.id, partner.id)) {
        if (mounted) context.showSuccess('Already connected to $where');
        return;
      }
      await _repo.createIndoorEdge(IndoorEdgeModel(
        fromNode: saved.id,
        toNode: partner.id,
        floorPlanId: widget.floorPlanId,
        weight: _crossBuildingEdgeWeight,
        isTwoWay: true,
      ));
      if (mounted) context.showSuccess('Connected to $where');
    } catch (e) {
      if (mounted) {
        context.showError(e,
            onRetry: () => _syncCrossBuildingLink(saved, previous: previous));
      }
    }
  }

  // --- canvas tap ------------------------------------------------------

  /// A point in the viewer to image pixels.
  Offset _toScene(Offset viewportPoint) => MatrixUtils.transformPoint(
      Matrix4.inverted(_transform.value), viewportPoint);

  /// The node under [scene], or null. Targets stay one size on screen at any
  /// zoom.
  IndoorNodeModel? _nodeAt(Offset scene) {
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
    return hit;
  }

  void _handleCanvasTap(Offset viewportPoint) {
    if (_moving) return;
    final scene = _toScene(viewportPoint);

    if (_mode == _Mode.addNode) {
      // The viewer lets the image be panned past its edges; only accept
      // taps that land on the image so x/y are always valid pixels.
      final size = _imageSize;
      if (size == null ||
          scene.dx < 0 ||
          scene.dy < 0 ||
          scene.dx > size.width ||
          scene.dy > size.height) {
        context.showError('Tap inside the floor plan image to place a node');
        return;
      }
      _openNodeDialog(
        x: scene.dx.roundToDouble(),
        y: scene.dy.roundToDouble(),
      );
      return;
    }

    final hit = _nodeAt(scene);
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
    if (_mode == _Mode.addDistance) {
      final from = _distanceFromId;
      if (from == null) {
        setState(() => _distanceFromId = node.id);
        return;
      }
      final problem =
          validateMeasurePair(from, node.id, _pairPixels(from, node.id));
      if (problem != null) {
        context.showError(problem);
        return;
      }
      setState(() => _distanceToId = node.id);
      await _promptAddDistance(from, node.id);
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
        buildings: _allBuildings,
        floorPlans: _allPlans.values.toList(),
      ),
    );
    if (result == null) return;
    // x/y image pixels are the node's position; no GPS is derived.
    final toSave = result;
    setState(() => _saving = true);
    try {
      await _entranceRepo.checkIndoorSide(toSave);
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
      await _syncCrossBuildingLink(saved, previous: existing);
      await _refresh();
    } catch (e) {
      if (mounted) {
        context.showError(e,
            onRetry: () => _openNodeDialog(x: x, y: y, existing: existing));
      }
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
      await _entranceRepo.syncFromIndoor(node, previous: previous);
    } catch (e) {
      if (mounted) {
        context.showError(e,
            onRetry: () => _syncOutdoorLink(node, previous: previous));
      }
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
    final measured = measurementsTouching(_distances, {node.id}).length;
    try {
      await _repo.deleteIndoorNode(node.id);
      await _entranceRepo.clearLinksToIndoorNode(node.id);
      setState(() {
        _nodes = _nodes.where((n) => n.id != node.id).toList();
        _edges = _edges
            .where((e) => e.fromNode != node.id && e.toNode != node.id)
            .toList();
        if (_selectedNodeId == node.id) _selectedNodeId = null;
      });
      if (!mounted) return;
      context.showSuccess('Node "${node.id}" deleted');
      // The database deleted its measurements with it (see
      // db/floor_plan_distances.sql), which can change the scale.
      if (measured > 0) {
        await _syncDistances(
            done: '$measured '
                '${measured == 1 ? 'measurement' : 'measurements'} removed '
                'with node ${node.id}');
      }
    } catch (e) {
      if (mounted) context.showError(e, onRetry: () => _deleteNode(node));
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
    // Weight is stored in pixels: it stays valid if meters-per-pixel is
    // changed later (meters = weight * meters_per_pixel).
    final px = _pixelDist(fromId, toId);
    final weight = px > 0 ? px : 1.0;
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
      if (mounted) {
        context.showError(e, onRetry: () => _promptAddEdge(fromId, toId));
      }
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
      if (mounted) context.showError(e, onRetry: () => _deleteEdge(edge));
    }
  }

  // --- distance measurements ---------------------------------------

  double? _pairPixels(String a, String b) =>
      nodePixelDistance(_node(a), _node(b));

  String _nodeName(String id) => nodeDisplayName(_node(id), id);

  String _pairName(FloorDistanceModel m) =>
      '${_nodeName(m.nodeAId)} ↔ ${_nodeName(m.nodeBId)}';

  /// From [_distances] and the nodes as they are now, drags included.
  FloorScaleSummary get _scaleSummary => computeFloorScale(_distances, _nodes);

  FloorDistanceModel? get _selectedDistance {
    for (final m in _distances) {
      if (m.id == _selectedDistanceId) return m;
    }
    return null;
  }

  void _toggleAddDistance() {
    if (_distancesMissing) {
      context.showError(kFloorDistancesMissingMessage);
      return;
    }
    setState(() {
      _mode = _mode == _Mode.addDistance ? _Mode.none : _Mode.addDistance;
      _edgeFromId = null;
      _edgeToId = null;
      _distanceFromId = null;
      _distanceToId = null;
    });
  }

  Future<void> _promptAddDistance(String a, String b) async {
    final meters = await showDialog<double>(
      context: context,
      builder: (_) => MeasurementDialog(
        nameA: _nodeName(a),
        nameB: _nodeName(b),
        pixels: _pairPixels(a, b)!,
      ),
    );
    if (!mounted) return;
    setState(() {
      _distanceFromId = null;
      _distanceToId = null;
    });
    if (meters == null) return;
    await _changeDistance(
      () => _distanceRepo.add(
        floorPlanId: widget.floorPlanId,
        nodeAId: a,
        nodeBId: b,
        realMeters: meters,
      ),
      'Distance saved',
    );
  }

  Future<void> _editDistance(MeasurementLine line) async {
    final m = line.measurement;
    final pixels = line.pixels;
    if (pixels == null) {
      context.showError('One of these nodes has no position on the plan');
      return;
    }
    final meters = await showDialog<double>(
      context: context,
      builder: (_) => MeasurementDialog(
        nameA: _nodeName(m.nodeAId),
        nameB: _nodeName(m.nodeBId),
        pixels: pixels,
        initialMeters: m.realMeters,
      ),
    );
    if (meters == null || meters == m.realMeters) return;
    await _changeDistance(
        () => _distanceRepo.setMeters(m.id, meters), 'Distance updated');
  }

  Future<void> _ignoreDistance(MeasurementLine line, bool ignored) =>
      _changeDistance(
        () => _distanceRepo.setIgnored(line.measurement.id, ignored),
        ignored ? 'Measurement ignored' : 'Measurement counted again',
      );

  Future<void> _deleteDistance(MeasurementLine line) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Delete distance',
      itemName: _pairName(line.measurement),
    );
    if (!ok) return;
    await _changeDistance(
      () => _distanceRepo.delete(line.measurement.id),
      'Distance deleted',
    );
  }

  /// Runs [write], then brings the list and the floor's scale up to date.
  Future<void> _changeDistance(
    Future<void> Function() write,
    String done,
  ) async {
    setState(() => _saving = true);
    try {
      await write();
      await _syncDistances(done: done);
    } on FloorDistancesMissing {
      if (mounted) {
        setState(() => _distancesMissing = true);
        context.showError(kFloorDistancesMissingMessage);
      }
    } catch (e) {
      if (mounted) {
        context.showError(e, onRetry: () => _changeDistance(write, done));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Reloads the measurements, saves the scale they give with the usual
  /// save-and-confirm, and says what happened. [done] starts the message.
  /// The list updates even if the scale can't be saved: the panel then shows
  /// the mismatch, with a button to try again.
  Future<void> _syncDistances({required String done}) async {
    try {
      final distances = await _distanceRepo.getForFloor(widget.floorPlanId);
      if (!mounted) return;
      setState(() {
        _distances = distances;
        _distancesMissing = false;
      });
      await _saveMeasuredScale(done: done);
    } on FloorDistancesMissing {
      if (mounted) setState(() => _distancesMissing = true);
    } catch (e) {
      if (mounted) {
        context.showError(e, onRetry: () => _syncDistances(done: done));
      }
    }
  }

  Future<void> _saveMeasuredScale({String done = 'Scale saved'}) async {
    final plan = _plan;
    if (plan == null) return;
    final summary = _scaleSummary;
    final saved = await _distanceRepo.applyScale(plan, summary);
    if (!mounted) return;
    setState(() => _plan = saved);
    if (summary.metersPerPixel == null) {
      context.showInfo('$done. ${unchangedScaleNote(saved)}');
      return;
    }
    final message = '$done. Scale: ${saved.scaleLabel}';
    final warnings = summary.warnings;
    if (warnings.isEmpty) {
      context.showSuccess(message);
    } else {
      context.showWarning('$message. ${warnings.join(' ')}');
    }
  }

  Future<void> _retryMeasuredScale() async {
    try {
      await _saveMeasuredScale();
    } catch (e) {
      if (mounted) context.showError(e, onRetry: _retryMeasuredScale);
    }
  }

  // --- moving nodes -------------------------------------------------

  bool get _moving => _mode == _Mode.moveNodes;

  void _enterMoveMode() {
    // A drawn route would no longer match the nodes it was found on.
    _clearRoute(resetInputs: false);
    setState(() {
      _mode = _Mode.moveNodes;
      _edgeFromId = null;
      _edgeToId = null;
      _distanceFromId = null;
      _distanceToId = null;
    });
  }

  void _placeNode(String id, double x, double y) {
    _nodes = [
      for (final n in _nodes)
        if (n.id == id) n.copyWith(x: x, y: y) else n,
    ];
  }

  void _onDragStart(PointerDownEvent event) {
    if (!_moving || _saving || _dragPointer != null) return;
    if (event.buttons != kPrimaryButton) return;
    final scene = _toScene(event.localPosition);
    final node = _nodeAt(scene);
    if (node == null) return;
    setState(() {
      _dragPointer = event.pointer;
      _dragNodeId = node.id;
      _dragStartPos = Offset(node.x!, node.y!);
      _dragGrabOffset = _dragStartPos - scene;
      _selectedNodeId = node.id;
    });
  }

  void _onDragUpdate(PointerMoveEvent event) {
    final id = _dragNodeId;
    final size = _imageSize;
    if (event.pointer != _dragPointer || id == null || size == null) return;
    final at = _toScene(event.localPosition) + _dragGrabOffset;
    // Whole pixels on the image, like a placed node.
    final x = at.dx.clamp(0.0, size.width).roundToDouble();
    final y = at.dy.clamp(0.0, size.height).roundToDouble();
    setState(() => _placeNode(id, x, y));
  }

  void _onDragEnd(PointerEvent event) {
    final id = _dragNodeId;
    if (event.pointer != _dragPointer || id == null) return;
    final end = _posOf(id);
    setState(() {
      if (end != null && end != _dragStartPos) {
        _moveLog.add(NodeMove(
          id: id,
          fromX: _dragStartPos.dx,
          fromY: _dragStartPos.dy,
          toX: end.dx,
          toY: end.dy,
        ));
      }
      _dragPointer = null;
      _dragNodeId = null;
    });
  }

  void _undoMove() {
    final move = _moveLog.undo();
    if (move == null) return;
    setState(() => _placeNode(move.id, move.fromX, move.fromY));
  }

  void _cancelMoves() {
    setState(() {
      for (var m = _moveLog.undo(); m != null; m = _moveLog.undo()) {
        _placeNode(m.id, m.fromX, m.fromY);
      }
      _mode = _Mode.none;
    });
  }

  /// Writes the dragged positions and the connected edges' new lengths, then
  /// recalculates the scale and says which measurements that touched.
  Future<void> _saveMoves() async {
    final moves = _moveLog.netMoves;
    if (moves.isEmpty) {
      _cancelMoves();
      return;
    }
    final movedIds = {for (final m in moves) m.id};
    final lengths = edgeLengthChanges(_edges, _nodes, movedIds);
    final affected = measurementsTouching(_distances, movedIds);
    setState(() => _saving = true);
    try {
      await _repo.saveNodeMoves(moves, lengths);
      if (!mounted) return;
      setState(() {
        _moveLog.clear();
        _mode = _Mode.none;
        _movedDistanceIds = {for (final m in affected) m.id};
        if (affected.isNotEmpty) _showDistances = true;
      });
      await _refresh();
      if (!mounted) return;
      final moved = '${moves.length} ${moves.length == 1 ? 'node' : 'nodes'} '
          'moved, ${lengths.length} edge '
          '${lengths.length == 1 ? 'length' : 'lengths'} updated';
      if (affected.isEmpty) {
        context.showSuccess(moved);
      } else {
        await _syncDistances(
            done: '$moved. Measurements affected: '
                '${affected.map(_pairName).join(', ')}');
      }
    } catch (e) {
      if (mounted) context.showError(e, onRetry: _saveMoves);
    } finally {
      if (mounted) setState(() => _saving = false);
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
      final w = _edgePixels(e);
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

  /// Shortest route over every start/goal pair; distance is in pixels.
  ({List<String> path, double dist})? _bestRoutes(
    List<String> starts,
    List<String> goals,
  ) {
    ({List<String> path, double dist})? best;
    for (final s in starts) {
      for (final g in goals) {
        if (s == g) continue;
        final path = _dijkstra(s, g);
        if (path == null || path.length < 2) continue;
        var d = 0.0;
        for (var i = 1; i < path.length; i++) {
          d += _pixelDist(path[i - 1], path[i]);
        }
        if (best == null || d < best.dist) best = (path: path, dist: d);
      }
    }
    return best;
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
      _routeArrivingLabel = arriving;
    });
  }

  void _clearRoute({bool resetInputs = true}) {
    setState(() {
      _routePath = const [];
      _routeDistance = 0;
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
      case _Mode.addDistance:
        return _distanceFromId == null
            ? 'Tap the first node to measure'
            : 'Now tap the second node. It needs no edge to the first';
      case _Mode.moveNodes:
        return 'Drag a node to move it. Nothing is saved until Save Moves';
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
        const SizedBox(height: 12),
        if (_error == null && !_loading && _loadFailures.isNotEmpty)
          ErrorBanner(
            message: 'Could not load ${_loadFailures.join(', ')}. '
                'Those lists are empty until this loads.',
            onRetry: _load,
          ),
        if (_error == null && !_loading && _danglingNodes.isNotEmpty)
          ErrorBanner(
            message: '${_danglingNodes.length} '
                '${_danglingNodes.length == 1 ? 'node links' : 'nodes link'} '
                'to a deleted or inactive room/facility: '
                '${_danglingNodes.take(5).map((n) => n.name ?? n.id).join(', ')}'
                '${_danglingNodes.length > 5 ? ', …' : ''}.',
            retryLabel: 'Clear links',
            onRetry: _clearDanglingLinks,
          ),
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
                        if (_showDistances && _plan != null) ...[
                          const SizedBox(width: 16),
                          SizedBox(width: 340, child: _distancePanel()),
                        ],
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _distancePanel() {
    return FloorDistancePanel(
      plan: _plan!,
      summary: _scaleSummary,
      edges: edgeDistanceLines(_edges, _nodes, _metersPerPixel),
      nodes: _nodes,
      tableMissing: _distancesMissing,
      busy: _saving || _moving,
      selectedId: _selectedDistanceId,
      movedIds: _movedDistanceIds,
      onClose: () => setState(() {
        _showDistances = false;
        _selectedDistanceId = null;
      }),
      onSaveScale: _retryMeasuredScale,
      onSelect: (line) => setState(() {
        final id = line.measurement.id;
        _selectedDistanceId = _selectedDistanceId == id ? null : id;
      }),
      onEdit: _editDistance,
      onDelete: _deleteDistance,
      onIgnore: _ignoreDistance,
    );
  }

  Widget _topBar() {
    final title = [
      _building == null ? 'Floor Plan' : buildingOptionLabel(_building!),
      _plan?.floorName ?? (_plan?.floorNumber != null
          ? 'Floor ${_plan!.floorNumber}'
          : ''),
    ].where((s) => s.isNotEmpty).join('  ·  ');
    return Row(
      children: [
        IconButton(
          onPressed: _moving ? null : () => context.go('/floor-plans'),
          icon: const Icon(Icons.arrow_back),
        ),
        Expanded(
          child: Text(title,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis),
        ),
        if (_plan != null) ...[
          OutlinedButton.icon(
            onPressed: _saving || _moving ? null : _editScale,
            icon: Icon(
                _scaleCalibrated ? Icons.straighten : Icons.warning_amber,
                size: 16),
            label: Text('Scale: ${_plan!.scaleLabel}'),
            style: _scaleCalibrated
                ? null
                : OutlinedButton.styleFrom(
                    foregroundColor: AppColors.errorRed),
          ),
          const SizedBox(width: 8),
        ],
        ElevatedButton.icon(
          onPressed: _saving || _moving ? null : _load,
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

  /// Edits this floor plan's meters-per-pixel scale. Edge weights are stored
  /// in pixels, so changing the scale never requires re-saving edges.
  Future<void> _editScale() async {
    final plan = _plan;
    if (plan == null) return;
    final value = await showDialog<double>(
      context: context,
      builder: (_) => _ScaleDialog(initial: plan.metersPerPixel),
    );
    if (value == null || value == plan.metersPerPixel) return;
    setState(() => _saving = true);
    try {
      final saved = await _repo.saveScale(plan.id!, value);
      if (!mounted) return;
      setState(() => _plan = saved);
      if (saved.isScaleCalibrated) {
        context.showSuccess('Scale saved and confirmed: ${saved.scaleLabel}');
      } else {
        context.showWarning(
            'Saved ${saved.scaleLabel}. That is still the default estimate — '
            'measure a known distance to calibrate this floor.');
      }
    } catch (e) {
      if (mounted) context.showError(e, onRetry: _editScale);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
    if (_moving) return _panelBox(_moveTools());
    return _panelBox(
      Column(
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
          const Divider(height: 1),
          _distanceTools(),
        ],
      ),
    );
  }

  /// The sidebar's last section, under every tab.
  Widget _distanceTools() {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _maroonButton(
            _mode == _Mode.addDistance ? 'Cancel Add Distance' : 'Add distance',
            _toggleAddDistance,
            on: _mode == _Mode.addDistance,
          ),
          const SizedBox(height: 8),
          _maroonButton(
            'Check distance',
            () => setState(() => _showDistances = !_showDistances),
            on: _showDistances,
          ),
        ],
      ),
    );
  }

  /// Replaces the tabs while moving, so nothing else can reload or save the
  /// nodes with drags still pending.
  Widget _moveTools() {
    final moves = _moveLog.netMoves;
    final affected =
        measurementsTouching(_distances, {for (final m in moves) m.id});
    final count = moves.length;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Move Nodes',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text(
          'Drag a node to its new position. Connected edges are measured '
          'again when you save.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Text('$count ${count == 1 ? 'node' : 'nodes'} moved, not saved yet',
            style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        _maroonButton('Save Moves', _saveMoves),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _moveLog.isEmpty || _saving ? null : _undoMove,
          child: const Text('Undo'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _saving ? null : _cancelMoves,
          child: const Text('Cancel'),
        ),
        if (affected.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Measurements affected',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          for (final m in affected)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(_pairName(m), style: const TextStyle(fontSize: 11)),
            ),
        ],
      ],
    );
  }

  Widget _panelBox(Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      // The list tiles below paint on the nearest Material, and this box's
      // colour would hide that.
      child: Material(type: MaterialType.transparency, child: child),
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
                  _distanceFromId = null;
                  _distanceToId = null;
                  _edgeFromId = null;
                  _edgeToId = null;
                }),
                on: _mode == _Mode.addNode,
              ),
              const SizedBox(height: 8),
              _maroonButton('Move Nodes', _enterMoveMode),
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
                  crossLinkCaption: _crossLinkCaption(_node(_selectedNodeId)!),
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
      if (mounted) {
        context.showError(
          e,
          onRetry: () => _saveEntranceLink(
              node, linkedRoomId, linkedTable, entranceLabel),
        );
      }
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
              _distanceFromId = null;
              _distanceToId = null;
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
                    final px = _edgePixels(e);
                    return ListTile(
                      dense: true,
                      title: Text('${e.fromNode}  →  ${e.toNode}',
                          style: const TextStyle(fontSize: 12)),
                      subtitle: Row(
                        children: [
                          Text(
                              '${_scaleCalibrated ? '' : '~'}'
                              '${_toMeters(px).toStringAsFixed(1)} m · '
                              '${px.toStringAsFixed(0)} px',
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
    final routeMeters = _toMeters(_routeDistance);
    final walkSeconds = routeMeters / 1.4;

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
                    'Distance: ${routeMeters.toStringAsFixed(1)} m',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${_routeDistance.toStringAsFixed(0)} px × '
                    '$_metersPerPixel m/px',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                  if (!_scaleCalibrated)
                    const Text(
                      'Scale not calibrated — meters and time are '
                      'estimates using 0.05 m/px.',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.errorRed),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    'Estimated time: ~${walkSeconds.ceil()} seconds walk',
                    style: const TextStyle(fontSize: 12),
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

  /// Hover tooltip ("Connected to GET Building Floor 1") on linked nodes.
  Widget _withCrossLinkTooltip(IndoorNodeModel n, Widget child) {
    final caption = _crossLinkCaption(n);
    if (caption == null) return child;
    return Tooltip(message: caption, child: child);
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
    final measured = _selectedDistance;
    Color? highlightOf(String id) => id == _edgeFromId || id == _distanceFromId
        ? _cGreen
        : id == _edgeToId || id == _distanceToId
            ? AppColors.errorRed
            : id == measured?.nodeAId || id == measured?.nodeBId
                ? _cRoute
                : null;

    final viewer = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => _handleCanvasTap(d.localPosition),
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 0.3,
        maxScale: 5.0,
        boundaryMargin: const EdgeInsets.all(100),
        constrained: false,
        panEnabled: _dragNodeId == null,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: widget.testImageSize != null
                    ? const SizedBox.shrink()
                    : CachedNetworkImage(imageUrl: url, fit: BoxFit.fill),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _IndoorEdgePainter(
                    byId: byId,
                    edges: _edges,
                    routePath: _routePath,
                    measureFrom: measured?.nodeAId,
                    measureTo: measured?.nodeBId,
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
                    child: _withCrossLinkTooltip(
                      n,
                      _NodeDot(
                        color: labelColor(n.label),
                        selected: n.id == _selectedNodeId,
                        crossBuilding:
                            (n.crossBuildingRef?.trim() ?? '').isNotEmpty,
                        highlight: highlightOf(n.id),
                      ),
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
                      child: _infoLabel(n, highlightOf(n.id)),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
    // A Listener sees the pointer outside the gesture arena, where the
    // viewer would win the drag and pan the plan instead. A press away from
    // any node still pans.
    return Listener(
      onPointerDown: _onDragStart,
      onPointerMove: _onDragUpdate,
      onPointerUp: _onDragEnd,
      onPointerCancel: _onDragEnd,
      child: viewer,
    );
  }

  Widget _infoLabel(IndoorNodeModel n, Color? highlight) {
    final color = infoTextColor(n.label);
    final num = n.roomNumber?.trim() ?? '';
    final name = n.roomName?.trim() ?? '';
    final fs = _dynamicFontSize; // base 16 → clamp(11, 26)
    final ring = highlight ?? (n.id == _selectedNodeId ? _cGold : null);

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
        border: ring == null ? null : Border.all(color: ring, width: 1.5),
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

  /// Linked to another building — drawn larger with an orange ring.
  final bool crossBuilding;

  const _NodeDot({
    required this.color,
    required this.selected,
    this.highlight,
    this.crossBuilding = false,
  });

  @override
  Widget build(BuildContext context) {
    final ring = highlight ??
        (selected
            ? _cGold
            : crossBuilding
                ? AppColors.crossBuildingOrange
                : Colors.white);
    final ringW = highlight != null || selected || crossBuilding ? 3.0 : 1.5;
    final size = crossBuilding ? 16.0 : 10.0;
    // alignment: center — the 24x24 box is centred on (x, y), and the
    // circle is centred in the box, so its centre sits on the coordinate.
    return Align(
      alignment: Alignment.center,
      child: Container(
        width: size,
        height: size,
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

  /// The measurement picked in Check distance, drawn as a straight line.
  final String? measureFrom;
  final String? measureTo;

  _IndoorEdgePainter({
    required this.byId,
    required this.edges,
    required this.routePath,
    this.measureFrom,
    this.measureTo,
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

    final from = measureFrom == null ? null : p(measureFrom!);
    final to = measureTo == null ? null : p(measureTo!);
    if (from != null && to != null) {
      _dashed(
        canvas,
        from,
        to,
        Paint()
          ..color = _cRoute
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke,
      );
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
      old.routePath != routePath ||
      old.measureFrom != measureFrom ||
      old.measureTo != measureTo;
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.crossBuildingOrange, width: 2.5),
                  ),
                ),
                const SizedBox(width: 4),
                const Text('Cross-building link',
                    style: TextStyle(fontSize: 9)),
              ],
            ),
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

  /// "Connected to GET Building Floor 1" — null if not a cross-building node.
  final String? crossLinkCaption;
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
    this.crossLinkCaption,
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
          Text(
            'Pixel position: x=${n.x?.toStringAsFixed(0) ?? '—'}, '
            'y=${n.y?.toStringAsFixed(0) ?? '—'}',
            style: const TextStyle(
                fontSize: 10, color: AppColors.textSecondary),
          ),
          if (widget.crossLinkCaption != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  const Icon(Icons.swap_horiz,
                      size: 14, color: AppColors.crossBuildingOrange),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.crossLinkCaption!,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.crossBuildingOrange),
                    ),
                  ),
                ],
              ),
            ),
          Text(
            'Is Navigable: ${n.isNavigable ? 'Yes (navigation node)' : 'No (informational)'}',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: n.isNavigable ? _cGreen : AppColors.infoBlue),
          ),
          const Divider(height: 16),

          if (n.isNavigable) ...[
            // Its own Material: the panel's colour would hide the tile's ink.
            Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Is Room Entrance'),
                value: _isRoomEntrance,
                onChanged: (v) => setState(() {
                  _isRoomEntrance = v;
                  if (!v) _link = null;
                }),
              ),
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
                // A link to a row that is gone or inactive is dropped on
                // save; with no lists loaded there is nothing to judge by.
                final keep =
                    (widget.rooms.isEmpty && widget.facilities.isEmpty) ||
                        linkExists(_link, widget.rooms, widget.facilities);
                final parsed = keep ? parseLink(_link) : null;
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

  /// Every building / floor plan — for the cross-building dropdowns.
  final List<BuildingModel> buildings;
  final List<FloorPlanModel> floorPlans;

  const _IndoorNodeDialog({
    this.existing,
    this.x,
    this.y,
    required this.floorPlanId,
    required this.buildingId,
    required this.outdoorEntrances,
    required this.rooms,
    required this.facilities,
    this.buildings = const [],
    this.floorPlans = const [],
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

  /// Set when the last [_fetchLinks] failed; the dropdown then shows the
  /// lists passed in by the editor (possibly stale) under an error + Retry.
  Object? _linksError;

  // ---- cross-building connection ----
  final _floorPlanRepo = FloorPlanRepository();
  late final TextEditingController _crossRef;
  late bool _crossLink;
  int? _crossBuildingId;
  int? _crossFloorPlanId;
  bool _searchingPartner = false;

  /// Result of "Find Connected Node"; null until searched.
  List<IndoorNodeModel>? _partners;

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
    _crossRef = TextEditingController(text: e?.crossBuildingRef ?? '');
    _crossLink = (e?.crossBuildingRef?.trim() ?? '').isNotEmpty;
    if (widget.buildingId != null) _fetchLinks();
    // Editing a linked node: look up its partner to pre-fill the dropdowns.
    if (_crossLink) _findPartner();
  }

  /// Refs are matched exactly, so normalise: trim, upper-case, no spaces.
  static String _normalizeRef(String s) =>
      s.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '_');

  BuildingModel? _buildingById(int? id) {
    for (final b in widget.buildings) {
      if (b.id == id) return b;
    }
    return null;
  }

  FloorPlanModel? _planById(int? id) {
    for (final p in widget.floorPlans) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// "GET Building Floor 1" for a found partner node.
  String _placeOf(IndoorNodeModel n) {
    final plan = _planById(n.floorPlanId);
    final building = _buildingById(n.buildingId ?? plan?.buildingId);
    return '${building?.name ?? 'Building #${n.buildingId}'} '
        'Floor ${plan?.floorNumber ?? n.floor}';
  }

  /// "DPT" from short_name, else the first word of the name.
  String _buildingCode(BuildingModel? b) {
    final s = (b?.shortName?.trim().isNotEmpty ?? false)
        ? b!.shortName!
        : (b?.name.trim().split(RegExp(r'\s+')).first ?? 'BLDG');
    return _normalizeRef(s);
  }

  /// e.g. DPT_GET_LINK_F1, from this floor and the connected building.
  void _suggestRef() {
    final here = _planById(widget.floorPlanId);
    final other = _buildingById(_crossBuildingId);
    if (other == null) {
      context.showInfo('Pick the connected building first');
      return;
    }
    final floor = here?.floorNumber ?? int.tryParse(_floor.text.trim()) ?? 1;
    setState(() {
      _crossRef.text = '${_buildingCode(_buildingById(widget.buildingId))}_'
          '${_buildingCode(other)}_LINK_F$floor';
      _partners = null;
    });
  }

  Future<void> _findPartner() async {
    final ref = _normalizeRef(_crossRef.text);
    if (ref.isEmpty) {
      setState(() => _partners = null);
      return;
    }
    setState(() => _searchingPartner = true);
    try {
      final found = await _floorPlanRepo.findCrossBuildingPartners(ref,
          excludeId: widget.existing?.id ?? _id.text.trim());
      if (!mounted) return;
      setState(() {
        _partners = found;
        _searchingPartner = false;
        // Fill empty dropdowns from a unique match.
        if (found.length == 1 && _crossBuildingId == null) {
          final p = found.first;
          _crossBuildingId = p.buildingId ?? _planById(p.floorPlanId)?.buildingId;
          _crossFloorPlanId = p.floorPlanId;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searchingPartner = false);
      context.showError(e, onRetry: _findPartner);
    }
  }

  Future<void> _fetchLinks() async {
    setState(() {
      _loadingLinks = true;
      _linksError = null;
    });
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
    } catch (e) {
      debugPrint('node dialog: rooms/facilities failed to load: $e');
      if (!mounted) return;
      setState(() {
        _linksError = e;
        _loadingLinks = false;
      });
    }
  }

  @override
  void dispose() {
    for (final c in [
      _id, _name, _entranceLabel, _outdoorNodeId, _roomName, _roomNumber,
      _description, _floor, _hours, _contact, _stairGroup,
      _unityX, _unityY, _unityZ, _crossRef,
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
                _crossBuildingSection(),
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
    // A link to a row that is gone or inactive is dropped on save, unless the
    // lists failed to load and there is nothing to judge by.
    final linkKnown = _linksError != null ||
        _loadingLinks ||
        linkExists(_linkSelection, _rooms, _facilities);
    final link =
        (!nav || roomEntrance) && linkKnown ? parseLink(_linkSelection) : null;
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
        crossBuildingRef: nav &&
                labelIsEntrance &&
                _crossLink &&
                _normalizeRef(_crossRef.text).isNotEmpty
            ? _normalizeRef(_crossRef.text)
            : null,
        unityX: double.tryParse(_unityX.text.trim()),
        unityY: double.tryParse(_unityY.text.trim()),
        unityZ: double.tryParse(_unityZ.text.trim()),
      ),
    );
  }

  /// "Cross Building Connection" — entrance navigation nodes only.
  Widget _crossBuildingSection() {
    final otherBuildings = selectableBuildings(widget.buildings, _crossBuildingId)
        .where((b) => b.id != null && b.id != widget.buildingId)
        .toList();
    final floors = widget.floorPlans
        .where((p) => p.id != null && p.buildingId == _crossBuildingId)
        .toList()
      ..sort((a, b) => (a.floorNumber ?? 0).compareTo(b.floorNumber ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 20),
        const Row(
          children: [
            Icon(Icons.swap_horiz,
                size: 16, color: AppColors.crossBuildingOrange),
            SizedBox(width: 6),
            Text('Cross Building Connection',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Links to another building'),
          value: _crossLink,
          activeThumbColor: AppColors.crossBuildingOrange,
          onChanged: (v) => setState(() => _crossLink = v),
        ),
        if (_crossLink) ...[
          DropdownButtonFormField<int>(
            initialValue: otherBuildings.any((b) => b.id == _crossBuildingId)
                ? _crossBuildingId
                : null,
            isExpanded: true,
            decoration:
                const InputDecoration(labelText: 'Connected Building'),
            items: [
              for (final b in otherBuildings)
                DropdownMenuItem(
                    value: b.id, child: Text(buildingOptionLabel(b))),
            ],
            onChanged: (v) => setState(() {
              _crossBuildingId = v;
              _crossFloorPlanId = null;
            }),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            // Keyed by building so the selection resets when it changes.
            key: ValueKey('cross-floor-$_crossBuildingId'),
            initialValue: floors.any((p) => p.id == _crossFloorPlanId)
                ? _crossFloorPlanId
                : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Connected Floor',
              helperText: _crossBuildingId != null && floors.isEmpty
                  ? 'This building has no floor plans yet'
                  : null,
            ),
            items: [
              for (final p in floors)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(p.floorName?.isNotEmpty == true
                      ? '${p.floorName} (Floor ${p.floorNumber ?? '?'})'
                      : 'Floor ${p.floorNumber ?? '?'}'),
                ),
            ],
            onChanged: (v) => setState(() => _crossFloorPlanId = v),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _crossRef,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Cross Building Ref ID',
              hintText: 'e.g. DPT_GET_CORRIDOR_F1',
              helperText:
                  'Use same ID on both connected nodes in different buildings',
              helperMaxLines: 2,
              suffixIcon: IconButton(
                tooltip: 'Suggest an ID',
                icon: const Icon(Icons.auto_fix_high, size: 18),
                onPressed: _suggestRef,
              ),
            ),
            onChanged: (_) {
              if (_partners != null) setState(() => _partners = null);
            },
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _searchingPartner ? null : _findPartner,
              icon: _searchingPartner
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search, size: 16),
              label: const Text('Find Connected Node'),
            ),
          ),
          if (_partners != null) ...[
            const SizedBox(height: 8),
            _partnerResult(_partners!),
          ],
        ],
      ],
    );
  }

  Widget _partnerResult(List<IndoorNodeModel> partners) {
    final ref = _normalizeRef(_crossRef.text);
    final (IconData icon, Color color, String text) result;
    if (partners.isEmpty) {
      result = (
        Icons.hourglass_empty,
        AppColors.warningAmber,
        'No node with ref $ref yet. Save this node, then give the node in '
            'the other building the same ref.',
      );
    } else if (partners.length > 1) {
      result = (
        Icons.error_outline,
        AppColors.errorRed,
        'Ref $ref is used by ${partners.length} nodes '
            '(${partners.map((p) => p.id).join(', ')}). Each connection needs '
            'its own unique ID.',
      );
    } else {
      final p = partners.first;
      final pBuilding = p.buildingId ?? _planById(p.floorPlanId)?.buildingId;
      final mismatch =
          (_crossBuildingId != null && pBuilding != _crossBuildingId) ||
              (_crossFloorPlanId != null && p.floorPlanId != _crossFloorPlanId);
      result = (
        mismatch ? Icons.warning_amber_rounded : Icons.check_circle,
        mismatch ? AppColors.warningAmber : AppColors.successGreen,
        'Found ${p.name?.isNotEmpty == true ? p.name : p.id} in '
            '${_placeOf(p)}'
            '${mismatch ? ' — not the building/floor selected above' : ''}',
      );
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: result.$2.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: result.$2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(result.$1, size: 16, color: result.$2),
          const SizedBox(width: 6),
          Expanded(child: Text(result.$3, style: const TextStyle(fontSize: 11))),
        ],
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
    final dropdown = DropdownButtonFormField<String>(
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
    final error = _linksError;
    if (error == null) return dropdown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ErrorBanner(
          message: 'Could not load rooms & facilities: $error',
          onRetry: _fetchLinks,
        ),
        dropdown,
      ],
    );
  }
}

/// Single "Meters per pixel" input. Pops the parsed value, or null on cancel.
class _ScaleDialog extends StatefulWidget {
  /// Null when the floor is not calibrated yet.
  final double? initial;

  const _ScaleDialog({required this.initial});

  @override
  State<_ScaleDialog> createState() => _ScaleDialogState();
}

class _ScaleDialogState extends State<_ScaleDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _value =
      TextEditingController(text: widget.initial?.toString() ?? '');

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, double.parse(_value.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Floor Plan Scale'),
      content: SizedBox(
        width: 340,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _value,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Meters per pixel',
                  helperText: widget.initial == null
                      ? 'Not calibrated yet — distances use a '
                          '$kDefaultMetersPerPixel estimate'
                      : widget.initial == kDefaultMetersPerPixel
                          ? 'Still the default $kDefaultMetersPerPixel — '
                              'not a measurement'
                          : null,
                ),
                validator: validateMetersPerPixel,
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 12),
              const Text(
                'Tip: measure a known distance (e.g. a 10 m hallway) in '
                'pixels on the image, then enter 10 ÷ pixels.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
