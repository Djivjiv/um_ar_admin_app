import '../../core/utils/parse_utils.dart';

class IndoorEdgeModel {
  final String? id;
  final String fromNode;
  final String toNode;
  final int? floorPlanId;
  final double? weight;
  final bool isTwoWay;
  final bool isActive;
  final DateTime? createdAt;

  const IndoorEdgeModel({
    this.id,
    required this.fromNode,
    required this.toNode,
    this.floorPlanId,
    this.weight,
    this.isTwoWay = true,
    this.isActive = true,
    this.createdAt,
  });

  factory IndoorEdgeModel.fromJson(Map<String, dynamic> json) {
    return IndoorEdgeModel(
      id: json['id']?.toString(),
      fromNode: json['from_node']?.toString() ?? '',
      toNode: json['to_node']?.toString() ?? '',
      floorPlanId: parseInt(json['floor_plan_id']),
      weight: parseDouble(json['weight']),
      isTwoWay: parseBool(json['is_two_way'], fallback: true),
      isActive: parseBool(json['is_active'], fallback: true),
      createdAt: parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'from_node': fromNode,
      'to_node': toNode,
      'floor_plan_id': floorPlanId,
      'weight': weight,
      'is_two_way': isTwoWay,
      'is_active': isActive,
    };
  }
}
