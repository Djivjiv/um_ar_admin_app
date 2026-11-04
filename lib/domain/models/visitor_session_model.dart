import '../../core/utils/parse_utils.dart';

class VisitorSessionModel {
  final String id;

  /// The install's random code, shared with the other evaluation tables.
  final String? deviceCode;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final bool isExpired;

  const VisitorSessionModel({
    required this.id,
    this.deviceCode,
    this.startedAt,
    this.expiresAt,
    this.isExpired = false,
  });

  /// Active means not marked expired and not past `expires_at`. The server
  /// only sets `is_expired` when that device checks in, so a session left to
  /// run out stays false. `applyActiveVisitorFilter` is the same rule as a
  /// query: change both together.
  bool isActiveAt(DateTime now) =>
      !isExpired && expiresAt != null && expiresAt!.isAfter(now);

  bool get isActive => isActiveAt(DateTime.now());

  factory VisitorSessionModel.fromJson(Map<String, dynamic> json) {
    String? text(String column) {
      final value = json[column]?.toString().trim() ?? '';
      return value.isEmpty ? null : value;
    }

    return VisitorSessionModel(
      id: json['id']?.toString() ?? '',
      // Rows from before device_code existed only have device_id.
      deviceCode: text('device_code') ?? text('device_id'),
      startedAt: parseDate(json['started_at']),
      expiresAt: parseDate(json['expires_at']),
      isExpired: parseBool(json['is_expired']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'device_code': deviceCode,
      'started_at': startedAt?.toUtc().toIso8601String(),
      'expires_at': expiresAt?.toUtc().toIso8601String(),
      'is_expired': isExpired,
    };
  }
}
