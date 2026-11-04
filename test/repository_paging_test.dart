import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/core/utils/ar_network_check.dart';
import 'package:um_ar_admin/data/repositories/building_repository.dart';
import 'package:um_ar_admin/data/repositories/content_repository.dart';
import 'package:um_ar_admin/data/repositories/facility_repository.dart';
import 'package:um_ar_admin/data/repositories/floor_plan_repository.dart';
import 'package:um_ar_admin/data/repositories/kiosk_repository.dart';
import 'package:um_ar_admin/data/repositories/node_repository.dart';
import 'package:um_ar_admin/data/repositories/outdoor_ar_repository.dart';
import 'package:um_ar_admin/data/repositories/room_repository.dart';
import 'package:um_ar_admin/data/repositories/survey_question_repository.dart';
import 'package:um_ar_admin/data/repositories/sus_repository.dart';
import 'package:um_ar_admin/data/repositories/user_repository.dart';
import 'package:um_ar_admin/data/repositories/visitor_session_repository.dart';

import 'support/fake_postgrest.dart';

/// More rows than one Supabase response can hold, spanning three pages.
const _total = 2500;

List<Map<String, dynamic>> _rows(Map<String, dynamic> Function(int i) row) => [
      for (var i = 1; i <= _total; i++) {'id': i, ...row(i)},
    ];

void main() {
  late FakePostgrest db;

  setUp(() {
    db = FakePostgrest()..install();
  });
  tearDown(FakePostgrest.uninstall);

  /// Checks every fake row arrived exactly once, in three requests.
  Future<void> expectAllRows(
    String table,
    Future<List<Object?>> Function() load, {
    Map<String, dynamic> Function(int i)? row,
  }) async {
    db.tables[table] = _rows(row ?? (_) => const {});
    final ids = await load();
    expect(ids, hasLength(_total), reason: '$table lost rows');
    expect(ids.toSet(), hasLength(_total), reason: '$table repeated rows');
    expect(db.requestCount('GET $table'), 3);
  }

  test('the fake really caps an unpaged select at 1000 rows', () async {
    db.tables['buildings'] = _rows((i) => {'name': 'B$i'});
    final rows = await db.client.from('buildings').select();
    expect(rows, hasLength(1000));
  });

  test('buildings', () {
    return expectAllRows(
      'buildings',
      () async => [
        for (final b in await BuildingRepository().getAll()) b.id,
      ],
      row: (i) => {'name': 'Building $i'},
    );
  });

  test('rooms', () {
    return expectAllRows(
      'rooms',
      () async => [for (final r in await RoomRepository().getAll()) r.id],
      row: (i) => {'roomname': 'Room $i', 'building_id': 1},
    );
  });

  test('rooms of one building', () {
    return expectAllRows(
      'rooms',
      () async => [
        for (final r in await RoomRepository().getByBuilding(1)) r.id,
      ],
      row: (i) => {'roomname': 'Room $i', 'building_id': 1},
    );
  });

  test('facilities', () {
    return expectAllRows(
      'facilities',
      () async => [
        for (final f in await FacilityRepository().getAll()) f.id,
      ],
      row: (i) => {'roomname': 'Facility $i', 'building_id': 1},
    );
  });

  test('facilities of one building', () {
    return expectAllRows(
      'facilities',
      () async => [
        for (final f in await FacilityRepository().getByBuilding(1)) f.id,
      ],
      row: (i) => {'roomname': 'Facility $i', 'building_id': 1},
    );
  });

  test('floor plans', () {
    return expectAllRows(
      'building_floors',
      () async => [
        for (final p in await FloorPlanRepository().getAll()) p.id,
      ],
      row: (i) => {'building_id': 1, 'floor_number': i},
    );
  });

  test('floor plans of one building', () {
    return expectAllRows(
      'building_floors',
      () async => [
        for (final p in await FloorPlanRepository().getByBuilding(1)) p.id,
      ],
      row: (i) => {'building_id': 1, 'floor_number': i},
    );
  });

  test('indoor nodes of a floor', () {
    return expectAllRows(
      'indoor_nodes',
      () async => [
        for (final n in await FloorPlanRepository().getIndoorNodes(1)) n.id,
      ],
      row: (i) => {'floor_plan_id': 1},
    );
  });

  test('indoor nodes of a building', () {
    return expectAllRows(
      'indoor_nodes',
      () async => [
        for (final n
            in await FloorPlanRepository().getIndoorNodesForBuilding(1))
          n.id,
      ],
      row: (i) => {'building_id': 1},
    );
  });

  test('indoor edges of a floor', () {
    return expectAllRows(
      'indoor_edges',
      () async => [
        for (final e in await FloorPlanRepository().getIndoorEdges(1)) e.id,
      ],
      row: (i) => {'floor_plan_id': 1, 'from_node': 'a', 'to_node': 'b'},
    );
  });

  test('cross-building nodes', () {
    return expectAllRows(
      'indoor_nodes',
      () async => [
        for (final n in await FloorPlanRepository().getCrossBuildingNodes())
          n.id,
      ],
      row: (i) => {'cross_building_ref': 'REF_$i'},
    );
  });

  test('cross-building partners', () {
    return expectAllRows(
      'indoor_nodes',
      () async => [
        for (final n
            in await FloorPlanRepository().findCrossBuildingPartners('REF'))
          n.id,
      ],
      row: (i) => {'cross_building_ref': 'REF'},
    );
  });

  test('graph stats count every node and edge', () async {
    db.tables['indoor_nodes'] = _rows((i) => {
          'floor_plan_id': 1,
          'is_navigable': true,
        });
    db.tables['indoor_edges'] = _rows((i) => {
          'floor_plan_id': 1,
          'from_node': '$i',
          'to_node': '${i + 1}',
        });
    final stats = await FloorPlanRepository().getGraphStats();
    expect(stats[1]!.nodeCount, _total);
    expect(stats[1]!.edgeCount, _total);
  });

  test('campus outdoor nodes', () {
    return expectAllRows(
      'outdoor_nodes',
      () async => [
        for (final n in await NodeRepository().getAllNodes()) n.id,
      ],
    );
  });

  test('campus outdoor edges', () {
    return expectAllRows(
      'outdoor_edges',
      () async => [
        for (final e in await NodeRepository().getAllEdges()) e.id,
      ],
      row: (i) => {'from_node': 'a', 'to_node': 'b'},
    );
  });

  test('outdoor entrance nodes', () {
    return expectAllRows(
      'outdoor_nodes',
      () async => [
        for (final n
            in await NodeRepository().getEntranceNodesForBuilding(1))
          n.id,
      ],
      row: (i) => {'building_id': 1, 'is_entrance': true},
    );
  });

  test('outdoor AR nodes', () {
    return expectAllRows(
      'outdoor_ar_nodes',
      () async => [
        for (final n in await OutdoorArRepository().getNodes()) n.id,
      ],
      row: (i) => {'lat': 7.0, 'lng': 125.0, 'created_at': '2026-01-01'},
    );
  });

  test('outdoor AR edges', () {
    return expectAllRows(
      'outdoor_ar_edges',
      () async => [
        for (final e in await OutdoorArRepository().getEdges()) e.id,
      ],
      row: (i) => {'from_node': 'a', 'to_node': 'b'},
    );
  });

  test('SUS survey responses', () {
    return expectAllRows(
      'sus_responses',
      () async => [for (final r in await SusRepository().getAll()) r.id],
      row: (i) => {'submitted_at': '2026-01-01'},
    );
  });

  test('survey questions', () {
    return expectAllRows(
      'survey_questions',
      () async => [
        for (final q in await SurveyQuestionRepository().getAll()) q.id,
      ],
      row: (i) => {'question_number': i, 'question_text': 'Q$i'},
    );
  });

  test('kiosk feedback responses are all summarised', () async {
    db.tables['kiosk_survey_responses'] = _rows((i) => {
          'created_at': '2026-01-01T00:00:00Z',
          'overall_rating': 5,
        });
    final summary = await KioskRepository().getSurveySummary(
      from: DateTime.utc(2025),
      to: DateTime.utc(2027),
    );
    expect(summary.responseCount, _total);
    expect(db.requestCount('GET kiosk_survey_responses'), 3);
  });

  test('kiosk sessions', () {
    return expectAllRows(
      'kiosk_sessions',
      () async => [
        for (final s in await KioskRepository().getSessions()) s.id,
      ],
      row: (i) => {'started_at': '2026-01-01T00:00:00Z'},
    );
  });

  test('users', () {
    return expectAllRows(
      'user_profiles',
      () async => [for (final u in await UserRepository().getAll()) u.id],
      row: (i) => {'created_at': '2026-01-01'},
    );
  });

  test('visitor sessions', () {
    return expectAllRows(
      'visitor_sessions',
      () async => [
        for (final v in await VisitorSessionRepository().getAll()) v.id,
      ],
      row: (i) => {'started_at': '2026-01-01'},
    );
  });

  test('context content', () {
    return expectAllRows(
      'facility_content',
      () async => [for (final c in await ContentRepository().getAll()) c.id],
      row: (i) => {'title': 'C$i'},
    );
  });

  test('the AR network check sees past the first 1000 rows', () async {
    // A chain of 2500 nodes: cut at 1000 rows, it would look like a smaller
    // network with its far end missing.
    db.tables['outdoor_ar_nodes'] = _rows((i) => {
          'lat': 7.0,
          'lng': 125.0,
          'created_at': '2026-01-01',
          'building_id': i == _total ? 99 : null,
        });
    db.tables['outdoor_ar_edges'] = [
      for (var i = 1; i < _total; i++)
        {'id': i, 'from_node': '$i', 'to_node': '${i + 1}'},
    ];
    final repo = OutdoorArRepository();
    final report = checkArNetwork(
      nodes: await repo.getNodes(),
      edges: await repo.getEdges(),
      buildingIds: [99],
    );
    expect(report.components, hasLength(1));
    expect(report.components.single, hasLength(_total));
    expect(report.buildingsWithoutNode, isEmpty);
  });
}
