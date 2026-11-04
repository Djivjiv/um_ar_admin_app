import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../domain/models/survey_question_model.dart';
import 'paged_query.dart';
import 'repository_exception.dart';

class SurveyQuestionRepository {
  final _client = SupabaseConfig.client;
  static const _table = 'survey_questions';

  /// Loads the SUS survey questions. The 10 standard statements now live in
  /// the `survey_questions` table itself (see
  /// db/survey_questions_and_foodcourt_cleanup.sql) — nothing is seeded or
  /// faked locally, so an empty/missing table surfaces as a real error.
  Future<List<SurveyQuestionModel>> getAll() async {
    try {
      final rows = await fetchAllPages((a, b) => _client
          .from(_table)
          .select()
          .order('question_number', ascending: true)
          .order('id')
          .range(a, b));
      return rows.map(SurveyQuestionModel.fromJson).toList();
    } on PostgrestException catch (e) {
      throw RepositoryException(
          'Failed to load survey questions: ${e.message}', e);
    } catch (e) {
      throw RepositoryException('Failed to load survey questions', e);
    }
  }

  Future<SurveyQuestionModel> update(SurveyQuestionModel question) async {
    if (question.id == null) {
      throw RepositoryException(
        'Cannot save — run the survey_questions table SQL first so questions '
        'have real ids.',
      );
    }
    try {
      final rows = await _client
          .from(_table)
          .update({
            'question_text': question.questionText,
            'scale': question.scale,
            'is_active': question.isActive,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', question.id!)
          .select();
      final list = rows as List;
      if (list.isEmpty) {
        throw RepositoryException(
            'Update affected 0 rows (row missing or blocked by RLS).');
      }
      return SurveyQuestionModel.fromJson(list.first as Map<String, dynamic>);
    } on RepositoryException {
      rethrow;
    } on PostgrestException catch (e) {
      throw RepositoryException(
          'Failed to save question: ${e.message}', e);
    } catch (e) {
      throw RepositoryException('Failed to save question: $e', e);
    }
  }
}
