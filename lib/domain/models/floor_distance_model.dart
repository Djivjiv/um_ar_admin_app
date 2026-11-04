import '../../core/utils/parse_utils.dart';

/// Maps to the `floor_plan_distances` table: a real-world distance measured
/// between two nodes of a floor. The pixel distance isn't stored, as it comes
/// from the nodes' current x/y.
class FloorDistanceModel {
  final String id;
  final int? floorPlanId;
  final String nodeAId;
  final String nodeBId;
  final double realMeters;

  /// Kept on the list, but left out of the floor's scale.
  final bool ignored;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FloorDistanceModel({
    required this.id,
    this.floorPlanId,
    required this.nodeAId,
    required this.nodeBId,
    required this.realMeters,
    this.ignored = false,
    this.createdAt,
    this.updatedAt,
  });

  bool touches(String nodeId) => nodeAId == nodeId || nodeBId == nodeId;

  factory FloorDistanceModel.fromJson(Map<String, dynamic> json) {
    return FloorDistanceModel(
      id: json['id']?.toString() ?? '',
      floorPlanId: parseInt(json['floor_plan_id']),
      nodeAId: json['node_a_id']?.toString() ?? '',
      nodeBId: json['node_b_id']?.toString() ?? '',
      realMeters: parseDouble(json['real_meters']) ?? 0,
      ignored: parseBool(json['ignored']),
      createdAt: parseDate(json['created_at']),
      updatedAt: parseDate(json['updated_at']),
    );
  }
}
