import '../../core/utils/parse_utils.dart';

/// Node types allowed by the `outdoor_ar_nodes.node_type` check constraint.
const outdoorArNodeTypes = ['path', 'junction', 'building'];

/// A node of the independent Outdoor AR path network (`outdoor_ar_nodes`).
class OutdoorArNodeModel {
  /// uuid; null before insert.
  final String? id;
  final double lat;
  final double lng;
  final String? label;
  final String nodeType;

  /// Linked building (`buildings.id`), so a route can end here.
  final int? buildingId;
  final bool isActive;
  final DateTime? createdAt;

  const OutdoorArNodeModel({
    this.id,
    required this.lat,
    required this.lng,
    this.label,
    this.nodeType = 'path',
    this.buildingId,
    this.isActive = true,
    this.createdAt,
  });

  factory OutdoorArNodeModel.fromJson(Map<String, dynamic> json) {
    return OutdoorArNodeModel(
      id: json['id']?.toString(),
      lat: parseDouble(json['lat']) ?? 0,
      lng: parseDouble(json['lng']) ?? 0,
      label: json['label']?.toString(),
      nodeType: json['node_type']?.toString() ?? 'path',
      buildingId: parseInt(json['building_id']),
      isActive: parseBool(json['is_active'], fallback: true),
      createdAt: parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'lat': lat,
      'lng': lng,
      'label': (label == null || label!.isEmpty) ? null : label,
      'node_type': nodeType,
      'building_id': buildingId,
      'is_active': isActive,
    };
  }

  /// `??` can't set [buildingId] or [label] back to null — pass
  /// `clearBuilding: true` / `clearLabel: true` for that.
  OutdoorArNodeModel copyWith({
    double? lat,
    double? lng,
    String? label,
    bool clearLabel = false,
    String? nodeType,
    int? buildingId,
    bool clearBuilding = false,
    bool? isActive,
  }) {
    return OutdoorArNodeModel(
      id: id,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      label: clearLabel ? null : (label ?? this.label),
      nodeType: nodeType ?? this.nodeType,
      buildingId: clearBuilding ? null : (buildingId ?? this.buildingId),
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }
}
