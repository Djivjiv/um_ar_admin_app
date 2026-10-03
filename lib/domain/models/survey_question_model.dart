import '../../core/utils/parse_utils.dart';

class SurveyQuestionModel {
  final String? id;
  final int questionNumber;
  final String questionText;
  final int scale;
  final bool isActive;
  final DateTime? updatedAt;

  const SurveyQuestionModel({
    this.id,
    required this.questionNumber,
    required this.questionText,
    this.scale = 5,
    this.isActive = true,
    this.updatedAt,
  });

  factory SurveyQuestionModel.fromJson(Map<String, dynamic> json) {
    return SurveyQuestionModel(
      id: json['id']?.toString(),
      questionNumber: parseInt(json['question_number']) ?? 0,
      questionText: json['question_text']?.toString() ?? '',
      scale: parseInt(json['scale']) ?? 5,
      isActive: parseBool(json['is_active'], fallback: true),
      updatedAt: parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'question_number': questionNumber,
      'question_text': questionText,
      'scale': scale,
      'is_active': isActive,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  SurveyQuestionModel copyWith({String? questionText, int? scale, bool? isActive}) {
    return SurveyQuestionModel(
      id: id,
      questionNumber: questionNumber,
      questionText: questionText ?? this.questionText,
      scale: scale ?? this.scale,
      isActive: isActive ?? this.isActive,
      updatedAt: updatedAt,
    );
  }
}
