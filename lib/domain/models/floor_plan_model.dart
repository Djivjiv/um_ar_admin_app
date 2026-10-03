import '../../core/utils/parse_utils.dart';

/// Maps to the `building_floors` table.
class FloorPlanModel {
  final int? id;
  final int? buildingId;
  final int? floorNumber;
  final String? floorName;
  final String? imageUrl;

  // Georeferencing — four corner GPS coordinates + center, set by the
  // GeoreferencingScreen. Null until the plan has been georeferenced.
  final double? nwLat;
  final double? nwLng;
  final double? neLat;
  final double? neLng;
  final double? swLat;
  final double? swLng;
  final double? seLat;
  final double? seLng;
  final double? centerLat;
  final double? centerLng;
  final double rotationAngle;
  final double scaleFactor;
  final bool isGeoreferenced;
  final bool isActive;

  final DateTime? createdAt;

  const FloorPlanModel({
    this.id,
    this.buildingId,
    this.floorNumber,
    this.floorName,
    this.imageUrl,
    this.nwLat,
    this.nwLng,
    this.neLat,
    this.neLng,
    this.swLat,
    this.swLng,
    this.seLat,
    this.seLng,
    this.centerLat,
    this.centerLng,
    this.rotationAngle = 0.0,
    this.scaleFactor = 1.0,
    this.isGeoreferenced = false,
    this.isActive = true,
    this.createdAt,
  });

  factory FloorPlanModel.fromJson(Map<String, dynamic> json) {
    return FloorPlanModel(
      id: parseInt(json['id']),
      buildingId: parseInt(json['building_id']),
      floorNumber: parseInt(json['floor_number']),
      floorName: json['floor_name']?.toString(),
      imageUrl: json['image_url']?.toString(),
      nwLat: parseDouble(json['nw_lat']),
      nwLng: parseDouble(json['nw_lng']),
      neLat: parseDouble(json['ne_lat']),
      neLng: parseDouble(json['ne_lng']),
      swLat: parseDouble(json['sw_lat']),
      swLng: parseDouble(json['sw_lng']),
      seLat: parseDouble(json['se_lat']),
      seLng: parseDouble(json['se_lng']),
      centerLat: parseDouble(json['center_lat']),
      centerLng: parseDouble(json['center_lng']),
      rotationAngle: parseDouble(json['rotation_angle']) ?? 0.0,
      scaleFactor: parseDouble(json['scale_factor']) ?? 1.0,
      isGeoreferenced: parseBool(json['is_georeferenced']),
      isActive: parseBool(json['is_active'], fallback: true),
      createdAt: parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'building_id': buildingId,
      'floor_number': floorNumber,
      'floor_name': floorName,
      'image_url': imageUrl,
      'nw_lat': nwLat,
      'nw_lng': nwLng,
      'ne_lat': neLat,
      'ne_lng': neLng,
      'sw_lat': swLat,
      'sw_lng': swLng,
      'se_lat': seLat,
      'se_lng': seLng,
      'center_lat': centerLat,
      'center_lng': centerLng,
      'rotation_angle': rotationAngle,
      'scale_factor': scaleFactor,
      'is_georeferenced': isGeoreferenced,
      'is_active': isActive,
    };
  }

  FloorPlanModel copyWith({
    int? id,
    int? buildingId,
    int? floorNumber,
    String? floorName,
    String? imageUrl,
    double? nwLat,
    double? nwLng,
    double? neLat,
    double? neLng,
    double? swLat,
    double? swLng,
    double? seLat,
    double? seLng,
    double? centerLat,
    double? centerLng,
    double? rotationAngle,
    double? scaleFactor,
    bool? isGeoreferenced,
    bool? isActive,
  }) {
    return FloorPlanModel(
      id: id ?? this.id,
      buildingId: buildingId ?? this.buildingId,
      floorNumber: floorNumber ?? this.floorNumber,
      floorName: floorName ?? this.floorName,
      imageUrl: imageUrl ?? this.imageUrl,
      nwLat: nwLat ?? this.nwLat,
      nwLng: nwLng ?? this.nwLng,
      neLat: neLat ?? this.neLat,
      neLng: neLng ?? this.neLng,
      swLat: swLat ?? this.swLat,
      swLng: swLng ?? this.swLng,
      seLat: seLat ?? this.seLat,
      seLng: seLng ?? this.seLng,
      centerLat: centerLat ?? this.centerLat,
      centerLng: centerLng ?? this.centerLng,
      rotationAngle: rotationAngle ?? this.rotationAngle,
      scaleFactor: scaleFactor ?? this.scaleFactor,
      isGeoreferenced: isGeoreferenced ?? this.isGeoreferenced,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }
}
