import '../../core/utils/parse_utils.dart';

/// Maps to `kiosk_sessions`, written by the kiosk tablet app.
class KioskSessionModel {
  final String id;
  final DateTime? startedAt;

  /// Null while the session is running, or when the kiosk app never set it
  /// (the column is added by db/kiosk_management.sql).
  final DateTime? endedAt;
  final int searchesCount;
  final int routesCalculated;
  final int destinationsViewed;
  final bool feedbackGiven;

  const KioskSessionModel({
    required this.id,
    this.startedAt,
    this.endedAt,
    this.searchesCount = 0,
    this.routesCalculated = 0,
    this.destinationsViewed = 0,
    this.feedbackGiven = false,
  });

  bool get isActive => endedAt == null;

  /// Null until the session has ended — a running session has no duration yet.
  Duration? get duration {
    if (startedAt == null || endedAt == null) return null;
    final d = endedAt!.difference(startedAt!);
    return d.isNegative ? null : d;
  }

  factory KioskSessionModel.fromJson(Map<String, dynamic> json) {
    return KioskSessionModel(
      id: json['id']?.toString() ?? '',
      startedAt: parseDate(json['started_at']),
      endedAt: parseDate(json['ended_at']),
      searchesCount: parseInt(json['searches_count']) ?? 0,
      routesCalculated: parseInt(json['routes_calculated']) ?? 0,
      destinationsViewed: parseInt(json['destinations_viewed']) ?? 0,
      feedbackGiven: parseBool(json['feedback_given']),
    );
  }
}
