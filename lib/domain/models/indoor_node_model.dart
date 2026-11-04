import '../../core/utils/parse_utils.dart';

class IndoorNodeModel {
  final String id;
  final int? floorPlanId;
  final int? buildingId;
  final String? name;
  final String? label;
  final double? x;
  final double? y;

  /// Legacy GPS coordinates from the old georeferencing workflow. No longer
  /// written by the editor — [x]/[y] image pixels are the source of truth.
  final double? lat;
  final double? lng;

  final String? roomId;

  final bool isEntrance;
  final String? entranceLabel;

  /// Links this indoor entrance to a node in `outdoor_nodes`.
  final String? outdoorNodeId;

  /// Navigation node (true) vs informational-only node (false).
  final bool isNavigable;

  // Informational-node fields.
  final String? roomName;
  final String? roomNumber;
  final String? nodeDescription;
  final int floor;
  final String? linkedRoomId;

  /// Which table [linkedRoomId] points at: 'rooms' or 'facilities'.
  final String? linkedTable;
  final String? operatingHours;
  final String? contact;

  /// Shared id for the same staircase/elevator across every floor
  /// (e.g. `BE_STAIRS_A`). Only meaningful for `stairs`/`elevator` labels.
  final String? stairGroup;

  /// Shared id linking this node to a node in another building
  /// (e.g. `DPT_GET_CORRIDOR_F1`). The two nodes with the same ref are joined
  /// by an edge. Only meaningful for `entrance` labels.
  final String? crossBuildingRef;

  /// AR-space coordinates for this node, calibrated per floor in Unity.
  final double? unityX;
  final double? unityY;
  final double? unityZ;

  final bool isActive;
  final DateTime? createdAt;

  const IndoorNodeModel({
    required this.id,
    this.floorPlanId,
    this.buildingId,
    this.name,
    this.label,
    this.x,
    this.y,
    this.lat,
    this.lng,
    this.roomId,
    this.isEntrance = false,
    this.entranceLabel,
    this.outdoorNodeId,
    this.isNavigable = true,
    this.roomName,
    this.roomNumber,
    this.nodeDescription,
    this.floor = 1,
    this.linkedRoomId,
    this.linkedTable,
    this.operatingHours,
    this.contact,
    this.stairGroup,
    this.crossBuildingRef,
    this.unityX,
    this.unityY,
    this.unityZ,
    this.isActive = true,
    this.createdAt,
  });

  factory IndoorNodeModel.fromJson(Map<String, dynamic> json) {
    return IndoorNodeModel(
      id: json['id']?.toString() ?? '',
      floorPlanId: parseInt(json['floor_plan_id']),
      buildingId: parseInt(json['building_id']),
      name: json['name']?.toString(),
      label: json['label']?.toString(),
      x: parseDouble(json['x']),
      y: parseDouble(json['y']),
      lat: parseDouble(json['lat']),
      lng: parseDouble(json['lng']),
      roomId: json['room_id']?.toString(),
      isEntrance: parseBool(json['is_entrance']),
      entranceLabel: json['entrance_label']?.toString(),
      outdoorNodeId: json['outdoor_node_id']?.toString(),
      isNavigable: parseBool(json['is_navigable'], fallback: true),
      roomName: json['room_name']?.toString(),
      roomNumber: json['room_number']?.toString(),
      nodeDescription: json['node_description']?.toString(),
      floor: parseInt(json['floor']) ?? 1,
      linkedRoomId: json['linked_room_id']?.toString(),
      linkedTable: json['linked_table']?.toString(),
      operatingHours: json['operating_hours']?.toString(),
      contact: json['contact']?.toString(),
      stairGroup: json['stair_group']?.toString(),
      crossBuildingRef: json['cross_building_ref']?.toString(),
      unityX: parseDouble(json['unity_x']),
      unityY: parseDouble(json['unity_y']),
      unityZ: parseDouble(json['unity_z']),
      isActive: parseBool(json['is_active'], fallback: true),
      createdAt: parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    String? nn(String? s) => (s == null || s.isEmpty) ? null : s;
    return {
      'id': id,
      'floor_plan_id': floorPlanId,
      'building_id': buildingId,
      'name': nn(name),
      'label': nn(label),
      'x': x,
      'y': y,
      'lat': lat,
      'lng': lng,
      'room_id': nn(roomId),
      'is_entrance': isEntrance,
      'entrance_label': nn(entranceLabel),
      'outdoor_node_id': nn(outdoorNodeId),
      'is_navigable': isNavigable,
      'room_name': nn(roomName),
      'room_number': nn(roomNumber),
      'node_description': nn(nodeDescription),
      'floor': floor,
      'linked_room_id': nn(linkedRoomId),
      'linked_table': nn(linkedTable),
      'operating_hours': nn(operatingHours),
      'contact': nn(contact),
      'stair_group': nn(stairGroup),
      'cross_building_ref': nn(crossBuildingRef),
      'unity_x': unityX,
      'unity_y': unityY,
      'unity_z': unityZ,
      'is_active': isActive,
    };
  }

  IndoorNodeModel copyWith({
    String? name,
    String? label,
    double? x,
    double? y,
    double? lat,
    double? lng,
    String? roomId,
    bool? isEntrance,
    String? entranceLabel,
    String? outdoorNodeId,
    bool? isNavigable,
    String? roomName,
    String? roomNumber,
    String? nodeDescription,
    int? floor,
    String? linkedRoomId,
    String? linkedTable,
    String? operatingHours,
    String? contact,
    String? stairGroup,
    String? crossBuildingRef,
    double? unityX,
    double? unityY,
    double? unityZ,
    bool? isActive,
  }) {
    return IndoorNodeModel(
      id: id,
      floorPlanId: floorPlanId,
      buildingId: buildingId,
      name: name ?? this.name,
      label: label ?? this.label,
      x: x ?? this.x,
      y: y ?? this.y,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      roomId: roomId ?? this.roomId,
      isEntrance: isEntrance ?? this.isEntrance,
      entranceLabel: entranceLabel ?? this.entranceLabel,
      outdoorNodeId: outdoorNodeId ?? this.outdoorNodeId,
      isNavigable: isNavigable ?? this.isNavigable,
      roomName: roomName ?? this.roomName,
      roomNumber: roomNumber ?? this.roomNumber,
      nodeDescription: nodeDescription ?? this.nodeDescription,
      floor: floor ?? this.floor,
      linkedRoomId: linkedRoomId ?? this.linkedRoomId,
      linkedTable: linkedTable ?? this.linkedTable,
      operatingHours: operatingHours ?? this.operatingHours,
      contact: contact ?? this.contact,
      stairGroup: stairGroup ?? this.stairGroup,
      crossBuildingRef: crossBuildingRef ?? this.crossBuildingRef,
      unityX: unityX ?? this.unityX,
      unityY: unityY ?? this.unityY,
      unityZ: unityZ ?? this.unityZ,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }
}
