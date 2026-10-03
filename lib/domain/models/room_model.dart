import '../../core/utils/parse_utils.dart';

class RoomModel {
  final int? id;
  final int? buildingId;
  final String roomname;
  final String? floor;
  final String? shortName;
  final String? type;
  final String? accessLevel;
  final String? openingHours;
  final String? contact;
  final List<String> services;
  final List<String> paymentMethods;
  final String? description;
  final List<String> imageUrl;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const RoomModel({
    this.id,
    this.buildingId,
    required this.roomname,
    this.floor,
    this.shortName,
    this.type,
    this.accessLevel,
    this.openingHours,
    this.contact,
    this.services = const [],
    this.paymentMethods = const [],
    this.description,
    this.imageUrl = const [],
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    return RoomModel(
      id: parseInt(json['id']),
      buildingId: parseInt(json['building_id']),
      roomname: json['roomname']?.toString() ?? '',
      floor: json['floor']?.toString(),
      shortName: json['short_name']?.toString(),
      type: json['type']?.toString(),
      accessLevel: json['access_level']?.toString(),
      openingHours: json['opening_hours']?.toString(),
      contact: json['contact']?.toString(),
      services: parseStringList(json['services']),
      paymentMethods: parseStringList(json['payment_methods']),
      description: json['description']?.toString(),
      imageUrl: parseStringList(json['image_url']),
      isActive: parseBool(json['is_active'], fallback: true),
      createdAt: parseDate(json['created_at']),
      updatedAt: parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'building_id': buildingId,
      'roomname': roomname,
      'floor': floor,
      'short_name': shortName,
      'type': type,
      'access_level': accessLevel,
      'opening_hours': openingHours,
      'contact': contact,
      'services': services,
      'payment_methods': paymentMethods,
      'description': description,
      'image_url': imageUrl,
      'is_active': isActive,
    };
  }

  RoomModel copyWith({
    int? id,
    int? buildingId,
    String? roomname,
    String? floor,
    String? shortName,
    String? type,
    String? accessLevel,
    String? openingHours,
    String? contact,
    List<String>? services,
    List<String>? paymentMethods,
    String? description,
    List<String>? imageUrl,
    bool? isActive,
  }) {
    return RoomModel(
      id: id ?? this.id,
      buildingId: buildingId ?? this.buildingId,
      roomname: roomname ?? this.roomname,
      floor: floor ?? this.floor,
      shortName: shortName ?? this.shortName,
      type: type ?? this.type,
      accessLevel: accessLevel ?? this.accessLevel,
      openingHours: openingHours ?? this.openingHours,
      contact: contact ?? this.contact,
      services: services ?? this.services,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
