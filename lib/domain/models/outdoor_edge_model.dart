import '../../core/utils/parse_utils.dart';

class OutdoorEdgeModel {
  final String? id;
  final String fromNode;
  final String toNode;
  final double? weight;
  final bool isTwoWay;
  final bool isActive;
  final DateTime? createdAt;

  const OutdoorEdgeModel({
    this.id,
    required this.fromNode,
    required this.toNode,
    this.weight,
    this.isTwoWay = true,
    this.isActive = true,
    this.createdAt,
  });

  factory OutdoorEdgeModel.fromJson(Map<String, dynamic> json) {
    return OutdoorEdgeModel(
      id: json['id']?.toString(),
      fromNode: json['from_node']?.toString() ?? '',
      toNode: json['to_node']?.toString() ?? '',
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
      'weight': weight,
      'is_two_way': isTwoWay,
      'is_active': isActive,
    };
  }
}
