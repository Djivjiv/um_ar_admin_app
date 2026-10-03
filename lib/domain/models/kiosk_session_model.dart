import '../../core/utils/parse_utils.dart';

class KioskSessionModel {
  final String id;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int navigationCount;

  const KioskSessionModel({
    required this.id,
    this.startedAt,
    this.endedAt,
    this.navigationCount = 0,
  });

  bool get isActive => endedAt == null;

  Duration? get duration {
    if (startedAt == null) return null;
    return (endedAt ?? DateTime.now()).difference(startedAt!);
  }

  factory KioskSessionModel.fromJson(Map<String, dynamic> json) {
    return KioskSessionModel(
      id: json['id']?.toString() ?? '',
      startedAt: parseDate(json['started_at'] ??
          json['created_at'] ??
          json['session_start']),
      endedAt: parseDate(json['ended_at'] ??
          json['completed_at'] ??
          json['expired_at']),
      navigationCount: parseInt(json['navigation_count'] ??
              json['navigations'] ??
              json['nav_count']) ??
          0,
    );
  }
}
