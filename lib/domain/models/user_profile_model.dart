import '../../core/utils/parse_utils.dart';

class UserProfileModel {
  final String id;
  final String? email;
  final String? fullName;
  final String? role;
  final bool isVerified;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? lastSeen;

  const UserProfileModel({
    required this.id,
    this.email,
    this.fullName,
    this.role,
    this.isVerified = false,
    this.isActive = true,
    this.createdAt,
    this.lastSeen,
  });

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    return UserProfileModel(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString(),
      fullName: json['full_name']?.toString(),
      role: json['role']?.toString(),
      isVerified: parseBool(json['is_verified']),
      isActive: parseBool(json['is_active'], fallback: true),
      createdAt: parseDate(json['created_at']),
      lastSeen: parseDate(json['last_seen']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'role': role,
      'is_verified': isVerified,
      'is_active': isActive,
    };
  }
}
