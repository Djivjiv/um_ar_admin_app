import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/facility_model.dart';
import '../../domain/models/indoor_node_model.dart';
import '../../domain/models/room_model.dart';
import 'paged_query.dart';
import 'repository_exception.dart';

/// The table an `indoor_nodes.linked_room_id` points at, per `linked_table`.
enum LinkedTable { rooms, facilities }

/// PostgREST `or` filter matching nodes whose `linked_table` refers to
/// [table]. A null `linked_table` means rooms (the column was added later,
/// see db/indoor_nodes_infonodes.sql), so rooms also match null.
String linkedTableFilter(LinkedTable table) => switch (table) {
      LinkedTable.rooms => 'linked_table.eq.rooms,linked_table.is.null',
      LinkedTable.facilities => 'linked_table.eq.facilities',
    };

/// Indoor nodes (`id`, `linked_room_id`) pointing at [ids] of [table].
Future<List<Map<String, dynamic>>> linkedIndoorNodes(
  SupabaseClient client, {
  required LinkedTable table,
  required List<int> ids,
}) async {
  if (ids.isEmpty) return const [];
  return fetchAllPages((a, b) => client
      .from('indoor_nodes')
      .select('id, linked_room_id')
      .inFilter('linked_room_id', ids)
      .or(linkedTableFilter(table))
      .order('id')
      .range(a, b));
}

/// Unlinks every indoor node pointing at [ids] of [table], then runs [then].
/// `linked_room_id` has no foreign key, so without this the nodes would keep
/// pointing at a row that is gone or inactive.
///
/// Supabase has no client-side transactions: if [then] fails the links are
/// put back so nothing changes, and its error is rethrown. If the unlink is
/// blocked or partial (Row Level Security matches no rows without an error),
/// [then] never runs.
Future<T> unlinkIndoorNodesThen<T>(
  SupabaseClient client, {
  required LinkedTable table,
  required List<int> ids,
  required Future<T> Function() then,
}) async {
  final List<Map<String, dynamic>> linked;
  try {
    linked = await linkedIndoorNodes(client, table: table, ids: ids);
  } on PostgrestException catch (e) {
    throw RepositoryException(
        'Nothing was changed: could not check which indoor nodes point at '
        'it (${e.message}).',
        e);
  }
  if (linked.isEmpty) return then();

  final nodeIds = [for (final r in linked) r['id'].toString()];
  final List<Map<String, dynamic>> unlinked;
  try {
    unlinked = await client
        .from('indoor_nodes')
        .update({'linked_room_id': null, 'linked_table': null})
        .inFilter('id', nodeIds)
        .select('id');
  } on PostgrestException catch (e) {
    throw RepositoryException(
        'Nothing was changed: could not unlink the indoor nodes that point '
        'at it (${e.message}).',
        e);
  }
  if (unlinked.length < nodeIds.length) {
    await _restoreLinks(client, table, linked);
    throw RepositoryException(
        'Nothing was changed: only ${unlinked.length} of ${nodeIds.length} '
        'indoor nodes could be unlinked. Row Level Security may be blocking '
        'updates to indoor_nodes for this account.');
  }

  try {
    return await then();
  } catch (_) {
    await _restoreLinks(client, table, linked);
    rethrow;
  }
}

/// Puts back the links in [linked], as read before they were cleared.
Future<void> _restoreLinks(
  SupabaseClient client,
  LinkedTable table,
  List<Map<String, dynamic>> linked,
) async {
  final byTarget = <Object?, List<String>>{};
  for (final r in linked) {
    (byTarget[r['linked_room_id']] ??= []).add(r['id'].toString());
  }
  try {
    for (final entry in byTarget.entries) {
      await client
          .from('indoor_nodes')
          .update({'linked_room_id': entry.key, 'linked_table': table.name})
          .inFilter('id', entry.value);
    }
  } catch (e) {
    final ids = [for (final r in linked) r['id'].toString()];
    throw RepositoryException(
        'The action failed, and indoor node links could not be restored: '
        '${ids.join(', ')}. Re-link them in the floor plan editor.',
        e);
  }
}

/// Nodes in [nodes] linked to a row that is not in [rooms] / [facilities].
/// Those lists hold the active rows, so a match is a link to something
/// deleted or inactive: routes would dead-end at it.
List<IndoorNodeModel> danglingLinkedNodes(
  Iterable<IndoorNodeModel> nodes,
  Iterable<RoomModel> rooms,
  Iterable<FacilityModel> facilities,
) {
  final roomIds = {for (final r in rooms) r.id?.toString()};
  final facilityIds = {for (final f in facilities) f.id?.toString()};
  return [
    for (final n in nodes)
      if ((n.linkedRoomId ?? '').isNotEmpty &&
          !(n.linkedTable == 'facilities' ? facilityIds : roomIds)
              .contains(n.linkedRoomId))
        n,
  ];
}
