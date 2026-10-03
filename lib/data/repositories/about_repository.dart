import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../domain/models/about_um_model.dart';
import 'repository_exception.dart';

class AboutRepository {
  final _client = SupabaseConfig.client;
  static const _table = 'about_um';

  /// Turns a Supabase/Postgrest error into a human-readable message.
  String _describe(Object e) {
    if (e is PostgrestException) return e.message;
    return e.toString();
  }

  Future<AboutUmModel?> get() async {
    try {
      final rows = await _client.from(_table).select().limit(1);
      final list = rows as List;
      if (list.isEmpty) return null;
      return AboutUmModel.fromJson(list.first as Map<String, dynamic>);
    } catch (e) {
      throw RepositoryException(
          'Failed to load About UM info: ${_describe(e)}', e);
    }
  }

  /// `about_um` is a singleton row (there should only ever be one). Rather
  /// than relying on `.upsert()` — which needs a conflict target that may
  /// not exist yet on the very first save — explicitly check whether a row
  /// is already there and UPDATE it, or INSERT a new one otherwise.
  Future<AboutUmModel> upsert(AboutUmModel about) async {
    try {
      final payload = about.toJson()..remove('id');

      var existingId = about.id;
      if (existingId == null) {
        final existing =
            await _client.from(_table).select('id').maybeSingle();
        existingId = existing?['id']?.toString();
      }

      final Map<String, dynamic> row;
      if (existingId != null) {
        final rows = await _client
            .from(_table)
            .update(payload)
            .eq('id', existingId)
            .select();
        final list = rows as List;
        row = list.isEmpty
            // The row may have been deleted between the check and the
            // update — fall back to inserting a fresh one.
            ? await _client.from(_table).insert(payload).select().single()
            : list.first as Map<String, dynamic>;
      } else {
        row = await _client.from(_table).insert(payload).select().single();
      }

      return AboutUmModel.fromJson(row);
    } catch (e) {
      throw RepositoryException(
          'Failed to save About UM info: ${_describe(e)}', e);
    }
  }
}
