import '../../core/utils/parse_utils.dart';

/// An undirected edge of the Outdoor AR path network (`outdoor_ar_edges`).
class OutdoorArEdgeModel {
  /// uuid; null before insert.
  final String? id;
  final String fromNode;
  final String toNode;

  /// Haversine length in metres.
  final double? weightM;
  final bool isActive;

  const OutdoorArEdgeModel({
    this.id,
    required this.fromNode,
    required this.toNode,
    this.weightM,
    this.isActive = true,
  });

  factory OutdoorArEdgeModel.fromJson(Map<String, dynamic> json) {
    return OutdoorArEdgeModel(
      id: json['id']?.toString(),
      fromNode: json['from_node']?.toString() ?? '',
      toNode: json['to_node']?.toString() ?? '',
      weightM: parseDouble(json['weight_m']),
      isActive: parseBool(json['is_active'], fallback: true),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'from_node': fromNode,
      'to_node': toNode,
      'weight_m': weightM,
      'is_active': isActive,
    };
  }

  bool touches(String nodeId) => fromNode == nodeId || toNode == nodeId;

  /// True if this edge joins [a] and [b] in either direction.
  bool joins(String a, String b) =>
      (fromNode == a && toNode == b) || (fromNode == b && toNode == a);

  OutdoorArEdgeModel copyWith({double? weightM}) {
    return OutdoorArEdgeModel(
      id: id,
      fromNode: fromNode,
      toNode: toNode,
      weightM: weightM ?? this.weightM,
      isActive: isActive,
    );
  }
}
