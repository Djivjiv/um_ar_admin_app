import 'dart:math' as math;

import '../../domain/models/floor_distance_model.dart';
import '../../domain/models/floor_plan_model.dart';
import '../../domain/models/indoor_edge_model.dart';
import '../../domain/models/indoor_node_model.dart';

/// The shortest gap a pair can be measured over. Node positions are whole
/// pixels placed by hand, so at 50 px being 1 px off is already a 2% error.
const double kMinMeasurePixels = 50;

/// A pair further than this from the floor average is highlighted, and a
/// spread above it gives a warning.
const double kMaxScalePercent = 5;

/// Below this many counted measurements the scale gets a warning.
const int kMinCountedMeasurements = 3;

/// The straight-line pixel gap between two nodes, or null when either is
/// missing or has no position.
double? nodePixelDistance(IndoorNodeModel? a, IndoorNodeModel? b) {
  final ax = a?.x, ay = a?.y, bx = b?.x, by = b?.y;
  if (ax == null || ay == null || bx == null || by == null) return null;
  final dx = ax - bx;
  final dy = ay - by;
  return math.sqrt(dx * dx + dy * dy);
}

/// What the Check distance panel calls a node.
String nodeDisplayName(IndoorNodeModel? node, String id) {
  for (final text in [node?.name, node?.roomName, node?.roomNumber]) {
    if (text != null && text.trim().isNotEmpty) return text.trim();
  }
  return id;
}

/// The scale as saved: 6 decimals, about 0.003% of a typical floor's scale.
double roundScale(double metersPerPixel) =>
    double.parse(metersPerPixel.toStringAsFixed(6));

/// Why [nodeA] and [nodeB], [pixels] apart, can't be measured, or null if
/// they can. [nodeA] and [nodeB] don't need an edge between them.
String? validateMeasurePair(String nodeA, String nodeB, double? pixels) {
  if (nodeA == nodeB) return 'Pick two different nodes';
  if (pixels == null) return 'One of these nodes has no position on the plan';
  if (pixels < kMinMeasurePixels) {
    return 'These nodes are only ${pixels.toStringAsFixed(0)} px apart. Pick '
        'nodes at least ${kMinMeasurePixels.toStringAsFixed(0)} px apart, as '
        'a tiny gap gives a wild scale.';
  }
  return null;
}

/// Form validator for the real distance of a pair [pixels] apart.
String? validateRealMeters(String? text, double pixels) {
  final meters = double.tryParse((text ?? '').trim());
  if (meters == null || !meters.isFinite || meters <= 0) {
    return 'Enter a distance greater than 0';
  }
  final scale = meters / pixels;
  if (roundScale(scale) <= 0) return 'That distance is too small to measure';
  return validateMetersPerPixel('$scale');
}

/// One measurement, worked out against the floor's other measurements.
class MeasurementLine {
  final FloorDistanceModel measurement;

  /// Null when a node has no position.
  final double? pixels;

  /// Meters per pixel this pair gives; null when it can't be used.
  final double? scale;

  /// Percent above (+) or below (-) the floor average; null with no average.
  final double? differencePercent;

  const MeasurementLine({
    required this.measurement,
    this.pixels,
    this.scale,
    this.differencePercent,
  });

  /// In the floor's average.
  bool get counted => scale != null && !measurement.ignored;

  /// Nodes moved so close together that the pair can't be used.
  bool get tooClose => pixels != null && pixels! < kMinMeasurePixels;

  bool get isOutlier => (differencePercent?.abs() ?? 0) > kMaxScalePercent;
}

class FloorScaleSummary {
  final List<MeasurementLine> lines;
  final int counted;

  /// The scale to save; null when nothing is counted, so the floor keeps the
  /// one it has.
  final double? metersPerPixel;

  /// Standard deviation of the counted per-pair scales, as a percent of their
  /// mean. Null with fewer than 2, as one number has no spread.
  final double? spreadPercent;

  const FloorScaleSummary({
    this.lines = const [],
    this.counted = 0,
    this.metersPerPixel,
    this.spreadPercent,
  });

  bool get hasTooFew => counted > 0 && counted < kMinCountedMeasurements;

  bool get hasHighSpread => (spreadPercent ?? 0) > kMaxScalePercent;

  List<String> get warnings => [
        if (hasTooFew)
          'Only $counted counted. Measure at least '
              '$kMinCountedMeasurements pairs so one mistake can\'t set the '
              'scale.',
        if (hasHighSpread)
          'The spread is ${spreadPercent!.toStringAsFixed(1)}%, above '
              '${kMaxScalePercent.toStringAsFixed(0)}%. Check the highlighted '
              'measurements, then edit or ignore any that are wrong.',
      ];
}

/// The floor's scale from [measurements]: total real meters over total pixels
/// of the counted pairs, so a long pair weighs more than a short one. A pair
/// counts unless it is ignored, a node has no position, or its gap is under
/// [kMinMeasurePixels].
FloorScaleSummary computeFloorScale(
  List<FloorDistanceModel> measurements,
  Iterable<IndoorNodeModel> nodes,
) {
  final byId = {for (final n in nodes) n.id: n};
  var totalMeters = 0.0;
  var totalPixels = 0.0;
  final scales = <double>[];
  final measured = <(FloorDistanceModel, double?, double?)>[];
  for (final m in measurements) {
    final pixels = nodePixelDistance(byId[m.nodeAId], byId[m.nodeBId]);
    final usable = pixels != null && pixels >= kMinMeasurePixels;
    final scale = usable ? m.realMeters / pixels : null;
    measured.add((m, pixels, scale));
    if (scale == null || m.ignored) continue;
    totalMeters += m.realMeters;
    totalPixels += pixels!;
    scales.add(scale);
  }

  final average = totalPixels > 0 ? totalMeters / totalPixels : null;
  return FloorScaleSummary(
    lines: [
      for (final (m, pixels, scale) in measured)
        MeasurementLine(
          measurement: m,
          pixels: pixels,
          scale: scale,
          differencePercent: scale == null || average == null
              ? null
              : (scale - average) / average * 100,
        ),
    ],
    counted: scales.length,
    metersPerPixel: average == null ? null : roundScale(average),
    spreadPercent: _spreadPercent(scales),
  );
}

double? _spreadPercent(List<double> scales) {
  if (scales.length < 2) return null;
  final mean = scales.reduce((a, b) => a + b) / scales.length;
  final squares =
      scales.fold(0.0, (sum, s) => sum + (s - mean) * (s - mean));
  return math.sqrt(squares / (scales.length - 1)) / mean * 100;
}

/// What to tell the admin when nothing is counted and [plan] keeps its scale.
String unchangedScaleNote(FloorPlanModel plan) {
  const start = 'No measurements are counted, so ';
  if (plan.metersPerPixel == null) return '${start}this floor stays not calibrated.';
  return plan.isScaleCalibrated
      ? '${start}the scale stays at the last saved ${plan.metersPerPixel} m/px.'
      : '${start}the scale is still the default ${plan.metersPerPixel} m/px.';
}

/// One edge in the Check distance panel.
class EdgeDistanceLine {
  final IndoorEdgeModel edge;

  /// Null when a node isn't on this floor plan: a cross-building edge has one
  /// end on another image, so no pixel length exists.
  final double? pixels;
  final double? meters;

  const EdgeDistanceLine({required this.edge, this.pixels, this.meters});
}

/// Every edge in [edges], with its distance at [metersPerPixel].
List<EdgeDistanceLine> edgeDistanceLines(
  List<IndoorEdgeModel> edges,
  Iterable<IndoorNodeModel> nodes,
  double metersPerPixel,
) {
  final byId = {for (final n in nodes) n.id: n};
  return [
    for (final e in edges)
      () {
        final pixels = nodePixelDistance(byId[e.fromNode], byId[e.toNode]);
        return EdgeDistanceLine(
          edge: e,
          pixels: pixels,
          meters: pixels == null ? null : pixels * metersPerPixel,
        );
      }(),
  ];
}

/// One drag of a node, from where it was to where it was dropped.
class NodeMove {
  final String id;
  final double fromX;
  final double fromY;
  final double toX;
  final double toY;

  const NodeMove({
    required this.id,
    required this.fromX,
    required this.fromY,
    required this.toX,
    required this.toY,
  });
}

/// The drags not saved yet, in order, so they can be undone one at a time.
class NodeMoveLog {
  final List<NodeMove> _moves = [];

  bool get isEmpty => _moves.isEmpty;

  int get length => _moves.length;

  void add(NodeMove move) => _moves.add(move);

  /// Takes back the latest drag and returns it.
  NodeMove? undo() => _moves.isEmpty ? null : _moves.removeLast();

  void clear() => _moves.clear();

  /// Each node's first position to its last, leaving out any that ended up
  /// back where they started.
  List<NodeMove> get netMoves {
    final net = <String, NodeMove>{};
    for (final m in _moves) {
      final first = net[m.id];
      net[m.id] = NodeMove(
        id: m.id,
        fromX: first?.fromX ?? m.fromX,
        fromY: first?.fromY ?? m.fromY,
        toX: m.toX,
        toY: m.toY,
      );
    }
    return [
      for (final m in net.values)
        if (m.fromX != m.toX || m.fromY != m.toY) m,
    ];
  }
}

/// A new pixel length for an edge, with the old one to put back on failure.
class EdgeLengthChange {
  final String id;
  final double? oldWeight;
  final double newWeight;

  const EdgeLengthChange({
    required this.id,
    this.oldWeight,
    required this.newWeight,
  });
}

/// The new length of each edge joined to a node in [movedIds]. Edges with an
/// end off this floor are skipped: their weight is a fixed cost, not a length.
List<EdgeLengthChange> edgeLengthChanges(
  List<IndoorEdgeModel> edges,
  Iterable<IndoorNodeModel> nodes,
  Set<String> movedIds,
) {
  final byId = {for (final n in nodes) n.id: n};
  return [
    for (final e in edges)
      if (e.id != null &&
          (movedIds.contains(e.fromNode) || movedIds.contains(e.toNode)))
        if (nodePixelDistance(byId[e.fromNode], byId[e.toNode])
            case final pixels? when pixels > 0)
          EdgeLengthChange(id: e.id!, oldWeight: e.weight, newWeight: pixels),
  ];
}

/// The measurements with a node in [nodeIds].
List<FloorDistanceModel> measurementsTouching(
  List<FloorDistanceModel> measurements,
  Set<String> nodeIds,
) =>
    [
      for (final m in measurements)
        if (nodeIds.any(m.touches)) m,
    ];
