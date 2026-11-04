import '../../core/config/supabase_config.dart';
import '../../core/utils/floor_scale.dart';
import '../../domain/models/floor_distance_model.dart';
import '../../domain/models/floor_plan_model.dart';
import 'floor_plan_repository.dart';
import 'paged_query.dart';
import 'repository_exception.dart';

const kFloorDistancesMissingMessage =
    'The floor_plan_distances table does not exist yet. Run '
    'db/floor_plan_distances.sql in the Supabase SQL editor, after '
    'db/user_roles.sql.';

/// Thrown instead of a plain failure while db/floor_plan_distances.sql hasn't
/// been run, so screens can keep working without measurements.
class FloorDistancesMissing extends RepositoryException {
  FloorDistancesMissing([Object? cause])
      : super(kFloorDistancesMissingMessage, cause);
}

class FloorDistanceRepository {
  final _client = SupabaseConfig.client;
  final _plans = FloorPlanRepository();
  static const _table = 'floor_plan_distances';

  /// [e] as the exception to throw for a failed [what].
  RepositoryException _failure(String what, Object e) {
    if (e is RepositoryException) return e;
    if (isMissingTable(e)) return FloorDistancesMissing(e);
    return RepositoryException('Failed to $what: ${describeError(e)}', e);
  }

  /// Oldest first.
  Future<List<FloorDistanceModel>> getForFloor(int floorPlanId) async {
    try {
      final rows = await fetchAllPages((a, b) => _client
          .from(_table)
          .select()
          .eq('floor_plan_id', floorPlanId)
          .order('created_at', ascending: true)
          .order('id', ascending: true)
          .range(a, b));
      return rows.map(FloorDistanceModel.fromJson).toList();
    } catch (e) {
      throw _failure('load distances', e);
    }
  }

  Future<void> add({
    required int floorPlanId,
    required String nodeAId,
    required String nodeBId,
    required double realMeters,
  }) async {
    try {
      await _client.from(_table).insert({
        'floor_plan_id': floorPlanId,
        'node_a_id': nodeAId,
        'node_b_id': nodeBId,
        'real_meters': realMeters,
      });
    } catch (e) {
      throw _failure('save the distance', e);
    }
  }

  Future<void> _update(
    String id,
    Map<String, Object> values,
    String what,
  ) async {
    try {
      final rows = await _client
          .from(_table)
          .update(values)
          .eq('id', id)
          .select('id');
      requireAffected(rows, 'Saving the distance');
    } catch (e) {
      throw _failure(what, e);
    }
  }

  Future<void> setMeters(String id, double realMeters) =>
      _update(id, {'real_meters': realMeters}, 'save the distance');

  Future<void> setIgnored(String id, bool ignored) =>
      _update(id, {'ignored': ignored}, 'update the distance');

  Future<void> delete(String id) async {
    try {
      final rows =
          await _client.from(_table).delete().eq('id', id).select('id');
      requireAffected(rows, 'Deleting the distance');
    } catch (e) {
      throw _failure('delete the distance', e);
    }
  }

  /// Saves and confirms [summary]'s scale on [plan], returning the floor as
  /// the database now holds it. With nothing counted, or nothing changed, the
  /// floor is left alone.
  Future<FloorPlanModel> applyScale(
    FloorPlanModel plan,
    FloorScaleSummary summary,
  ) async {
    final scale = summary.metersPerPixel;
    if (scale == null || scale == plan.metersPerPixel) return plan;
    return _plans.saveScale(plan.id!, scale);
  }
}
