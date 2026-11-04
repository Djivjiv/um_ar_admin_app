import '../../core/utils/navigation_metrics.dart' show isVisitorRow;
import '../../core/utils/parse_utils.dart';

class SusResponseModel {
  final String id;
  final String? userId;
  final String? visitorSessionId;
  final List<int?> answers; // q1..q10, index 0 = q1
  final double? susScore;

  /// The role the user app recorded, e.g. student or visitor.
  final String? userType;
  final DateTime? submittedAt;

  /// The raw install code. Only ever exported as `anonymousDeviceId`.
  final String? deviceCode;

  /// The trip this answer followed: `navigation_sessions.trip_id`.
  final String? navigationSessionId;
  final bool isVisitor;

  const SusResponseModel({
    required this.id,
    this.userId,
    this.visitorSessionId,
    this.answers = const [],
    this.susScore,
    this.userType,
    this.submittedAt,
    this.deviceCode,
    this.navigationSessionId,
    this.isVisitor = false,
  });

  int? answerFor(int question) {
    final idx = question - 1;
    if (idx < 0 || idx >= answers.length) return null;
    return answers[idx];
  }

  factory SusResponseModel.fromJson(Map<String, dynamic> json) {
    return SusResponseModel(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString(),
      visitorSessionId: json['visitor_session_id']?.toString(),
      answers: List<int?>.generate(10, (i) => parseInt(json['q${i + 1}'])),
      susScore: parseDouble(json['sus_score']),
      userType: json['user_type']?.toString(),
      submittedAt: parseDate(json['submitted_at']),
      deviceCode: json['device_code']?.toString(),
      navigationSessionId: json['navigation_session_id']?.toString(),
      isVisitor: isVisitorRow(json),
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'user_id': userId,
      'visitor_session_id': visitorSessionId,
      'sus_score': susScore,
      'user_type': userType,
      'device_code': deviceCode,
      'navigation_session_id': navigationSessionId,
    };
    for (var i = 0; i < answers.length && i < 10; i++) {
      map['q${i + 1}'] = answers[i];
    }
    return map;
  }
}
