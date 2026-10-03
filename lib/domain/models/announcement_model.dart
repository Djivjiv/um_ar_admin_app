import '../../core/utils/parse_utils.dart';

class AnnouncementModel {
  final String? id;
  final String title;
  final String? body;
  final String? type;
  final bool isActive;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AnnouncementModel({
    this.id,
    required this.title,
    this.body,
    this.type,
    this.isActive = true,
    this.expiresAt,
    this.createdAt,
    this.updatedAt,
  });

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  bool get isEmergency => (type ?? '').toLowerCase() == 'emergency';

  factory AnnouncementModel.fromJson(Map<String, dynamic> json) {
    return AnnouncementModel(
      id: json['id']?.toString(),
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString(),
      type: json['type']?.toString(),
      isActive: parseBool(json['is_active'], fallback: true),
      expiresAt: parseDate(json['expires_at']),
      createdAt: parseDate(json['created_at']),
      updatedAt: parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'body': body,
      'type': type,
      'is_active': isActive,
      'expires_at': expiresAt?.toUtc().toIso8601String(),
    };
  }

  AnnouncementModel copyWith({
    String? id,
    String? title,
    String? body,
    String? type,
    bool? isActive,
    DateTime? expiresAt,
  }) {
    return AnnouncementModel(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      isActive: isActive ?? this.isActive,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
