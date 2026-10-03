import '../../core/utils/parse_utils.dart';

class VisitorSessionModel {
  final String id;
  final String? deviceId;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final bool isExpired;

  const VisitorSessionModel({
    required this.id,
    this.deviceId,
    this.startedAt,
    this.expiresAt,
    this.isExpired = false,
  });

  bool get isActive {
    if (isExpired) return false;
    if (expiresAt == null) return true;
    return expiresAt!.isAfter(DateTime.now());
  }

  factory VisitorSessionModel.fromJson(Map<String, dynamic> json) {
    return VisitorSessionModel(
      id: json['id']?.toString() ?? '',
      deviceId: json['device_id']?.toString(),
      startedAt: parseDate(json['started_at']),
      expiresAt: parseDate(json['expires_at']),
      isExpired: parseBool(json['is_expired']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'device_id': deviceId,
      'started_at': startedAt?.toUtc().toIso8601String(),
      'expires_at': expiresAt?.toUtc().toIso8601String(),
      'is_expired': isExpired,
    };
  }
}
