import '../../core/utils/parse_utils.dart';

class OutdoorNodeModel {
  final String id;
  final String? name;
  final String? type;
  final double? lat;
  final double? lng;

  /// Linked building id (kept as a String for form binding; the column is int8).
  final String? buildingId;
  final bool isEntrance;
  final String? entranceLabel;

  /// Links this outdoor entrance to a node in `indoor_nodes`.
  final String? indoorNodeId;
  final int floor;

  /// Deep-link value encoded into this entrance's QR code (e.g.
  /// `UM_AR://{buildingId}/entrance/{nodeId}`). Only meaningful when
  /// [isEntrance] is true.
  final String? qrCodeValue;

  final bool isActive;
  final DateTime? createdAt;

  /// Populated from the embedded `buildings(...)` select (read-only).
  final String? buildingName;
  final String? buildingShortName;

  const OutdoorNodeModel({
    required this.id,
    this.name,
    this.type,
    this.lat,
    this.lng,
    this.buildingId,
    this.isEntrance = false,
    this.entranceLabel,
    this.indoorNodeId,
    this.floor = 1,
    this.qrCodeValue,
    this.isActive = true,
    this.createdAt,
    this.buildingName,
    this.buildingShortName,
  });

  factory OutdoorNodeModel.fromJson(Map<String, dynamic> json) {
    final building = json['buildings'];
    final Map<String, dynamic>? b =
        building is Map ? building.cast<String, dynamic>() : null;
    return OutdoorNodeModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString(),
      type: json['type']?.toString(),
      lat: parseDouble(json['lat'] ?? json['latitude'] ?? json['y']),
      lng: parseDouble(json['lng'] ??
          json['lon'] ??
          json['long'] ??
          json['longitude'] ??
          json['x']),
      buildingId: json['building_id']?.toString(),
      isEntrance: parseBool(json['is_entrance']),
      entranceLabel: json['entrance_label']?.toString(),
      indoorNodeId: json['indoor_node_id']?.toString(),
      floor: parseInt(json['floor']) ?? 1,
      qrCodeValue: json['qr_code_value']?.toString(),
      isActive: parseBool(json['is_active'], fallback: true),
      createdAt: parseDate(json['created_at']),
      buildingName: b?['name']?.toString(),
      buildingShortName: b?['short_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'lat': lat,
      'lng': lng,
      'building_id': (buildingId == null || buildingId!.isEmpty)
          ? null
          : buildingId,
      'is_entrance': isEntrance,
      'entrance_label': entranceLabel,
      'indoor_node_id': indoorNodeId,
      'floor': floor,
      'qr_code_value': qrCodeValue,
      'is_active': isActive,
    };
  }

  OutdoorNodeModel copyWith({
    String? id,
    String? name,
    String? type,
    double? lat,
    double? lng,
    String? buildingId,
    bool? isEntrance,
    String? entranceLabel,
    String? indoorNodeId,
    int? floor,
    String? qrCodeValue,
    bool? isActive,
  }) {
    return OutdoorNodeModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      buildingId: buildingId ?? this.buildingId,
      isEntrance: isEntrance ?? this.isEntrance,
      entranceLabel: entranceLabel ?? this.entranceLabel,
      indoorNodeId: indoorNodeId ?? this.indoorNodeId,
      floor: floor ?? this.floor,
      qrCodeValue: qrCodeValue ?? this.qrCodeValue,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      buildingName: buildingName,
      buildingShortName: buildingShortName,
    );
  }
}
