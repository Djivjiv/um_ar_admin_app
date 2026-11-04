import '../../core/utils/parse_utils.dart';

/// The `facilities` table, optionally joined with its one-to-one
/// `facility_details` row and the parent building's name.
class FacilityModel {
  final int? id;
  final String? roomname;
  final String? roomNumber;
  final int? buildingId;
  final String? buildingName;
  final int? floor;
  final String? facilityCategories;
  final List<String> description;
  final String? location;
  final String? createdAt;

  /// `facilities.access_level`, see access_level.dart. Null when empty or
  /// before db/access_level.sql has added the column.
  final String? accessLevel;

  /// `facilities.is_active`. Missing or null reads as true, matching the
  /// column default (and rows fetched without that column).
  final bool isActive;

  // From facility_details.
  final int? detailsId;
  final String? officeHours;
  final String? contactNumber;
  final List<String> services;
  final List<String> paymentMethod;
  final List<String> instructions;

  const FacilityModel({
    this.id,
    this.roomname,
    this.roomNumber,
    this.buildingId,
    this.buildingName,
    this.floor,
    this.facilityCategories,
    this.description = const [],
    this.location,
    this.createdAt,
    this.accessLevel,
    this.isActive = true,
    this.detailsId,
    this.officeHours,
    this.contactNumber,
    this.services = const [],
    this.paymentMethod = const [],
    this.instructions = const [],
  });

  /// PostgREST embeds a related row as either a Map (to-one) or a List
  /// (to-many). Normalise both to a single Map.
  static Map<String, dynamic>? _embed(dynamic raw) {
    if (raw is Map) return raw.cast<String, dynamic>();
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return (raw.first as Map).cast<String, dynamic>();
    }
    return null;
  }

  factory FacilityModel.fromJson(Map<String, dynamic> json) {
    final building = _embed(json['buildings']);
    final details = _embed(json['facility_details']);
    return FacilityModel(
      id: parseInt(json['id']),
      roomname: json['roomname']?.toString(),
      roomNumber: json['room_number']?.toString(),
      buildingId: parseInt(json['building_id']),
      buildingName: building?['name']?.toString(),
      floor: parseInt(json['floor']),
      facilityCategories: json['facility_categories']?.toString(),
      description: parseStringList(json['description']),
      location: json['location']?.toString(),
      createdAt: json['created_at']?.toString(),
      accessLevel: json['access_level']?.toString(),
      isActive: parseBool(json['is_active'], fallback: true),
      detailsId: parseInt(details?['id']),
      officeHours: details?['office_hours']?.toString(),
      contactNumber: details?['contact_number']?.toString(),
      services: parseStringList(details?['services']),
      paymentMethod: parseStringList(details?['payment_method']),
      instructions: parseStringList(details?['instructions']),
    );
  }

  /// Columns written to the `facilities` table. A null [accessLevel] is left
  /// out, so saves work before db/access_level.sql has been run.
  Map<String, dynamic> facilityJson() => {
        'roomname': roomname,
        'room_number': roomNumber,
        'building_id': buildingId,
        'floor': floor,
        'location': location,
        'facility_categories': facilityCategories,
        'description': description,
        'access_level': ?accessLevel,
        'is_active': isActive,
      };

  /// Columns written to the `facility_details` table (excludes `facility_id`,
  /// which the repository supplies).
  Map<String, dynamic> detailsJson() => {
        'office_hours': officeHours,
        'contact_number': contactNumber,
        'services': services,
        'payment_method': paymentMethod,
        'instructions': instructions,
      };
}
