import '../../core/utils/parse_utils.dart';

/// Maps to the `facility_content` table.
class FacilityContentModel {
  final String? id;
  final int? buildingId;
  final int? roomId;
  final String title;
  final String? content;
  final String? type;
  final String? icon;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FacilityContentModel({
    this.id,
    this.buildingId,
    this.roomId,
    required this.title,
    this.content,
    this.type,
    this.icon,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory FacilityContentModel.fromJson(Map<String, dynamic> json) {
    return FacilityContentModel(
      id: json['id']?.toString(),
      buildingId: parseInt(json['building_id']),
      roomId: parseInt(json['room_id']),
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString(),
      type: json['type']?.toString(),
      icon: json['icon']?.toString(),
      isActive: parseBool(json['is_active'], fallback: true),
      createdAt: parseDate(json['created_at']),
      updatedAt: parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'building_id': buildingId,
      'room_id': roomId,
      'title': title,
      'content': content,
      'type': type,
      'icon': icon,
      'is_active': isActive,
    };
  }

  FacilityContentModel copyWith({
    String? id,
    int? buildingId,
    int? roomId,
    String? title,
    String? content,
    String? type,
    String? icon,
    bool? isActive,
  }) {
    return FacilityContentModel(
      id: id ?? this.id,
      buildingId: buildingId ?? this.buildingId,
      roomId: roomId ?? this.roomId,
      title: title ?? this.title,
      content: content ?? this.content,
      type: type ?? this.type,
      icon: icon ?? this.icon,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
