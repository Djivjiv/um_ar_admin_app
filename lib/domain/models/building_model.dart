import '../../core/utils/parse_utils.dart';

class BuildingModel {
  final int? id;
  final String name;
  final String? imageUrl;
  final double? lat;
  final double? lng;
  final String? shortName;
  final List<String> description;
  final List<String> departments;
  final List<String> facilitiesList;
  final int? floorCount;
  final String? openingHours;
  final String? contact;
  final bool isAccessible;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Campus-map label editing — where the building's name tag is drawn
  // (independent of the building's own lat/lng) and what text it shows.
  final double? labelLat;
  final double? labelLng;
  final String? displayName;

  const BuildingModel({
    this.id,
    required this.name,
    this.imageUrl,
    this.lat,
    this.lng,
    this.shortName,
    this.description = const [],
    this.departments = const [],
    this.facilitiesList = const [],
    this.floorCount,
    this.openingHours,
    this.contact,
    this.isAccessible = false,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
    this.labelLat,
    this.labelLng,
    this.displayName,
  });

  factory BuildingModel.fromJson(Map<String, dynamic> json) {
    return BuildingModel(
      id: parseInt(json['id']),
      name: json['name']?.toString() ?? '',
      imageUrl: json['image_url']?.toString(),
      lat: parseDouble(json['lat']),
      lng: parseDouble(json['lng']),
      shortName: json['short_name']?.toString(),
      description: parseStringList(json['description']),
      departments: parseStringList(json['departments']),
      facilitiesList: parseStringList(json['facilities_list']),
      floorCount: parseInt(json['floor_count']),
      openingHours: json['opening_hours']?.toString(),
      contact: json['contact']?.toString(),
      isAccessible: parseBool(json['is_accessible']),
      isActive: parseBool(json['is_active'], fallback: true),
      createdAt: parseDate(json['created_at']),
      updatedAt: parseDate(json['updated_at']),
      labelLat: parseDouble(json['label_lat']),
      labelLng: parseDouble(json['label_lng']),
      displayName: json['display_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'image_url': imageUrl,
      'lat': lat,
      'lng': lng,
      'short_name': shortName,
      'description': description,
      'departments': departments,
      'facilities_list': facilitiesList,
      'floor_count': floorCount,
      'opening_hours': openingHours,
      'contact': contact,
      'is_accessible': isAccessible,
      'is_active': isActive,
      'label_lat': labelLat,
      'label_lng': labelLng,
      'display_name': displayName,
    };
  }

  BuildingModel copyWith({
    int? id,
    String? name,
    String? imageUrl,
    double? lat,
    double? lng,
    String? shortName,
    List<String>? description,
    List<String>? departments,
    List<String>? facilitiesList,
    int? floorCount,
    String? openingHours,
    String? contact,
    bool? isAccessible,
    bool? isActive,
    double? labelLat,
    double? labelLng,
    String? displayName,
  }) {
    return BuildingModel(
      id: id ?? this.id,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      shortName: shortName ?? this.shortName,
      description: description ?? this.description,
      departments: departments ?? this.departments,
      facilitiesList: facilitiesList ?? this.facilitiesList,
      floorCount: floorCount ?? this.floorCount,
      openingHours: openingHours ?? this.openingHours,
      contact: contact ?? this.contact,
      isAccessible: isAccessible ?? this.isAccessible,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
      labelLat: labelLat ?? this.labelLat,
      labelLng: labelLng ?? this.labelLng,
      displayName: displayName ?? this.displayName,
    );
  }

  /// Explicitly clears the custom display name (falls back to short_name /
  /// name on the map) — [copyWith]'s `??` semantics can't express "set to
  /// null", so this rebuilds every field by hand.
  BuildingModel clearDisplayName() {
    return BuildingModel(
      id: id,
      name: name,
      imageUrl: imageUrl,
      lat: lat,
      lng: lng,
      shortName: shortName,
      description: description,
      departments: departments,
      facilitiesList: facilitiesList,
      floorCount: floorCount,
      openingHours: openingHours,
      contact: contact,
      isAccessible: isAccessible,
      isActive: isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
      labelLat: labelLat,
      labelLng: labelLng,
      displayName: null,
    );
  }

  /// Explicitly resets the label position so it falls back to the building's
  /// own lat/lng — see [clearDisplayName] for why this can't be [copyWith].
  BuildingModel clearLabelPosition() {
    return BuildingModel(
      id: id,
      name: name,
      imageUrl: imageUrl,
      lat: lat,
      lng: lng,
      shortName: shortName,
      description: description,
      departments: departments,
      facilitiesList: facilitiesList,
      floorCount: floorCount,
      openingHours: openingHours,
      contact: contact,
      isAccessible: isAccessible,
      isActive: isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
      labelLat: null,
      labelLng: null,
      displayName: displayName,
    );
  }
}
