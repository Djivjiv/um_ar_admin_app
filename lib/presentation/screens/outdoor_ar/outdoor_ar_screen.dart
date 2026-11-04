import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/maptiler_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/ar_network_check.dart';
import '../../../core/utils/entrance_links.dart';
import '../../../core/utils/geo_utils.dart';
import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/building_repository.dart';
import '../../../data/repositories/entrance_link_repository.dart';
import '../../../data/repositories/outdoor_ar_repository.dart';
import '../../../data/repositories/paged_query.dart';
import '../../../domain/models/building_model.dart';
import '../../../domain/models/outdoor_ar_edge_model.dart';
import '../../../domain/models/outdoor_ar_node_model.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/maptiler_key_notice.dart';
import 'entrance_status_section.dart';

// --- tile sources -----------------------------------------------------------

const _mapTilerKey = MapTilerConfig.apiKey;

class _TileSource {
  final String label;
  final String url;

  /// Highest zoom the server actually has; beyond it tiles are upscaled
  /// (overzoom) so the map never goes blank up to [_maxZoom].
  final int maxNativeZoom;
  final String attribution;
  const _TileSource(this.label, this.url, this.maxNativeZoom, this.attribution);
}

enum _BaseLayer { maptilerSatellite, esriImagery, openStreetMap }

const _baseSources = <_BaseLayer, _TileSource>{
  _BaseLayer.maptilerSatellite: _TileSource(
    'MapTiler Satellite',
    'https://api.maptiler.com/maps/satellite/{z}/{x}/{y}.jpg?key=$_mapTilerKey',
    20,
    '© MapTiler © OpenStreetMap contributors',
  ),
  _BaseLayer.esriImagery: _TileSource(
    'Esri World Imagery',
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    19,
    'Tiles © Esri — Esri, Maxar, Earthstar Geographics, and the GIS User Community',
  ),
  _BaseLayer.openStreetMap: _TileSource(
    'OpenStreetMap',
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    19,
    '© OpenStreetMap contributors',
  ),
};

/// The existing UM campus overlay tileset (same as the Campus Map Editor).
const _umOverlay = _TileSource(
  'UM campus overlay',
  'https://api.maptiler.com/tiles/019fff21-f053-72a0-838d-683bbccd7aa7/{z}/{x}/{y}.webp?key=$_mapTilerKey',
  20,
  'UM overlay © MapTiler',
);

const _maxZoom = 21.0;

const _prefBaseLayer = 'outdoor_ar.base_layer';
const _prefUmOverlay = 'outdoor_ar.um_overlay';
const _prefUmOpacity = 'outdoor_ar.um_opacity';
const _prefShowDistances = 'outdoor_ar.show_distances';
const _prefMaxEdgeM = 'outdoor_ar.max_edge_m';

// --- campus + rules -----------------------------------------------------------

// UM Matina campus extent.
const _campusNorth = 7.0705229;
const _campusSouth = 7.0638081;
const _campusEast = 125.5986040;
const _campusWest = 125.5915322;

const _campusCenter = LatLng(
  (_campusNorth + _campusSouth) / 2,
  (_campusEast + _campusWest) / 2,
);
final _campusBounds = LatLngBounds(
  const LatLng(_campusSouth, _campusWest),
  const LatLng(_campusNorth, _campusEast),
);

/// How far past the campus edge the camera may pan.
const _campusPaddingM = 150.0;
final _panBounds = LatLngBounds(
  LatLng(_campusSouth - _campusPaddingM / 110540,
      _campusWest - _campusPaddingM / (111320 * math.cos(_campusCenter.latitudeInRad))),
  LatLng(_campusNorth + _campusPaddingM / 110540,
      _campusEast + _campusPaddingM / (111320 * math.cos(_campusCenter.latitudeInRad))),
);
final _cameraConstraint = _CampusCameraConstraint(_panBounds);

/// At 16 the whole padded campus (~1.1 × 1.0 km) fits in the map panel;
/// further out only shows unrelated city.
const _minZoom = 16.0;

final _campusFit = CameraFit.bounds(
  bounds: _campusBounds,
  padding: const EdgeInsets.all(24),
  minZoom: _minZoom,
);

/// Points further than this from campus get a "far from campus" warning.
const _farFromCampusM = 2000.0;

/// Default for the "Max edge length (m)" setting — edges over the limit are
/// drawn amber/dashed and listed as warnings.
const _defaultMaxEdgeM = 6.0;

/// Edge length labels are hidden below this zoom to avoid clutter.
const _distanceLabelZoom = 18.0;

const _cWithinLimit = Color(0xFF00C853);
const _cOverLimit = Color(0xFFFF1744);

const _defaultEmoji = '📍';
const _defaultArrivalRadiusM = 8.0;

const _cBuilding = Color(0xFF7B1C1C);
const _cPathway = Color(0xFFC9972C);
const _cPath = Color(0xFF4285F4);
const _cJunction = Color(0xFF8E24AA);
const _cEdge = Color(0xFFFFD54F);
const _cSelected = Color(0xFF00E5FF);
const _cConnectFrom = Color(0xFF1D9E75);

Color _typeColor(String type) {
  switch (type) {
    case 'building':
      return _cBuilding;
    case 'junction':
      return _cJunction;
    case 'path':
    default:
      return _cPath;
  }
}

String _typeLabel(String type) => switch (type) {
      'building' => 'Building',
      'junction' => 'Junction',
      _ => 'Path',
    };

double _distM(LatLng a, LatLng b) =>
    haversineMeters(a.latitude, a.longitude, b.latitude, b.longitude);

double _distFromCampusM(double lat, double lng) =>
    haversineMeters(lat, lng, _campusCenter.latitude, _campusCenter.longitude);

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

LatLng _midpoint(LatLng a, LatLng b) {
  final m = geoMidpoint(a.latitude, a.longitude, b.latitude, b.longitude);
  return LatLng(m.lat, m.lng);
}

enum _Tab { nodes, edges, buildings, check }

/// [measure] is entered from the map controls, not the mode buttons.
enum _Mode { select, addNode, connect, measure }

class OutdoorArScreen extends StatefulWidget {
  const OutdoorArScreen({super.key});

  @override
  State<OutdoorArScreen> createState() => _OutdoorArScreenState();
}

class _OutdoorArScreenState extends State<OutdoorArScreen> {
  final _repo = OutdoorArRepository();
  final _buildingRepo = BuildingRepository();
  final _entranceRepo = EntranceLinkRepository();
  final _mapController = MapController();
  final _mapKey = GlobalKey();

  /// Lat/lng under the mouse — a notifier so hovering doesn't rebuild the map.
  final _cursor = ValueNotifier<LatLng?>(null);

  /// Whether the mouse is over the map itself; the bottom bar keeps the last
  /// position (so its copy button is reachable) but the live line hides.
  final _cursorOnMap = ValueNotifier<bool>(false);

  /// Insertion-ordered (by created_at from the repository).
  final Map<String, OutdoorArNodeModel> _nodes = {};
  List<OutdoorArEdgeModel> _edges = [];
  /// Active buildings: what the Check and Building AR tabs work on.
  List<BuildingModel> _buildings = [];

  /// Every building, so a node linked to an inactive one keeps its name.
  List<BuildingModel> _allBuildings = [];

  /// Building entrances for the Check tab; null until loaded. They are campus
  /// map nodes, so they load apart from the AR network and fail on their own.
  List<EntranceStatusRow>? _entranceRows;
  Object? _entrancesError;

  /// Set when buildings failed to load in [_load]; the Check tab shows it,
  /// since "no building lacks a node" would otherwise be a false all-clear.
  Object? _buildingsError;
  bool _loading = true;
  Object? _error;

  _Tab _tab = _Tab.nodes;
  _Mode _mode = _Mode.select;
  bool _autoConnect = true;

  String? _selectedNodeId;
  String? _selectedEdgeId;
  String _nodeSearch = '';
  bool _onlyLongEdges = false;
  int _isolatedCursor = 0;

  // node drag
  String? _dragNodeId;
  LatLng? _dragPos;

  /// A save is in flight.
  bool _busy = false;

  // layers (remembered per browser via SharedPreferences)
  // Without a key MapTiler tiles can't load, so start on one that can.
  _BaseLayer _base = MapTilerConfig.isConfigured
      ? _BaseLayer.maptilerSatellite
      : _BaseLayer.esriImagery;
  bool _showUmOverlay = true;
  double _umOpacity = 0.6;
  bool _layersOpen = false;

  // distances (also remembered)
  bool _showDistances = true;
  double _maxEdgeM = _defaultMaxEdgeM;
  final _maxEdgeCtrl =
      TextEditingController(text: _fmt(_defaultMaxEdgeM));
  String? _maxEdgeError;

  // measure tool
  LatLng? _measureA;
  LatLng? _measureB;

  /// "Add by coordinates" section in the side panel.
  bool _coordsOpen = false;

  StreamSubscription<MapEvent>? _mapEventSub;

  double _currentZoom = 17;
  static const double _labelShowZoom = 18.0;

  // building AR settings
  String? _arBuildingId;
  double? _previewRadiusM;

  @override
  void initState() {
    super.initState();
    _restoreLayerPrefs();
    _load();
    // A window/panel resize changes the viewport without going through the
    // camera constraint — re-apply it so the view stays on campus.
    _mapEventSub = _mapController.mapEventStream.listen((event) {
      if (event is! MapEventNonRotatedSizeChange) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final camera = _mapController.camera;
        final fixed = _cameraConstraint.constrain(camera);
        if (fixed.center != camera.center) {
          _mapController.move(fixed.center, fixed.zoom);
        }
      });
    });
  }

  @override
  void dispose() {
    _mapEventSub?.cancel();
    _cursor.dispose();
    _cursorOnMap.dispose();
    _maxEdgeCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // --- layer prefs ---------------------------------------------------------

  bool _layerAvailable(_BaseLayer layer) =>
      MapTilerConfig.isConfigured || layer != _BaseLayer.maptilerSatellite;

  Future<void> _restoreLayerPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final base = prefs.getString(_prefBaseLayer);
      if (!mounted) return;
      setState(() {
        final saved = _BaseLayer.values.firstWhere((b) => b.name == base,
            orElse: () => _base);
        if (_layerAvailable(saved)) _base = saved;
        _showUmOverlay = prefs.getBool(_prefUmOverlay) ?? _showUmOverlay;
        _umOpacity =
            (prefs.getDouble(_prefUmOpacity) ?? _umOpacity).clamp(0.1, 1.0);
        _showDistances = prefs.getBool(_prefShowDistances) ?? _showDistances;
        final max = prefs.getDouble(_prefMaxEdgeM);
        if (max != null && parseEdgeLimit(max.toString()) != null) {
          _maxEdgeM = max;
          _maxEdgeCtrl.text = _fmt(max);
        }
      });
    } catch (e) {
      debugPrint('Outdoor AR layer prefs unavailable: $e');
    }
  }

  Future<void> _saveLayerPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefBaseLayer, _base.name);
      await prefs.setBool(_prefUmOverlay, _showUmOverlay);
      await prefs.setDouble(_prefUmOpacity, _umOpacity);
      await prefs.setBool(_prefShowDistances, _showDistances);
      await prefs.setDouble(_prefMaxEdgeM, _maxEdgeM);
    } catch (e) {
      debugPrint('Outdoor AR layer prefs not saved: $e');
    }
  }

  void _onMaxEdgeChanged(String v) {
    final limit = parseEdgeLimit(v);
    setState(() {
      if (limit == null) {
        _maxEdgeError = '${_fmt(minEdgeLimitM)}–${_fmt(maxEdgeLimitM)} m';
      } else {
        _maxEdgeError = null;
        _maxEdgeM = limit;
      }
    });
    if (limit != null) _saveLayerPrefs();
  }

  // --- data --------------------------------------------------------------

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final nodes = await _repo.getNodes();
      final edges = await _repo.getEdges();
      // Buildings feed the link dropdown / AR panel only — don't fail the
      // whole screen if they can't be read.
      List<BuildingModel> buildings = [];
      Object? buildingsError;
      try {
        buildings = await _buildingRepo.getAll(status: ActiveFilter.all);
      } catch (be) {
        debugPrint('buildings fetch failed (dropdowns will be empty): $be');
        buildingsError = be;
      }
      if (!mounted) return;
      setState(() {
        _nodes
          ..clear()
          ..addEntries(nodes.where((n) => n.id != null).map((n) => MapEntry(n.id!, n)));
        _edges = edges;
        _buildings = selectableBuildings(buildings, null);
        _allBuildings = buildings;
        _buildingsError = buildingsError;
        _loading = false;
        _entranceRows = null;
        _entrancesError = null;
        if (!_nodes.containsKey(_selectedNodeId)) _selectedNodeId = null;
        if (_edgeById(_selectedEdgeId) == null) _selectedEdgeId = null;
        // An empty network starts in "add" mode: tapping the map adds nodes,
        // with the coordinates form open as the other way in.
        if (_nodes.isEmpty) {
          _mode = _Mode.addNode;
          _coordsOpen = true;
        }
      });
    } catch (e) {
      debugPrint('Outdoor AR load failed: $e');
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
      return;
    }
    await _loadEntrances();
  }

  Future<void> _loadEntrances() async {
    setState(() {
      _entranceRows = null;
      _entrancesError = null;
    });
    try {
      final rows = await _entranceRepo.getStatusList(
        // With no building list, show every entrance rather than none.
        activeBuildingIds: _buildingsError != null
            ? null
            : {for (final b in _buildings) ?b.id},
      );
      if (mounted) setState(() => _entranceRows = rows);
    } catch (e) {
      if (mounted) setState(() => _entrancesError = e);
    }
  }

  bool get _entrancesNeedWork =>
      _entrancesError != null ||
      (_entranceRows?.any((r) => !r.isLinked) ?? false);

  // --- lookups -------------------------------------------------------------

  LatLng? _pos(String? nodeId) {
    if (nodeId != null && nodeId == _dragNodeId && _dragPos != null) {
      return _dragPos;
    }
    final n = _nodes[nodeId];
    return n == null ? null : LatLng(n.lat, n.lng);
  }

  OutdoorArEdgeModel? _edgeById(String? id) {
    if (id == null) return null;
    for (final e in _edges) {
      if (e.id == id) return e;
    }
    return null;
  }

  BuildingModel? _buildingById(int? id) {
    if (id == null) return null;
    for (final b in _allBuildings) {
      if (b.id == id) return b;
    }
    return null;
  }

  String _buildingDisplayText(BuildingModel b) {
    if ((b.arLabel ?? '').isNotEmpty) return b.arLabel!;
    if ((b.displayName ?? '').isNotEmpty) return b.displayName!;
    if ((b.shortName ?? '').isNotEmpty) return b.shortName!;
    return b.name;
  }

  String _nodeName(String? id) {
    final n = _nodes[id];
    if (n == null) return 'Unknown node';
    if ((n.label ?? '').isNotEmpty) return n.label!;
    final b = _buildingById(n.buildingId);
    if (b != null) return _buildingDisplayText(b);
    return '${_typeLabel(n.nodeType)} ${n.id!.substring(0, 6)}';
  }

  String _edgeLabel(OutdoorArEdgeModel e) =>
      '${_nodeName(e.fromNode)} — ${_nodeName(e.toNode)}';

  int _degree(String id) => _edges.where((e) => e.touches(id)).length;

  List<OutdoorArNodeModel> get _isolatedNodes =>
      [for (final n in _nodes.values) if (_degree(n.id!) == 0) n];

  /// Current length (follows a node while it's being dragged).
  double? _edgeLengthM(OutdoorArEdgeModel e) {
    final a = _pos(e.fromNode);
    final b = _pos(e.toNode);
    if (a == null || b == null) return null;
    return _distM(a, b);
  }

  /// Over the "Max edge length" setting.
  bool _isLong(OutdoorArEdgeModel e) =>
      exceedsEdgeLimit(_edgeLengthM(e) ?? 0, _maxEdgeM);

  /// Totals for the network summary.
  ({double total, double longest, int over}) get _edgeStats {
    var total = 0.0;
    var longest = 0.0;
    var over = 0;
    for (final e in _edges) {
      final len = _edgeLengthM(e) ?? 0;
      total += len;
      longest = math.max(longest, len);
      if (exceedsEdgeLimit(len, _maxEdgeM)) over++;
    }
    return (total: total, longest: longest, over: over);
  }

  /// Where the live "next edge" line starts: the selected node in Add /
  /// Connect mode (Add only when it will auto-connect), or the first
  /// measure point.
  LatLng? get _liveLineStart {
    switch (_mode) {
      case _Mode.addNode:
        return _autoConnect ? _pos(_selectedNodeId) : null;
      case _Mode.connect:
        return _pos(_selectedNodeId);
      case _Mode.measure:
        return _measureB == null ? _measureA : null;
      case _Mode.select:
        return null;
    }
  }

  // --- geometry --------------------------------------------------------

  /// Local planar metres around [origin] — accurate enough at campus scale.
  Offset _toLocal(LatLng p, LatLng origin) => Offset(
        (p.longitude - origin.longitude) *
            111320 *
            math.cos(origin.latitudeInRad),
        (p.latitude - origin.latitude) * 110540,
      );

  double _distToSegmentM(LatLng p, LatLng a, LatLng b) {
    final pa = _toLocal(a, p);
    final ab = _toLocal(b, p) - pa;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    var t = len2 == 0 ? 0.0 : (-pa.dx * ab.dx - pa.dy * ab.dy) / len2;
    t = t.clamp(0.0, 1.0);
    return (pa + ab * t).distance;
  }

  double _metersPerPixel(LatLng at) =>
      156543.03392 *
      math.cos(at.latitudeInRad) /
      math.pow(2, _mapController.camera.zoom);

  OutdoorArEdgeModel? _nearestEdge(LatLng p, {required double maxPx}) {
    final maxM = maxPx * _metersPerPixel(p);
    OutdoorArEdgeModel? best;
    var bestD = double.infinity;
    for (final e in _edges) {
      final a = _pos(e.fromNode);
      final b = _pos(e.toNode);
      if (a == null || b == null) continue;
      final d = _distToSegmentM(p, a, b);
      if (d < bestD) {
        bestD = d;
        best = e;
      }
    }
    return bestD <= maxM ? best : null;
  }

  LatLng? _globalToLatLng(Offset global) {
    final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return _mapController.camera.screenOffsetToLatLng(box.globalToLocal(global));
  }

  void _focus(LatLng p) =>
      _mapController.move(p, math.max(_mapController.camera.zoom, 18.5));

  // --- modes / selection -----------------------------------------------------

  void _setMode(_Mode m) {
    setState(() {
      _mode = m;
      _selectedEdgeId = null;
      _measureA = null;
      _measureB = null;
      // Connect mode starts fresh: the next tapped node is the "from".
      if (m == _Mode.connect) _selectedNodeId = null;
    });
  }

  void _toggleMeasure() =>
      _setMode(_mode == _Mode.measure ? _Mode.select : _Mode.measure);

  /// Measure tool: first click sets A, second sets B, a third starts over.
  void _measureTap(LatLng p) {
    setState(() {
      if (_measureA == null || _measureB != null) {
        _measureA = p;
        _measureB = null;
      } else {
        _measureB = p;
      }
    });
  }

  void _selectNode(String id, {bool focus = false}) {
    setState(() {
      _selectedNodeId = id;
      _selectedEdgeId = null;
      _tab = _Tab.nodes;
    });
    if (focus) {
      final p = _pos(id);
      if (p != null) _focus(p);
    }
  }

  void _selectEdge(OutdoorArEdgeModel e, {bool fit = false}) {
    setState(() {
      _selectedEdgeId = e.id;
      _selectedNodeId = null;
    });
    final a = _pos(e.fromNode);
    final b = _pos(e.toNode);
    if (fit && a != null && b != null) {
      _mapController.fitCamera(CameraFit.coordinates(
        coordinates: [a, b],
        padding: const EdgeInsets.all(80),
        maxZoom: 19.5,
      ));
    }
  }

  String get _banner {
    switch (_mode) {
      case _Mode.addNode:
        final from = _autoConnect && _selectedNodeId != null
            ? ' (connects to ${_nodeName(_selectedNodeId)})'
            : '';
        return 'Click the map to add a node$from';
      case _Mode.connect:
        return _selectedNodeId == null
            ? 'Click the FROM node'
            : 'Click the node to connect to ${_nodeName(_selectedNodeId)}';
      case _Mode.measure:
        if (_measureA == null) return 'Measure: click the first point';
        if (_measureB == null) return 'Measure: click the second point';
        return 'Distance ${formatDistanceM(_distM(_measureA!, _measureB!))}'
            ' — click to measure again';
      case _Mode.select:
        return '';
    }
  }

  void _handleMapTap(LatLng p) {
    if (_dragNodeId != null || _busy) return;
    switch (_mode) {
      case _Mode.addNode:
        _createNodeAt(p);
      case _Mode.connect:
        setState(() => _selectedNodeId = null);
      case _Mode.measure:
        _measureTap(p);
      case _Mode.select:
        final edge = _nearestEdge(p, maxPx: 10);
        setState(() {
          _selectedNodeId = null;
          _selectedEdgeId = edge?.id;
          if (edge != null) _tab = _Tab.edges;
        });
    }
  }

  Future<void> _handleNodeTap(OutdoorArNodeModel n) async {
    if (_busy) return;
    if (_mode == _Mode.measure) {
      // Snap the measurement to the node.
      _measureTap(LatLng(n.lat, n.lng));
      return;
    }
    if (_mode == _Mode.connect) {
      final from = _selectedNodeId;
      if (from == null) {
        setState(() => _selectedNodeId = n.id);
      } else if (from == n.id) {
        setState(() => _selectedNodeId = null);
      } else {
        // Chain: the tapped node becomes the next "from".
        final ok = await _createEdge(from, n.id!);
        if (ok && mounted) setState(() => _selectedNodeId = n.id);
      }
      return;
    }
    _selectNode(n.id!);
  }

  // --- node CRUD -------------------------------------------------------------

  Future<OutdoorArNodeModel?> _insertNode(OutdoorArNodeModel model) async {
    setState(() => _busy = true);
    try {
      final saved = await _repo.createNode(model);
      if (!mounted) return saved;
      setState(() => _nodes[saved.id!] = saved);
      return saved;
    } catch (e) {
      if (mounted) context.showError(e, onRetry: () => _insertNode(model));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createNodeAt(LatLng p) async {
    final connectFrom = _autoConnect ? _selectedNodeId : null;
    final saved = await _insertNode(
        OutdoorArNodeModel(lat: p.latitude, lng: p.longitude));
    if (saved == null || !mounted) return;
    if (connectFrom != null && _nodes.containsKey(connectFrom)) {
      await _createEdge(connectFrom, saved.id!, quiet: true);
    }
    if (mounted) setState(() => _selectedNodeId = saved.id);
  }

  /// From the side-panel form; true when the node was saved.
  Future<bool> _addByCoordinates(OutdoorArNodeModel model) async {
    final saved = await _insertNode(model);
    if (saved == null || !mounted) return false;
    _selectNode(saved.id!, focus: true);
    context.showSuccess('Node added at '
        '${saved.lat.toStringAsFixed(6)}, ${saved.lng.toStringAsFixed(6)}');
    return true;
  }

  void _recenterOnCampus() => _mapController.fitCamera(_campusFit);

  /// Saves [updated]; when it moved, also recomputes its edges' weight_m.
  Future<bool> _saveNode(OutdoorArNodeModel updated, {String? success}) async {
    final id = updated.id!;
    final old = _nodes[id];
    setState(() {
      _nodes[id] = updated;
      _busy = true;
    });
    try {
      final saved = await _repo.updateNode(updated);
      if (!mounted) return true;
      setState(() => _nodes[id] = saved);
      final moved = old == null || old.lat != saved.lat || old.lng != saved.lng;
      if (moved) await _refreshEdgeWeights(id);
      if (success != null && mounted) context.showSuccess(success);
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        if (old != null) _nodes[id] = old;
      });
      context.showError(e, onRetry: () => _saveNode(updated, success: success));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshEdgeWeights(String nodeId) async {
    final touching = [
      for (final e in _edges)
        if (e.touches(nodeId) && e.id != null)
          e.copyWith(weightM: _edgeLengthM(e)),
    ];
    if (touching.isEmpty) return;
    setState(() {
      _edges = [
        for (final e in _edges)
          touching.firstWhere((t) => t.id == e.id, orElse: () => e),
      ];
    });
    try {
      await Future.wait([
        for (final e in touching)
          if (e.weightM != null) _repo.updateEdgeWeight(e.id!, e.weightM!),
      ]);
    } catch (e) {
      if (mounted) {
        context.showError(e, onRetry: () => _refreshEdgeWeights(nodeId));
      }
    }
  }

  Future<void> _deleteNode(OutdoorArNodeModel n) async {
    final degree = _degree(n.id!);
    final ok = await ConfirmDialog.show(
      context,
      title: 'Delete AR node',
      itemName: _nodeName(n.id),
      message: degree == 0
          ? 'This action cannot be undone.'
          : 'This also deletes its $degree edge(s). This cannot be undone.',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await _repo.deleteNode(n.id!);
      if (!mounted) return;
      setState(() {
        _nodes.remove(n.id);
        _edges = _edges.where((e) => !e.touches(n.id!)).toList();
        if (_selectedNodeId == n.id) _selectedNodeId = null;
        if (_edgeById(_selectedEdgeId) == null) _selectedEdgeId = null;
      });
      context.showSuccess('Node deleted');
    } catch (e) {
      if (mounted) context.showError(e, onRetry: () => _deleteNode(n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- drag ------------------------------------------------------------------

  void _startDrag(OutdoorArNodeModel n) {
    if (_mode != _Mode.select || _busy) return;
    setState(() {
      _selectedNodeId = n.id;
      _selectedEdgeId = null;
      _dragNodeId = n.id;
      _dragPos = null;
    });
  }

  void _updateDrag(Offset global) {
    if (_dragNodeId == null) return;
    final ll = _globalToLatLng(global);
    if (ll != null) setState(() => _dragPos = ll);
  }

  Future<void> _endDrag() async {
    final id = _dragNodeId;
    final pos = _dragPos;
    setState(() {
      _dragNodeId = null;
      _dragPos = null;
    });
    final node = _nodes[id];
    if (node == null || pos == null) return;
    await _saveNode(node.copyWith(lat: pos.latitude, lng: pos.longitude));
  }

  // --- edge CRUD -------------------------------------------------------------

  Future<bool> _createEdge(String from, String to, {bool quiet = false}) async {
    if (from == to) return false;
    if (_edges.any((e) => e.joins(from, to))) {
      if (!quiet) context.showInfo('These nodes are already connected.');
      return true;
    }
    final a = _pos(from);
    final b = _pos(to);
    if (a == null || b == null) return false;
    setState(() => _busy = true);
    try {
      final saved = await _repo.createEdge(OutdoorArEdgeModel(
        fromNode: from,
        toNode: to,
        weightM: _distM(a, b),
      ));
      if (!mounted) return true;
      setState(() => _edges = [..._edges, saved]);
      final len = saved.weightM ?? 0;
      // Over the limit is allowed — just flagged.
      if (exceedsEdgeLimit(len, _maxEdgeM)) {
        context.showWarning('New edge is ${formatDistanceM(len)} — over the '
            '${_fmt(_maxEdgeM)} m limit. Consider adding a node in between.');
      } else if (!quiet) {
        context.showSuccess('Edge added (${formatDistanceM(len)})');
      }
      return true;
    } catch (e) {
      if (mounted) {
        context.showError(e,
            onRetry: () => _createEdge(from, to, quiet: quiet));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteEdge(OutdoorArEdgeModel e) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Delete AR edge',
      itemName: _edgeLabel(e),
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await _repo.deleteEdge(e.id!);
      if (!mounted) return;
      setState(() {
        _edges = _edges.where((x) => x.id != e.id).toList();
        if (_selectedEdgeId == e.id) _selectedEdgeId = null;
      });
      context.showSuccess('Edge deleted');
    } catch (err) {
      if (mounted) context.showError(err, onRetry: () => _deleteEdge(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- building AR settings ------------------------------------------------

  Future<bool> _saveBuildingAr(
      BuildingModel b, String emoji, String label, double radius) async {
    try {
      final updated = await _buildingRepo.updateArSettings(
        b.id!,
        arEmoji: emoji,
        arLabel: label,
        arArrivalRadiusM: radius,
      );
      if (!mounted) return true;
      setState(() {
        _buildings = [
          for (final x in _buildings) if (x.id == updated.id) updated else x,
        ];
        _allBuildings = [
          for (final x in _allBuildings) if (x.id == updated.id) updated else x,
        ];
        _previewRadiusM = null;
      });
      context.showSuccess('AR settings saved for ${b.name}');
      return true;
    } catch (e) {
      if (mounted) {
        context.showError(e,
            onRetry: () => _saveBuildingAr(b, emoji, label, radius));
      }
      return false;
    }
  }

  void _locateBuilding(BuildingModel b) {
    if (b.lat == null || b.lng == null) {
      context.showError('This building has no coordinates yet.');
      return;
    }
    _focus(LatLng(b.lat!, b.lng!));
  }

  Future<void> _copyCoords(LatLng p) async {
    final text =
        '${p.latitude.toStringAsFixed(7)}, ${p.longitude.toStringAsFixed(7)}';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) context.showSuccess('Copied $text');
  }

  // --- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 330, child: _leftPanel()),
        const SizedBox(width: 16),
        Expanded(child: _mapPanel()),
      ],
    );
  }

  // --- left panel ------------------------------------------------------------

  Widget _leftPanel() {
    final long = _edges.where(_isLong).length;
    final report = _networkReport;
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
          _networkSummary(),
          const Divider(height: 1),
          Row(
            children: [
              _tabButton('Nodes (${_nodes.length})', _Tab.nodes),
              _tabButton(
                  long > 0
                      ? 'Edges (${_edges.length}) ⚠'
                      : 'Edges (${_edges.length})',
                  _Tab.edges),
              _tabButton('Building AR', _Tab.buildings),
              _tabButton(
                  report.isHealthy &&
                          _buildingsError == null &&
                          !_entrancesNeedWork
                      ? 'Check'
                      : 'Check ⚠',
                  _Tab.check),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: switch (_tab) {
              _Tab.nodes => _nodesTab(),
              _Tab.edges => _edgesTab(),
              _Tab.buildings => _buildingsTab(),
              _Tab.check => _checkTab(report),
            },
          ),
        ],
      ),
    );
  }

  /// Totals + the edge length limit, visible on every tab.
  Widget _networkSummary() {
    final stats = _edgeStats;
    Widget stat(String value, String label, {Color? color}) => Expanded(
          child: Column(
            children: [
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: color ?? AppColors.textPrimary)),
              Text(label,
                  style: const TextStyle(
                      fontSize: 9.5, color: AppColors.textSecondary)),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              stat('${_nodes.length}', 'nodes'),
              stat('${_edges.length}', 'edges'),
              stat(formatDistanceM(stats.total), 'total'),
              stat(_edges.isEmpty ? '—' : formatDistanceM(stats.longest),
                  'longest',
                  color: exceedsEdgeLimit(stats.longest, _maxEdgeM)
                      ? AppColors.warningAmber
                      : null),
              stat('${stats.over}', 'over limit',
                  color: stats.over > 0 ? AppColors.warningAmber : null),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                child: Text('Max edge length (m)',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _maxEdgeCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    isDense: true,
                    suffixText: 'm',
                    errorText: _maxEdgeError,
                    errorStyle: const TextStyle(fontSize: 10),
                  ),
                  onChanged: _onMaxEdgeChanged,
                ),
              ),
            ],
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

  // --- network check ------------------------------------------------------

  /// Active buildings are the ones an AR route must be able to reach.
  ArNetworkReport get _networkReport => checkArNetwork(
        nodes: _nodes.values,
        edges: _edges,
        buildingIds: [
          for (final b in _buildings)
            if (b.isActive && b.id != null) b.id!,
        ],
      );

  /// Selects [id] and zooms to it without leaving the current tab.
  void _zoomToNode(String id) {
    setState(() {
      _selectedNodeId = id;
      _selectedEdgeId = null;
    });
    final p = _pos(id);
    if (p != null) _focus(p);
  }

  void _zoomToGroup(List<String> ids) {
    final points = [for (final id in ids) ?_pos(id)];
    if (points.isEmpty) return;
    if (points.length == 1) {
      _focus(points.first);
      return;
    }
    _mapController.fitCamera(CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.all(80),
      maxZoom: 19.5,
    ));
  }

  /// Zooms to the building's map point, or says it has none.
  void _zoomToBuilding(BuildingModel b) {
    final lat = b.labelLat ?? b.lat;
    final lng = b.labelLng ?? b.lng;
    if (lat == null || lng == null) {
      context.showWarning('${b.name} has no map coordinates to zoom to.');
      return;
    }
    _focus(LatLng(lat, lng));
  }

  Widget _checkTab(ArNetworkReport report) {
    final pieces = report.components;
    final isolated = report.isolatedNodeIds.toSet();
    final multi = [for (final g in pieces) if (!isolated.contains(g.first)) g];
    Widget row(String title, String? subtitle, VoidCallback onTap,
            {IconData icon = Icons.my_location}) =>
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, size: 18, color: AppColors.textSecondary),
          title: Text(title,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis),
          subtitle: subtitle == null
              ? null
              : Text(subtitle, style: const TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.zoom_in, size: 16),
          onTap: onTap,
        );
    List<Widget> buildingRows(List<int> ids, String why) => [
          for (final id in ids)
            if (_buildingById(id) case final b?)
              row(_buildingDisplayText(b), why, () {
                final nodes = [
                  for (final n in _nodes.values)
                    if (n.buildingId == id && n.isActive) n.id!,
                ];
                nodes.isEmpty ? _zoomToBuilding(b) : _zoomToGroup(nodes);
              }, icon: Icons.apartment),
        ];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionTitle('AR network check'),
        _hint('Active nodes and edges only — what the user app routes on. '
            'Click a row to zoom to it.'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh, size: 15),
          label: const Text('Reload and check again'),
        ),
        const SizedBox(height: 8),
        Text('Disconnected pieces: ${pieces.length}',
            style: const TextStyle(fontSize: 12)),
        Text('Nodes with no edges: ${report.isolatedNodeIds.length}',
            style: const TextStyle(fontSize: 12)),
        Text(
            'Buildings with no link to the network: '
            '${_buildingsError != null ? 'not checked' : report.buildingsWithoutNode.length + report.buildingsOffMainNetwork.length}',
            style: const TextStyle(fontSize: 12)),
        Text(
            'Buildings with unlinked entrances: '
            '${_entrancesError != null ? 'not checked' : _entranceRows == null ? '…' : unlinkedByBuilding(_entranceRows!).length}',
            style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 10),
        if (_buildingsError != null) ...[
          _warningBox('Buildings could not be loaded, so building coverage '
              'is not checked: $_buildingsError. Click to retry.',
              onTap: _load),
          const SizedBox(height: 8),
        ],
        if (report.isHealthy && _buildingsError == null)
          _hint('✓ One connected network, and every active building has a '
              'reachable AR node.'),
        const SizedBox(height: 8),
        _sectionTitle('Connected pieces (${multi.length})'),
        if (multi.length > 1)
          _hint('Routes can\'t cross between pieces. Connect them with an '
              'edge.'),
        for (var i = 0; i < multi.length; i++)
          row(
            i == 0 ? 'Main network' : 'Piece ${i + 1}',
            '${multi[i].length} nodes',
            () => _zoomToGroup(multi[i]),
            icon: Icons.hub_outlined,
          ),
        const Divider(height: 20),
        _sectionTitle('Isolated nodes (${report.isolatedNodeIds.length})'),
        for (final id in report.isolatedNodeIds)
          row(_nodeName(id), _typeLabel(_nodes[id]?.nodeType ?? 'path'),
              () => _zoomToNode(id),
              icon: Icons.radio_button_unchecked),
        const Divider(height: 20),
        _sectionTitle(
            'Buildings with no AR node (${report.buildingsWithoutNode.length})'),
        if (report.buildingsWithoutNode.isNotEmpty)
          _hint('Link a node to each one (node → Building) so AR routes can '
              'end there.'),
        ...buildingRows(report.buildingsWithoutNode, 'No node linked'),
        if (report.buildingsOffMainNetwork.isNotEmpty) ...[
          const Divider(height: 20),
          _sectionTitle('Buildings off the main network '
              '(${report.buildingsOffMainNetwork.length})'),
          ...buildingRows(report.buildingsOffMainNetwork,
              'Linked node is not connected to the main network'),
        ],
        const Divider(height: 20),
        EntranceStatusSection(
          rows: _entranceRows,
          error: _entrancesError,
          onRetry: _loadEntrances,
          buildingName: (id) => id == null
              ? 'No building'
              : _buildingById(id)?.name ?? 'Building #$id',
        ),
      ],
    );
  }

  Widget _hint(String text) => Text(text,
      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary));

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      );

  Widget _warningBox(String text, {VoidCallback? onTap}) {
    final box = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.warningAmber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warningAmber.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 16, color: AppColors.warningAmber),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 11))),
          if (onTap != null)
            const Icon(Icons.chevron_right, size: 16, color: AppColors.textSecondary),
        ],
      ),
    );
    return onTap == null ? box : InkWell(onTap: onTap, child: box);
  }

  String get _modeHint => switch (_mode) {
        _Mode.select => 'Click a node to edit it, drag it to move it. Click '
            'an edge line to select it.',
        _Mode.addNode => 'Each click on the map adds a node. Click an existing '
            'node to continue from it.',
        _Mode.connect => 'Click a node, then another, to join them. Keep '
            'clicking to chain edges along a walkway.',
        _Mode.measure => 'Measuring: click two points (or nodes) on the map. '
            'Nothing is saved. Turn it off with the ruler button on the map.',
      };

  Widget _nodesTab() {
    final isolated = _isolatedNodes;
    final long = _edges.where(_isLong).length;
    final q = _nodeSearch.toLowerCase();
    final list = _nodes.values
        .where((n) => q.isEmpty || _nodeName(n.id).toLowerCase().contains(q))
        .toList();
    final selected = _nodes[_selectedNodeId];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _AddByCoordinatesSection(
          open: _coordsOpen,
          enabled: !_busy && _error == null,
          onToggle: () => setState(() => _coordsOpen = !_coordsOpen),
          onAdd: _addByCoordinates,
        ),
        const SizedBox(height: 12),
        SegmentedButton<_Mode>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
          ),
          segments: const [
            ButtonSegment(
                value: _Mode.select,
                icon: Icon(Icons.near_me_outlined, size: 16),
                label: Text('Select')),
            ButtonSegment(
                value: _Mode.addNode,
                icon: Icon(Icons.add_location_alt_outlined, size: 16),
                label: Text('Add')),
            ButtonSegment(
                value: _Mode.connect,
                icon: Icon(Icons.timeline, size: 16),
                label: Text('Connect')),
          ],
          // Measure mode (from the map controls) shows no segment selected.
          emptySelectionAllowed: true,
          selected: _mode == _Mode.measure ? const {} : {_mode},
          onSelectionChanged: (s) {
            if (s.isNotEmpty) _setMode(s.first);
          },
        ),
        const SizedBox(height: 6),
        _hint(_modeHint),
        if (_mode == _Mode.addNode)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Connect each new node to the selected one',
                style: TextStyle(fontSize: 12)),
            value: _autoConnect,
            onChanged: (v) => setState(() => _autoConnect = v ?? false),
          ),
        const SizedBox(height: 10),
        if (isolated.isNotEmpty) ...[
          _warningBox(
            '${isolated.length} isolated node(s) with no edges — routes can\'t '
            'reach them. Click to show the next one.',
            onTap: () {
              final n = isolated[_isolatedCursor % isolated.length];
              _isolatedCursor++;
              _selectNode(n.id!, focus: true);
            },
          ),
          const SizedBox(height: 8),
        ],
        if (long > 0) ...[
          _warningBox(
            '$long edge(s) longer than the ${_fmt(_maxEdgeM)} m limit. '
            'Click to review.',
            onTap: () => setState(() {
              _tab = _Tab.edges;
              _onlyLongEdges = true;
            }),
          ),
          const SizedBox(height: 8),
        ],
        if (selected != null) ...[
          _NodePanel(
            key: ValueKey('node-${selected.id}-${selected.lat}-'
                '${selected.lng}-${selected.buildingId}-${selected.nodeType}-'
                '${selected.label}'),
            node: selected,
            buildings: selectableBuildings(_allBuildings, selected.buildingId),
            busy: _busy,
            onSave: (n) => _saveNode(n, success: 'Node saved'),
            onDelete: () => _deleteNode(selected),
            onClose: () => setState(() => _selectedNodeId = null),
            onCopy: () => _copyCoords(LatLng(selected.lat, selected.lng)),
          ),
          const SizedBox(height: 8),
          _connectedEdges(selected),
          const Divider(height: 24),
        ],
        _sectionTitle('All nodes'),
        TextField(
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'Search by label…',
            prefixIcon: Icon(Icons.search, size: 18),
          ),
          onChanged: (v) => setState(() => _nodeSearch = v),
        ),
        const SizedBox(height: 6),
        if (_nodes.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
                'No AR nodes yet - tap the map or enter coordinates.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary)),
          )
        else
          for (final n in list) _nodeRow(n),
      ],
    );
  }

  Widget _connectedEdges(OutdoorArNodeModel n) {
    final edges = _edges.where((e) => e.touches(n.id!)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Connected edges (${edges.length})',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        if (edges.isEmpty)
          _hint('None — use Connect mode to join this node to the network.'),
        for (final e in edges)
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _selectEdge(e, fit: true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '→ ${_nodeName(e.fromNode == n.id ? e.toNode : e.fromNode)}'
                      ' · ${formatDistanceM(_edgeLengthM(e) ?? 0)}',
                      style: TextStyle(
                          fontSize: 11,
                          color: _isLong(e)
                              ? AppColors.warningAmber
                              : AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Delete edge',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.link_off,
                    size: 16, color: AppColors.errorRed),
                onPressed: _busy ? null : () => _deleteEdge(e),
              ),
            ],
          ),
      ],
    );
  }

  Widget _nodeRow(OutdoorArNodeModel n) {
    final degree = _degree(n.id!);
    final building = _buildingById(n.buildingId);
    return InkWell(
      onTap: () => _selectNode(n.id!, focus: true),
      child: Container(
        color: _selectedNodeId == n.id
            ? _cPathway.withValues(alpha: 0.12)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: _typeColor(n.nodeType), shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            if (building != null) ...[
              Text(building.arEmoji ?? _defaultEmoji,
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(_nodeName(n.id),
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis),
            ),
            if (degree == 0)
              const Tooltip(
                message: 'Isolated — no edges',
                child: Icon(Icons.warning_amber_rounded,
                    size: 16, color: AppColors.warningAmber),
              )
            else
              Text('$degree',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _edgesTab() {
    final list = _edges.where((e) => !_onlyLongEdges || _isLong(e)).toList()
      ..sort((a, b) =>
          (_edgeLengthM(b) ?? 0).compareTo(_edgeLengthM(a) ?? 0));
    final selected = _edgeById(_selectedEdgeId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text('Only edges longer than ${_fmt(_maxEdgeM)} m',
              style: const TextStyle(fontSize: 12)),
          value: _onlyLongEdges,
          onChanged: (v) => setState(() => _onlyLongEdges = v ?? false),
        ),
        if (selected != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _selectedEdgeCard(selected),
          ),
        const Divider(height: 1),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                        _edges.isEmpty
                            ? 'No edges yet — use Connect mode on the Nodes tab.'
                            : 'No edges match.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary)),
                  ),
                )
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => _edgeRow(list[i]),
                ),
        ),
      ],
    );
  }

  Widget _selectedEdgeCard(OutdoorArEdgeModel e) {
    final len = _edgeLengthM(e) ?? 0;
    return Container(
      padding: const EdgeInsets.all(10),
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
              const Expanded(
                child: Text('Selected edge',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              InkWell(
                onTap: () => setState(() => _selectedEdgeId = null),
                child: const Icon(Icons.close, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_edgeLabel(e),
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: _cBuilding)),
          const SizedBox(height: 4),
          Text(
            'Length ${formatDistanceM(len)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: exceedsEdgeLimit(len, _maxEdgeM)
                  ? AppColors.warningAmber
                  : AppColors.successGreen,
            ),
          ),
          _hint('Limit ${_fmt(_maxEdgeM)} m · stored weight_m '
              '${e.weightM?.toStringAsFixed(1) ?? '—'}'),
          if (exceedsEdgeLimit(len, _maxEdgeM)) ...[
            const SizedBox(height: 6),
            _warningBox('Longer than ${_fmt(_maxEdgeM)} m — add nodes along '
                'the walkway so AR arrows follow it.'),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.errorRed,
              side: const BorderSide(color: AppColors.errorRed),
            ),
            onPressed: _busy ? null : () => _deleteEdge(e),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Delete edge'),
          ),
        ],
      ),
    );
  }

  Widget _edgeRow(OutdoorArEdgeModel e) {
    final len = _edgeLengthM(e) ?? 0;
    final long = exceedsEdgeLimit(len, _maxEdgeM);
    final selected = e.id == _selectedEdgeId;
    return InkWell(
      onTap: () => _selectEdge(e, fit: true),
      child: Container(
        color: selected ? _cPathway.withValues(alpha: 0.12) : null,
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_edgeLabel(e),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  Text(formatDistanceM(len),
                      style: TextStyle(
                          fontSize: 10,
                          color: long
                              ? AppColors.warningAmber
                              : AppColors.textSecondary)),
                ],
              ),
            ),
            if (long)
              Tooltip(
                message: 'Longer than ${_fmt(_maxEdgeM)} m',
                child: const Icon(Icons.warning_amber_rounded,
                    size: 18, color: AppColors.warningAmber),
              ),
            IconButton(
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: AppColors.errorRed),
              onPressed: _busy ? null : () => _deleteEdge(e),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildingsTab() {
    final list = [..._buildings]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final selected = _buildingById(int.tryParse(_arBuildingId ?? ''));
    final linked = selected == null
        ? const <OutdoorArNodeModel>[]
        : [for (final n in _nodes.values) if (n.buildingId == selected.id) n];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionTitle('Building AR settings'),
        _hint('The marker the AR overlay shows at a destination building, and '
            'how close the user must get to count as arrived.'),
        const SizedBox(height: 10),
        DropdownButton<String>(
          isExpanded: true,
          value: selected == null ? null : _arBuildingId,
          hint: const Text('Pick a building'),
          items: [
            for (final b in list)
              DropdownMenuItem(
                value: b.id?.toString(),
                child: Text('${b.arEmoji ?? _defaultEmoji}  ${b.name}',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            setState(() {
              _arBuildingId = v;
              _previewRadiusM = null;
            });
            final b = _buildingById(int.tryParse(v ?? ''));
            if (b != null && b.lat != null && b.lng != null) _locateBuilding(b);
          },
        ),
        if (list.isEmpty)
          _hint('No buildings could be loaded.'),
        if (selected != null) ...[
          const SizedBox(height: 12),
          _BuildingArPanel(
            key: ValueKey('ar-bld-${selected.id}'),
            building: selected,
            onSave: (emoji, label, radius) =>
                _saveBuildingAr(selected, emoji, label, radius),
            onRadiusPreview: (r) => setState(() => _previewRadiusM = r),
            onLocate: () => _locateBuilding(selected),
          ),
          const SizedBox(height: 12),
          Text('Linked AR nodes (${linked.length})',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          if (linked.isEmpty)
            _hint('No node links to this building yet, so routes can\'t end '
                'here. Select a node and pick this building in "Linked '
                'building".')
          else
            for (final n in linked)
              InkWell(
                onTap: () => _selectNode(n.id!, focus: true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('• ${_nodeName(n.id)}',
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
        ],
      ],
    );
  }

  // --- map -------------------------------------------------------------------

  Widget _mapPanel() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          Positioned.fill(child: _map()),
          const Positioned(
            top: 100,
            left: 12,
            right: 12,
            child: MapTilerKeyNotice(),
          ),
          if (_loading)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x88FFFFFF),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          if (_banner.isNotEmpty && _error == null)
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: IgnorePointer(
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
            ),
          if (!_loading && _error == null && _nodes.isEmpty)
            Positioned(
                top: 60,
                left: 0,
                right: 0,
                // Info only — clicks pass through to the map.
                child: IgnorePointer(child: _emptyState())),
          if (_error != null)
            Positioned(top: 60, left: 24, right: 24, child: _errorCard()),
          Positioned(
            top: 12,
            right: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _layerSwitcher(),
                const SizedBox(height: 8),
                Material(
                  color: Colors.white,
                  elevation: 3,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: IconButton(
                      tooltip: 'Recenter on campus',
                      icon: const Icon(Icons.center_focus_strong),
                      onPressed: _recenterOnCampus,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Material(
                  color: _mode == _Mode.measure ? _cSelected : Colors.white,
                  elevation: 3,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: IconButton(
                      tooltip: _mode == _Mode.measure
                          ? 'Stop measuring'
                          : 'Measure distance (no nodes created)',
                      icon: const Icon(Icons.straighten),
                      onPressed: _error == null ? _toggleMeasure : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
              left: 12, bottom: 34, child: _Legend(maxEdgeM: _maxEdgeM)),
          Positioned(left: 0, right: 0, bottom: 34, child: _cursorBar()),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.view_in_ar, size: 32, color: _cBuilding),
            const SizedBox(height: 8),
            const Text('No AR nodes yet - tap the map or enter coordinates',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            _hint('Place nodes along the real walkways, then join them in '
                'Connect mode. To type coordinates, use "Add by coordinates" '
                'in the side panel.'),
          ],
        ),
      ),
    );
  }

  Widget _errorCard() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxWidth: 460),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.errorRed.withValues(alpha: 0.5)),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 32, color: AppColors.errorRed),
            const SizedBox(height: 8),
            Text('Could not load the AR path network.\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            _hint('If the tables are missing, run db/outdoor_ar_v2.sql in the '
                'Supabase SQL editor.'),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _layerSwitcher() {
    return Material(
      color: Colors.white,
      elevation: 3,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: _layersOpen ? 240 : null,
          padding: const EdgeInsets.all(4),
          child: !_layersOpen
              ? IconButton(
                  tooltip: 'Map layers',
                  icon: const Icon(Icons.layers_outlined),
                  onPressed: () => setState(() => _layersOpen = true),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('Map layers',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => setState(() => _layersOpen = false),
                        ),
                      ],
                    ),
                    RadioGroup<_BaseLayer>(
                      groupValue: _base,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _base = v);
                        _saveLayerPrefs();
                      },
                      child: Column(
                        children: [
                          for (final b
                              in _BaseLayer.values.where(_layerAvailable))
                            RadioListTile<_BaseLayer>(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              value: b,
                              title: Text(_baseSources[b]!.label,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 8),
                    SwitchListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: const Text('UM campus overlay',
                          style: TextStyle(fontSize: 12)),
                      value: _showUmOverlay,
                      onChanged: (v) {
                        setState(() => _showUmOverlay = v);
                        _saveLayerPrefs();
                      },
                    ),
                    Row(
                      children: [
                        const SizedBox(width: 8),
                        const Text('Opacity', style: TextStyle(fontSize: 11)),
                        Expanded(
                          child: Slider(
                            value: _umOpacity,
                            min: 0.1,
                            max: 1.0,
                            divisions: 9,
                            label: '${(_umOpacity * 100).round()}%',
                            onChanged: _showUmOverlay
                                ? (v) => setState(() => _umOpacity = v)
                                : null,
                            onChangeEnd: (_) => _saveLayerPrefs(),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 8),
                    SwitchListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: const Text('Show distances',
                          style: TextStyle(fontSize: 12)),
                      subtitle: Text(
                          'Edge lengths, from zoom ${_fmt(_distanceLabelZoom)}',
                          style: const TextStyle(fontSize: 10)),
                      value: _showDistances,
                      onChanged: (v) {
                        setState(() => _showDistances = v);
                        _saveLayerPrefs();
                      },
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _cursorBar() {
    return Center(
      child: ValueListenableBuilder<LatLng?>(
        valueListenable: _cursor,
        builder: (_, p, _) {
          if (p == null) return const SizedBox.shrink();
          const mono = TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontFeatures: [FontFeature.tabularFigures()],
          );
          final start = _liveLineStart;
          final measured = _mode == _Mode.measure &&
                  _measureA != null &&
                  _measureB != null
              ? _distM(_measureA!, _measureB!)
              : null;
          final String? distanceText;
          Color distanceColor = Colors.white;
          if (measured != null) {
            distanceText = 'Measured: ${formatDistanceM(measured)}';
          } else if (start != null) {
            final d = _distM(start, p);
            if (_mode == _Mode.measure) {
              distanceText = 'From first point: ${formatDistanceM(d)}';
            } else {
              distanceText = 'From selected node: ${formatDistanceM(d)}';
              distanceColor =
                  exceedsEdgeLimit(d, _maxEdgeM) ? _cOverLimit : _cWithinLimit;
            }
          } else {
            distanceText = null;
          }
          return Container(
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (distanceText != null) ...[
                  Text(distanceText,
                      style: mono.copyWith(
                          color: distanceColor, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  const Text('·', style: mono),
                  const SizedBox(width: 6),
                ],
                Text(
                  '${p.latitude.toStringAsFixed(7)}, '
                  '${p.longitude.toStringAsFixed(7)}',
                  style: mono,
                ),
                IconButton(
                  tooltip: 'Copy coordinates',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy, size: 14, color: Colors.white),
                  onPressed: () => _copyCoords(p),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _map() {
    var flags = InteractiveFlag.all & ~InteractiveFlag.rotate;
    // While a node is being dragged the map must not pan underneath it.
    if (_dragNodeId != null) {
      flags &= ~(InteractiveFlag.drag |
          InteractiveFlag.flingAnimation |
          InteractiveFlag.pinchMove);
    }
    final base = _baseSources[_base]!;
    final arBuilding = _tab == _Tab.buildings
        ? _buildingById(int.tryParse(_arBuildingId ?? ''))
        : null;
    final attribution = [
      base.attribution,
      if (_showUmOverlay && MapTilerConfig.isConfigured)
        _umOverlay.attribution,
    ].join('  ·  ');

    return SizedBox.expand(
      key: _mapKey,
      child: MouseRegion(
        // Hovering a map control (above the map) also counts as leaving it.
        onExit: (_) => _cursorOnMap.value = false,
        child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCameraFit: _campusFit,
          minZoom: _minZoom,
          maxZoom: _maxZoom,
          cameraConstraint: _cameraConstraint,
          interactionOptions: InteractionOptions(flags: flags),
          onTap: (_, point) => _handleMapTap(point),
          onPointerHover: (_, point) {
            _cursor.value = point;
            _cursorOnMap.value = true;
          },
          onPositionChanged: (camera, _) {
            if ((camera.zoom - _currentZoom).abs() > 0.15) {
              setState(() => _currentZoom = camera.zoom);
            }
          },
        ),
        children: [
          TileLayer(
            key: ValueKey(_base),
            urlTemplate: base.url,
            userAgentPackageName: 'com.umindanao.um_ar_admin',
            maxNativeZoom: base.maxNativeZoom,
            maxZoom: _maxZoom,
          ),
          if (_showUmOverlay && MapTilerConfig.isConfigured)
            Opacity(
              opacity: _umOpacity,
              child: TileLayer(
                urlTemplate: _umOverlay.url,
                userAgentPackageName: 'com.umindanao.um_ar_admin',
                maxNativeZoom: _umOverlay.maxNativeZoom,
                maxZoom: _maxZoom,
              ),
            ),
          if (arBuilding != null &&
              arBuilding.lat != null &&
              arBuilding.lng != null)
            CircleLayer(circles: [
              CircleMarker(
                point: LatLng(arBuilding.lat!, arBuilding.lng!),
                radius: _previewRadiusM ??
                    arBuilding.arArrivalRadiusM ??
                    _defaultArrivalRadiusM,
                useRadiusInMeter: true,
                color: _cConnectFrom.withValues(alpha: 0.2),
                borderColor: _cConnectFrom,
                borderStrokeWidth: 2,
              ),
            ]),
          PolylineLayer(polylines: _polylines()),
          if (_mode == _Mode.measure && _measureA != null && _measureB != null)
            PolylineLayer(polylines: [
              Polyline(
                points: [_measureA!, _measureB!],
                strokeWidth: 3,
                color: _cSelected,
                borderStrokeWidth: 1.5,
                borderColor: Colors.black.withValues(alpha: 0.6),
              ),
            ]),
          // Live line from the selected node / first measure point to the
          // cursor. Rebuilt from the hover notifiers only, not the whole map.
          ListenableBuilder(
            listenable: Listenable.merge([_cursor, _cursorOnMap]),
            builder: (_, _) {
              final live = _liveSegment();
              if (live == null) return const SizedBox.shrink();
              return PolylineLayer(polylines: [
                Polyline(
                  points: [live.from, live.to],
                  strokeWidth: 3,
                  color: live.color,
                  borderStrokeWidth: 1,
                  borderColor: Colors.black.withValues(alpha: 0.6),
                  pattern: StrokePattern.dashed(segments: const [8.0, 6.0]),
                ),
              ]);
            },
          ),
          MarkerLayer(markers: _nodeMarkers()),
          if (_showDistances && _currentZoom >= _distanceLabelZoom)
            MarkerLayer(markers: _edgeLengthMarkers()),
          if (_mode == _Mode.measure && _measureA != null)
            MarkerLayer(markers: _measureMarkers()),
          ListenableBuilder(
            listenable: Listenable.merge([_cursor, _cursorOnMap]),
            builder: (_, _) {
              final live = _liveSegment();
              if (live == null) return const SizedBox.shrink();
              return MarkerLayer(markers: [
                Marker(
                  point: live.to,
                  width: 96,
                  height: 30,
                  // Up and to the right of the cursor.
                  alignment: Alignment.topRight,
                  child: IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 14, bottom: 6),
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: _distancePill(
                            formatDistanceM(_distM(live.from, live.to)),
                            live.color,
                            textColor: live.color == _cSelected
                                ? Colors.black
                                : Colors.white),
                      ),
                    ),
                  ),
                ),
              ]);
            },
          ),
          SimpleAttributionWidget(
            source: Text(attribution, style: const TextStyle(fontSize: 10)),
          ),
        ],
        ),
      ),
    );
  }

  /// The live "next edge" segment to the cursor, or null when there is
  /// nothing to draw. Green / red against the limit; cyan when measuring.
  ({LatLng from, LatLng to, Color color})? _liveSegment() {
    final start = _liveLineStart;
    final cursor = _cursor.value;
    if (start == null || cursor == null || !_cursorOnMap.value) return null;
    if (_dragNodeId != null) return null;
    final Color color;
    if (_mode == _Mode.measure) {
      color = _cSelected;
    } else {
      color = exceedsEdgeLimit(_distM(start, cursor), _maxEdgeM)
          ? _cOverLimit
          : _cWithinLimit;
    }
    return (from: start, to: cursor, color: color);
  }

  Widget _distancePill(String text, Color background,
      {Color textColor = Colors.white, Color? borderColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: borderColor ?? Colors.black.withValues(alpha: 0.35)),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
      ),
      child: Text(text,
          maxLines: 1,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.bold, color: textColor)),
    );
  }

  /// Length label at each edge's midpoint (follows a node being dragged).
  List<Marker> _edgeLengthMarkers() {
    final markers = <Marker>[];
    for (final e in _edges) {
      final a = _pos(e.fromNode);
      final b = _pos(e.toNode);
      if (a == null || b == null) continue;
      final len = _distM(a, b);
      final over = exceedsEdgeLimit(len, _maxEdgeM);
      markers.add(Marker(
        point: _midpoint(a, b),
        width: 70,
        height: 20,
        child: IgnorePointer(
          child: Center(
            child: _distancePill(
              formatDistanceM(len),
              over ? AppColors.warningAmber : Colors.black.withValues(alpha: 0.72),
              textColor: over ? Colors.black : Colors.white,
              borderColor: e.id == _selectedEdgeId ? _cSelected : null,
            ),
          ),
        ),
      ));
    }
    return markers;
  }

  List<Marker> _measureMarkers() {
    Marker dot(LatLng p) => Marker(
          point: p,
          width: 14,
          height: 14,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: _cSelected,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 1.5),
              ),
            ),
          ),
        );
    final a = _measureA!;
    final b = _measureB;
    return [
      dot(a),
      if (b != null) ...[
        dot(b),
        Marker(
          point: _midpoint(a, b),
          width: 80,
          height: 22,
          child: IgnorePointer(
            child: Center(
              child: _distancePill(formatDistanceM(_distM(a, b)), _cSelected,
                  textColor: Colors.black),
            ),
          ),
        ),
      ],
    ];
  }

  List<Polyline> _polylines() {
    final lines = <Polyline>[];
    for (final e in _edges) {
      final a = _pos(e.fromNode);
      final b = _pos(e.toNode);
      if (a == null || b == null) continue;
      final selected = e.id == _selectedEdgeId;
      final long = exceedsEdgeLimit(_distM(a, b), _maxEdgeM);
      lines.add(Polyline(
        points: [a, b],
        strokeWidth: selected ? 6 : 4,
        color: selected
            ? _cSelected
            : long
                ? AppColors.warningAmber
                : _cEdge,
        borderStrokeWidth: 1.5,
        borderColor: Colors.black.withValues(alpha: 0.55),
        pattern: long && !selected
            ? StrokePattern.dashed(segments: const [10.0, 6.0])
            : const StrokePattern.solid(),
      ));
    }
    return lines;
  }

  List<Marker> _nodeMarkers() {
    final showLabels = _currentZoom >= _labelShowZoom;
    final markers = <Marker>[];
    for (final n in _nodes.values) {
      final pos = _pos(n.id)!;
      final selected = n.id == _selectedNodeId;
      final isConnectFrom = selected && _mode == _Mode.connect;
      final isolated = _degree(n.id!) == 0;
      final building = _buildingById(n.buildingId);
      final ring = isConnectFrom
          ? _cConnectFrom
          : selected
              ? _cSelected
              : isolated
                  ? AppColors.errorRed
                  : Colors.white;
      final size = selected ? 16.0 : 11.0;
      markers.add(Marker(
        key: ValueKey('ar-node-${n.id}'),
        point: pos,
        width: 140,
        height: 64,
        alignment: Alignment.center,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (building != null)
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Text(building.arEmoji ?? _defaultEmoji,
                        style: const TextStyle(fontSize: 18)),
                  ),
                ),
              ),
            MouseRegion(
              cursor: _mode == _Mode.select
                  ? SystemMouseCursors.move
                  : SystemMouseCursors.click,
              child: Listener(
                onPointerDown: (_) => _startDrag(n),
                onPointerMove: (ev) => _updateDrag(ev.position),
                onPointerUp: (_) => _endDrag(),
                onPointerCancel: (_) => _endDrag(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _handleNodeTap(n),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Center(
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          color: _typeColor(n.nodeType),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: ring, width: selected ? 3 : 2),
                          boxShadow: const [
                            BoxShadow(color: Colors.black45, blurRadius: 3),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (showLabels || selected || building != null)
              Positioned(
                top: 44,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(_nodeName(n.id),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ));
    }
    return markers;
  }
}

// --- legend ---------------------------------------------------------------

class _Legend extends StatelessWidget {
  final double maxEdgeM;
  const _Legend({required this.maxEdgeM});

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String label, {Color ring = Colors.white}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(color: ring, width: 2),
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 10)),
          ]),
        );
    Widget line(Color c, String label) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 14, height: 4, color: c),
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
          dot(_cPath, 'Path'),
          dot(_cJunction, 'Junction'),
          dot(_cBuilding, 'Building'),
          dot(_cPath, 'Isolated', ring: AppColors.errorRed),
          line(_cEdge, 'Edge'),
          line(AppColors.warningAmber, 'Edge > ${_fmt(maxEdgeM)} m'),
          line(_cWithinLimit, 'Next edge, within limit'),
          line(_cOverLimit, 'Next edge, over limit'),
        ],
      ),
    );
  }
}

// --- selected node panel ---------------------------------------------------

class _NodePanel extends StatefulWidget {
  final OutdoorArNodeModel node;
  final List<BuildingModel> buildings;
  final bool busy;
  final Future<bool> Function(OutdoorArNodeModel updated) onSave;
  final VoidCallback onDelete;
  final VoidCallback onClose;
  final VoidCallback onCopy;

  const _NodePanel({
    super.key,
    required this.node,
    required this.buildings,
    required this.busy,
    required this.onSave,
    required this.onDelete,
    required this.onClose,
    required this.onCopy,
  });

  @override
  State<_NodePanel> createState() => _NodePanelState();
}

class _NodePanelState extends State<_NodePanel> {
  late final TextEditingController _label;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  late String _type;
  int? _buildingId;

  @override
  void initState() {
    super.initState();
    final n = widget.node;
    _label = TextEditingController(text: n.label ?? '');
    _lat = TextEditingController(text: n.lat.toStringAsFixed(7));
    _lng = TextEditingController(text: n.lng.toStringAsFixed(7));
    _type = n.nodeType;
    _buildingId = n.buildingId;
  }

  @override
  void dispose() {
    _label.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  BuildingModel? get _building {
    for (final b in widget.buildings) {
      if (b.id == _buildingId) return b;
    }
    return null;
  }

  /// Pasting "lat, lng" into the latitude field fills both fields.
  void _onLatChanged(String v) {
    final pair = parseLatLngPair(v);
    if (pair == null || !v.contains(RegExp(r'[,;\s]'))) return;
    _lat.text = pair.lat.toString();
    _lng.text = pair.lng.toString();
    setState(() {});
  }

  Future<void> _save() async {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    final err = validateLatLng(lat, lng);
    if (err != null) {
      context.showError(err, onRetry: _save);
      return;
    }
    final far = _distFromCampusM(lat!, lng!);
    if (far > _farFromCampusM) {
      final ok = await _confirmFarFromCampus(context, far);
      if (!ok) return;
    }
    final label = _label.text.trim();
    await widget.onSave(widget.node.copyWith(
      lat: lat,
      lng: lng,
      label: label,
      clearLabel: label.isEmpty,
      nodeType: _type,
      buildingId: _buildingId,
      clearBuilding: _buildingId == null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final buildings = [...widget.buildings]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final b = _building;
    return Container(
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
              const Expanded(
                child: Text('Selected node',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                tooltip: 'Copy coordinates',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy, size: 15),
                onPressed: widget.onCopy,
              ),
              InkWell(
                onTap: widget.onClose,
                child: const Icon(Icons.close, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _label,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Label',
              hintText: 'e.g. Library steps, Gate 1 junction',
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            // Re-created when linking a building switches the type.
            key: ValueKey('type-$_type'),
            initialValue: _type,
            isDense: true,
            decoration:
                const InputDecoration(isDense: true, labelText: 'Node type'),
            items: [
              for (final t in outdoorArNodeTypes)
                DropdownMenuItem(value: t, child: Text(_typeLabel(t))),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int?>(
            initialValue: _buildingId,
            isExpanded: true,
            isDense: true,
            decoration: const InputDecoration(
                isDense: true, labelText: 'Linked building'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('None')),
              for (final x in buildings)
                DropdownMenuItem<int?>(
                  value: x.id,
                  child: Text('${x.arEmoji ?? _defaultEmoji}  ${x.name}',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() {
              _buildingId = v;
              // A building link means a route can end here.
              if (v != null && _type == 'path') _type = 'building';
            }),
          ),
          if (b != null) ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Text(b.arEmoji ?? _defaultEmoji,
                      style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (b.arLabel ?? '').isNotEmpty ? b.arLabel! : b.name,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Arrival radius '
                          '${_fmt(b.arArrivalRadiusM ?? _defaultArrivalRadiusM)} m'
                          ' · edit on the Building AR tab',
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _lat,
                  decoration: const InputDecoration(
                      isDense: true, labelText: 'Latitude'),
                  onChanged: _onLatChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _lng,
                  decoration: const InputDecoration(
                      isDense: true, labelText: 'Longitude'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _cBuilding,
                    foregroundColor: _cPathway,
                  ),
                  onPressed: widget.busy ? null : _save,
                  child: const Text('Save node'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Delete node',
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.errorRed),
                onPressed: widget.busy ? null : widget.onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<bool> _confirmFarFromCampus(BuildContext context, double distanceM) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text('Far from campus'),
      content: Text('This point is ${formatDistanceM(distanceM)} from the UM Matina '
          'campus. Check that latitude and longitude are not swapped or '
          'mistyped.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Go back'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Use anyway'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

// --- camera constraint ---------------------------------------------------------

/// Like [CameraConstraint.contain], but never rejects a camera: when the
/// viewport is bigger than [bounds] in a direction (zoomed out on a large
/// panel), the view is centred on [bounds] in that direction instead of
/// returning null (which would freeze the map). Idempotent within 0.5 px, so
/// flutter_map's "camera within constraint" check holds after any move.
class _CampusCameraConstraint extends CameraConstraint {
  final LatLngBounds bounds;
  const _CampusCameraConstraint(this.bounds);

  @override
  MapCamera constrain(MapCamera camera) {
    final zoom = camera.zoom;
    final ne = camera.projectAtZoom(bounds.northEast, zoom);
    final sw = camera.projectAtZoom(bounds.southWest, zoom);
    final half = camera.size / 2;

    double clampAxis(double v, double a, double b, double halfExtent) {
      final lo = math.min(a, b) + halfExtent;
      final hi = math.max(a, b) - halfExtent;
      return lo > hi ? (a + b) / 2 : v.clamp(lo, hi);
    }

    final center = camera.projectAtZoom(camera.center, zoom);
    final fixed = Offset(
      clampAxis(center.dx, sw.dx, ne.dx, half.width),
      clampAxis(center.dy, sw.dy, ne.dy, half.height),
    );
    if ((fixed - center).distance < 0.5) return camera;
    return camera.withPosition(center: camera.unprojectAtZoom(fixed, zoom));
  }

  @override
  bool operator ==(Object other) =>
      other is _CampusCameraConstraint && other.bounds == bounds;

  @override
  int get hashCode => bounds.hashCode;
}

// --- add by coordinates (side panel) ---------------------------------------------

class _AddByCoordinatesSection extends StatefulWidget {
  final bool open;
  final bool enabled;
  final VoidCallback onToggle;

  /// Saves the node; true on success (the form is then cleared).
  final Future<bool> Function(OutdoorArNodeModel node) onAdd;

  const _AddByCoordinatesSection({
    required this.open,
    required this.enabled,
    required this.onToggle,
    required this.onAdd,
  });

  @override
  State<_AddByCoordinatesSection> createState() =>
      _AddByCoordinatesSectionState();
}

class _AddByCoordinatesSectionState extends State<_AddByCoordinatesSection> {
  final _paste = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _label = TextEditingController();
  String _type = 'path';
  String? _pasteError;
  bool _saving = false;

  @override
  void dispose() {
    _paste.dispose();
    _lat.dispose();
    _lng.dispose();
    _label.dispose();
    super.dispose();
  }

  void _onPaste(String v) {
    if (v.trim().isEmpty) {
      setState(() => _pasteError = null);
      return;
    }
    final pair = parseLatLngPair(v);
    setState(() {
      if (pair == null) {
        _pasteError = 'Use "latitude, longitude", e.g. 7.06492, 125.59840';
      } else {
        _pasteError = null;
        _lat.text = pair.lat.toString();
        _lng.text = pair.lng.toString();
      }
    });
  }

  /// Pasting "lat, lng" straight into the latitude field fills both too.
  void _onLatChanged(String v) {
    final pair = parseLatLngPair(v);
    if (pair != null && v.contains(RegExp(r'[,;\s]'))) {
      _lat.text = pair.lat.toString();
      _lng.text = pair.lng.toString();
    }
    setState(() {});
  }

  double? get _latV => double.tryParse(_lat.text.trim());
  double? get _lngV => double.tryParse(_lng.text.trim());

  String? get _error {
    if (_lat.text.trim().isEmpty && _lng.text.trim().isEmpty) return null;
    return validateLatLng(_latV, _lngV);
  }

  double? get _farM {
    if (_lat.text.trim().isEmpty || _error != null) return null;
    final d = _distFromCampusM(_latV!, _lngV!);
    return d > _farFromCampusM ? d : null;
  }

  bool get _valid =>
      _lat.text.trim().isNotEmpty &&
      _lng.text.trim().isNotEmpty &&
      _error == null;

  Future<void> _submit() async {
    if (!_valid) return;
    final far = _farM;
    if (far != null) {
      final ok = await _confirmFarFromCampus(context, far);
      if (!ok || !mounted) return;
    }
    final label = _label.text.trim();
    setState(() => _saving = true);
    final added = await widget.onAdd(OutdoorArNodeModel(
      lat: _latV!,
      lng: _lngV!,
      label: label.isEmpty ? null : label,
      nodeType: _type,
    ));
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (added) {
        _paste.clear();
        _lat.clear();
        _lng.clear();
        _label.clear();
        _pasteError = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final err = _error;
    final far = _farM;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: widget.onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  const Icon(Icons.pin_drop_outlined,
                      size: 16, color: _cBuilding),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Add by coordinates',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                  Icon(widget.open ? Icons.expand_less : Icons.expand_more,
                      size: 18),
                ],
              ),
            ),
          ),
          if (widget.open)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _paste,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: "Paste 'lat, lng'",
                      hintText: '7.06492, 125.59840',
                      prefixIcon: const Icon(Icons.content_paste, size: 18),
                      errorText: _pasteError,
                    ),
                    onChanged: _onPaste,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _lat,
                          decoration: const InputDecoration(
                              isDense: true, labelText: 'Latitude *'),
                          onChanged: _onLatChanged,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _lng,
                          decoration: const InputDecoration(
                              isDense: true, labelText: 'Longitude *'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  if (err != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(err,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.errorRed)),
                    ),
                  if (far != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 16, color: AppColors.warningAmber),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'This point is ${formatDistanceM(far)} from campus. Check '
                              'that latitude and longitude are not swapped.',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _label,
                    decoration: const InputDecoration(
                        isDense: true, labelText: 'Label (optional)'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    isDense: true,
                    decoration: const InputDecoration(
                        isDense: true, labelText: 'Node type'),
                    items: [
                      for (final t in outdoorArNodeTypes)
                        DropdownMenuItem(value: t, child: Text(_typeLabel(t))),
                    ],
                    onChanged: (v) => setState(() => _type = v ?? _type),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _cBuilding,
                      foregroundColor: _cPathway,
                    ),
                    onPressed: widget.enabled && _valid && !_saving
                        ? _submit
                        : null,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: _cPathway),
                          )
                        : const Icon(Icons.add_location_alt_outlined, size: 16),
                    label: const Text('Add node'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// --- building AR settings panel -------------------------------------------

class _BuildingArPanel extends StatefulWidget {
  final BuildingModel building;
  final Future<bool> Function(String emoji, String label, double radiusM)
      onSave;
  final ValueChanged<double?> onRadiusPreview;
  final VoidCallback onLocate;

  const _BuildingArPanel({
    super.key,
    required this.building,
    required this.onSave,
    required this.onRadiusPreview,
    required this.onLocate,
  });

  @override
  State<_BuildingArPanel> createState() => _BuildingArPanelState();
}

class _BuildingArPanelState extends State<_BuildingArPanel> {
  static const _minRadiusM = 2.0;
  static const _maxRadiusM = 50.0;

  late final TextEditingController _emoji;
  late final TextEditingController _label;
  late final TextEditingController _radius;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final b = widget.building;
    _emoji = TextEditingController(text: b.arEmoji ?? _defaultEmoji);
    _label = TextEditingController(text: b.arLabel ?? '');
    _radius = TextEditingController(
        text: _fmt(b.arArrivalRadiusM ?? _defaultArrivalRadiusM));
  }

  @override
  void dispose() {
    _emoji.dispose();
    _label.dispose();
    _radius.dispose();
    super.dispose();
  }

  String get _previewLabel {
    final l = _label.text.trim();
    if (l.isNotEmpty) return l;
    final b = widget.building;
    if ((b.displayName ?? '').isNotEmpty) return b.displayName!;
    if ((b.shortName ?? '').isNotEmpty) return b.shortName!;
    return b.name;
  }

  Future<void> _save() async {
    final emoji = _emoji.text.trim();
    if (emoji.isEmpty) {
      context.showError('Enter an emoji for the AR marker.');
      return;
    }
    final radius = double.tryParse(_radius.text.trim());
    if (radius == null || radius < _minRadiusM || radius > _maxRadiusM) {
      context.showError('Arrival radius must be from ${_fmt(_minRadiusM)} to '
          '${_fmt(_maxRadiusM)} m.');
      return;
    }
    setState(() => _busy = true);
    await widget.onSave(emoji, _label.text.trim(), radius);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.building;
    return Container(
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
              Expanded(
                child: Text(b.name,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _cBuilding)),
              ),
              IconButton(
                tooltip: 'Locate',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.my_location, size: 16),
                onPressed: widget.onLocate,
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Preview of what the AR overlay shows.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Text(_emoji.text.trim().isEmpty ? '?' : _emoji.text.trim(),
                    style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_previewLabel,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _emoji,
            maxLength: 16,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'AR emoji',
              hintText: 'e.g. 📍 🏫 📚 🏀',
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _label,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'AR label',
              hintText: 'Defaults to the display / short name',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _radius,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Arrival radius',
              suffixText: 'm',
              helperText:
                  '${_fmt(_minRadiusM)}–${_fmt(_maxRadiusM)} m · green circle on the map',
            ),
            onChanged: (v) => widget.onRadiusPreview(double.tryParse(v.trim())),
          ),
          const SizedBox(height: 12),
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
                  : const Text('Save AR Settings'),
            ),
          ),
          if (b.lat == null || b.lng == null) ...[
            const SizedBox(height: 8),
            const Text(
              'This building has no coordinates, so the AR overlay cannot '
              'place its marker.',
              style: TextStyle(fontSize: 11, color: AppColors.errorRed),
            ),
          ],
        ],
      ),
    );
  }
}
