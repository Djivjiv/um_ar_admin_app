import '../../core/utils/parse_utils.dart';

class NavigationSessionModel {
  final String id;
  final String? userId;
  final String? visitorSessionId;
  final String? fromNode;
  final String? toNode;
  final String? fromName;
  final String? toName;
  final double? distanceMeters;
  final int? durationSeconds;
  final bool completed;
  final DateTime? startedAt;
  final DateTime? completedAt;

  const NavigationSessionModel({
    required this.id,
    this.userId,
    this.visitorSessionId,
    this.fromNode,
    this.toNode,
    this.fromName,
    this.toName,
    this.distanceMeters,
    this.durationSeconds,
    this.completed = false,
    this.startedAt,
    this.completedAt,
  });

  factory NavigationSessionModel.fromJson(Map<String, dynamic> json) {
    return NavigationSessionModel(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString(),
      visitorSessionId: json['visitor_session_id']?.toString(),
      fromNode: json['from_node']?.toString(),
      toNode: json['to_node']?.toString(),
      fromName: json['from_name']?.toString(),
      toName: json['to_name']?.toString(),
      distanceMeters: parseDouble(json['distance_meters']),
      durationSeconds: parseInt(json['duration_seconds']),
      completed: parseBool(json['completed']),
      startedAt: parseDate(json['started_at']),
      completedAt: parseDate(json['completed_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'visitor_session_id': visitorSessionId,
      'from_node': fromNode,
      'to_node': toNode,
      'from_name': fromName,
      'to_name': toName,
      'distance_meters': distanceMeters,
      'duration_seconds': durationSeconds,
      'completed': completed,
      'started_at': startedAt?.toUtc().toIso8601String(),
      'completed_at': completedAt?.toUtc().toIso8601String(),
    };
  }
}
