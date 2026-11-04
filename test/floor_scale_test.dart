import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/core/utils/floor_scale.dart';
import 'package:um_ar_admin/data/repositories/floor_distance_repository.dart';
import 'package:um_ar_admin/data/repositories/floor_plan_repository.dart';
import 'package:um_ar_admin/data/repositories/repository_exception.dart';
import 'package:um_ar_admin/domain/models/floor_distance_model.dart';
import 'package:um_ar_admin/domain/models/floor_plan_model.dart';
import 'package:um_ar_admin/domain/models/indoor_edge_model.dart';
import 'package:um_ar_admin/domain/models/indoor_node_model.dart';
import 'package:um_ar_admin/presentation/screens/floor_plans/floor_distance_panel.dart';
import 'package:um_ar_admin/presentation/screens/floor_plans/floor_plan_editor_screen.dart';

import 'support/fake_postgrest.dart';

IndoorNodeModel node(String id, double x, double y, {String? name}) =>
    IndoorNodeModel(id: id, x: x, y: y, name: name);

/// a to b is 100 px, a to c 300 px, a to d 500 px. None are joined by an edge.
final nodes = [
  node('a', 0, 0),
  node('b', 100, 0),
  node('c', 300, 0),
  node('d', 500, 0),
];

var _nextId = 1;

FloorDistanceModel measure(
  String a,
  String b,
  double meters, {
  bool ignored = false,
}) =>
    FloorDistanceModel(
      id: 'm${_nextId++}',
      floorPlanId: 1,
      nodeAId: a,
      nodeBId: b,
      realMeters: meters,
      ignored: ignored,
    );

FloorPlanModel plan(double? scale) =>
    FloorPlanModel.fromJson({'id': 1, 'meters_per_pixel': scale});

void main() {
  group('the scale', () {
    test('is total meters over total pixels, not an average of pairs', () {
      final s = computeFloorScale(
        [measure('a', 'b', 5), measure('a', 'c', 18)],
        nodes,
      );
      // 23 m / 400 px. A plain average of 0.05 and 0.06 would give 0.055.
      expect(s.metersPerPixel, 0.0575);
      expect(s.counted, 2);
    });

    test('the two nodes need no edge, and can repeat', () {
      final s = computeFloorScale(
        [measure('b', 'd', 20), measure('b', 'd', 20), measure('d', 'b', 20)],
        nodes,
      );
      expect(s.counted, 3);
      expect(s.metersPerPixel, 0.05);
    });

    test('each line has its pixels, scale and difference from the average', () {
      final s = computeFloorScale(
        [measure('a', 'b', 5), measure('a', 'c', 18)],
        nodes,
      );
      expect(s.lines[0].pixels, 100);
      expect(s.lines[0].scale, closeTo(0.05, 1e-9));
      expect(s.lines[0].differencePercent, closeTo(-13.04, 0.01));
      expect(s.lines[1].scale, closeTo(0.06, 1e-9));
      expect(s.lines[1].differencePercent, closeTo(4.35, 0.01));
    });

    test('a pair over 5% from the average is an outlier, under is not', () {
      final s = computeFloorScale(
        [measure('a', 'b', 5), measure('a', 'c', 18)],
        nodes,
      );
      expect(s.lines[0].isOutlier, isTrue, reason: '-13% counts both ways');
      expect(s.lines[1].isOutlier, isFalse);
    });

    test('an ignored pair stays listed but out of the average', () {
      final s = computeFloorScale(
        [measure('a', 'b', 5), measure('a', 'c', 90, ignored: true)],
        nodes,
      );
      expect(s.counted, 1);
      expect(s.metersPerPixel, 0.05);
      expect(s.lines, hasLength(2));
      expect(s.lines[1].counted, isFalse);
      expect(s.lines[1].scale, closeTo(0.3, 1e-9));
    });

    test('a node with no position leaves its pair out', () {
      final s = computeFloorScale(
        [measure('a', 'b', 5), measure('a', 'gone', 90)],
        nodes,
      );
      expect(s.counted, 1);
      expect(s.lines[1].pixels, isNull);
      expect(s.lines[1].counted, isFalse);
    });

    test('a pair moved under the minimum gap stops counting', () {
      final close = [node('a', 0, 0), node('b', 49, 0), node('c', 300, 0)];
      final s = computeFloorScale(
        [measure('a', 'b', 5), measure('a', 'c', 15)],
        close,
      );
      expect(s.counted, 1);
      expect(s.metersPerPixel, 0.05);
      expect(s.lines[0].tooClose, isTrue);
    });

    test('is saved at 6 decimals', () {
      final s = computeFloorScale([measure('a', 'c', 10)], nodes);
      expect(s.metersPerPixel, 0.033333);
    });

    test('spread is the sample deviation as a percent of the mean', () {
      final s = computeFloorScale(
        [measure('a', 'b', 5), measure('a', 'c', 18)],
        nodes,
      );
      // sqrt(2 * 0.005^2 / 1) / 0.055
      expect(s.spreadPercent, closeTo(12.856, 0.001));
    });

    test('one measurement has no spread', () {
      final s = computeFloorScale([measure('a', 'b', 5)], nodes);
      expect(s.spreadPercent, isNull);
    });
  });

  group('warnings', () {
    test('fewer than 3 counted warns, 3 does not', () {
      final two = computeFloorScale(
          [measure('a', 'b', 5), measure('a', 'c', 15)], nodes);
      expect(two.hasTooFew, isTrue);
      expect(two.warnings.single, contains('Only 2 counted'));

      final three = computeFloorScale([
        measure('a', 'b', 5),
        measure('a', 'c', 15),
        measure('a', 'd', 25),
      ], nodes);
      expect(three.hasTooFew, isFalse);
      expect(three.warnings, isEmpty);
    });

    test('an ignored measurement does not count toward the 3', () {
      final s = computeFloorScale([
        measure('a', 'b', 5),
        measure('a', 'c', 15),
        measure('a', 'd', 25, ignored: true),
      ], nodes);
      expect(s.hasTooFew, isTrue);
    });

    test('a spread above 5% warns, below does not', () {
      final high = computeFloorScale([
        measure('a', 'b', 5),
        measure('a', 'c', 18),
        measure('a', 'd', 25),
      ], nodes);
      expect(high.hasHighSpread, isTrue);
      expect(high.warnings.single, contains('spread'));

      final low = computeFloorScale([
        measure('a', 'b', 5),
        measure('a', 'c', 15.3),
        measure('a', 'd', 25),
      ], nodes);
      expect(low.hasHighSpread, isFalse);
    });

    test('with none, nothing is saved and the note says what stays', () {
      final s = computeFloorScale(const [], nodes);
      expect(s.metersPerPixel, isNull);
      expect(s.warnings, isEmpty);
      expect(unchangedScaleNote(plan(0.05)), contains('still the default 0.05'));
      expect(unchangedScaleNote(plan(0.032)), contains('last saved 0.032'));
      expect(unchangedScaleNote(plan(null)), contains('not calibrated'));
    });
  });

  group('validation', () {
    test('two different nodes', () {
      expect(validateMeasurePair('a', 'a', 100), contains('two different'));
    });

    test('a minimum pixel gap', () {
      expect(validateMeasurePair('a', 'b', 49), contains('at least 50 px'));
      expect(validateMeasurePair('a', 'b', 50), isNull);
    });

    test('a position on both nodes', () {
      expect(validateMeasurePair('a', 'b', null), contains('no position'));
    });

    test('a positive number', () {
      for (final bad in ['', 'abc', '0', '-3', 'Infinity', 'NaN']) {
        expect(validateRealMeters(bad, 100), isNotNull, reason: bad);
      }
      expect(validateRealMeters(' 4.5 ', 100), isNull);
    });

    test('a distance that would break the scale limit is refused', () {
      expect(validateRealMeters('1001', 100), contains('over 10 m'));
      expect(validateRealMeters('0.00001', 100), contains('too small'));
    });
  });

  group('connected nodes', () {
    const edges = [IndoorEdgeModel(id: 'e1', fromNode: 'a', toNode: 'b')];

    test('use the pixel length times the floor scale', () {
      final line = edgeDistanceLines(edges, nodes, 0.05).single;
      expect(line.pixels, 100);
      expect(line.meters, 5);
    });

    test('are worked out with no measurements at all', () {
      expect(edgeDistanceLines(edges, nodes, kDefaultMetersPerPixel), hasLength(1));
    });

    test('an edge to another building has no length, but is listed', () {
      final line = edgeDistanceLines(
        const [IndoorEdgeModel(id: 'x', fromNode: 'a', toNode: 'far', weight: 50)],
        nodes,
        0.05,
      ).single;
      expect(line.meters, isNull);
    });
  });

  group('moving nodes', () {
    NodeMove move(String id, double fromX, double toX) =>
        NodeMove(id: id, fromX: fromX, fromY: 0, toX: toX, toY: 0);

    test('undo takes back the latest drag', () {
      final log = NodeMoveLog()
        ..add(move('b', 100, 200))
        ..add(move('b', 200, 300));
      expect(log.undo()?.toX, 300);
      expect(log.netMoves.single.toX, 200);
      expect(log.undo()?.toX, 200);
      expect(log.undo(), isNull);
      expect(log.isEmpty, isTrue);
    });

    test('several drags of a node net to first and last position', () {
      final log = NodeMoveLog()
        ..add(move('b', 100, 200))
        ..add(move('b', 200, 300));
      final net = log.netMoves.single;
      expect(net.fromX, 100);
      expect(net.toX, 300);
    });

    test('a node dragged back to its start is not a move', () {
      final log = NodeMoveLog()
        ..add(move('b', 100, 200))
        ..add(move('b', 200, 100));
      expect(log.netMoves, isEmpty);
    });

    test('recalculates the lengths of the moved node\'s edges only', () {
      final changes = edgeLengthChanges(
        const [
          IndoorEdgeModel(id: 'e1', fromNode: 'a', toNode: 'b', weight: 9),
          IndoorEdgeModel(id: 'e2', fromNode: 'c', toNode: 'd', weight: 8),
        ],
        nodes,
        {'b'},
      );
      expect(changes.single.id, 'e1');
      expect(changes.single.newWeight, 100);
      expect(changes.single.oldWeight, 9);
    });

    test('an edge to another floor keeps its fixed cost', () {
      expect(
        edgeLengthChanges(
          const [IndoorEdgeModel(id: 'x', fromNode: 'b', toNode: 'far', weight: 50)],
          nodes,
          {'b'},
        ),
        isEmpty,
      );
    });

    test('finds the measurements a move touched, from either end', () {
      final ab = measure('a', 'b', 5);
      final bc = measure('b', 'c', 10);
      final cd = measure('c', 'd', 10);
      expect(measurementsTouching([ab, bc, cd], {'b'}), [ab, bc]);
    });

    test('a moved node changes the scale its measurements give', () {
      final m = [measure('a', 'b', 5)];
      expect(computeFloorScale(m, nodes).metersPerPixel, 0.05);
      final moved = [node('a', 0, 0), node('b', 250, 0)];
      expect(computeFloorScale(m, moved).metersPerPixel, 0.02);
    });
  });

  group('FloorDistanceRepository', () {
    late FakePostgrest db;
    late FloorDistanceRepository repo;

    setUp(() {
      db = FakePostgrest()..install();
      db.generatedIds.add('floor_plan_distances');
      db.tables['building_floors'] = [
        {'id': 1, 'meters_per_pixel': 0.05},
      ];
      repo = FloorDistanceRepository();
    });
    tearDown(FakePostgrest.uninstall);

    Future<void> addThree() async {
      await repo.add(floorPlanId: 1, nodeAId: 'a', nodeBId: 'b', realMeters: 4);
      await repo.add(floorPlanId: 1, nodeAId: 'a', nodeBId: 'c', realMeters: 12);
      await repo.add(floorPlanId: 1, nodeAId: 'a', nodeBId: 'd', realMeters: 20);
    }

    /// What the editor does after each change.
    Future<double?> recalculate() async {
      final saved = await repo.applyScale(
        await FloorPlanRepository().getAll().then((p) => p.single),
        computeFloorScale(await repo.getForFloor(1), nodes),
      );
      return saved.metersPerPixel;
    }

    double? stored() =>
        db.tables['building_floors']!.single['meters_per_pixel'] as double?;

    test('adding saves the scale, with save-and-confirm', () async {
      await addThree();
      db.requests.clear();
      expect(await recalculate(), 0.04);
      expect(stored(), 0.04);
      expect(db.requests, containsAllInOrder(
          ['PATCH building_floors', 'GET building_floors']));
    });

    test('editing recalculates', () async {
      await addThree();
      await recalculate();
      final first = (await repo.getForFloor(1)).first;
      await repo.setMeters(first.id, 8);
      // 40 m over 900 px
      expect(await recalculate(), 0.044444);
    });

    test('ignoring recalculates, and un-ignoring puts it back', () async {
      await addThree();
      await repo.add(floorPlanId: 1, nodeAId: 'b', nodeBId: 'c', realMeters: 99);
      final odd = (await repo.getForFloor(1)).last;
      await repo.setIgnored(odd.id, true);
      expect(await recalculate(), 0.04);
      expect((await repo.getForFloor(1)).last.ignored, isTrue);
      await repo.setIgnored(odd.id, false);
      expect(await recalculate(), greaterThan(0.04));
    });

    test('deleting recalculates', () async {
      await addThree();
      await repo.add(floorPlanId: 1, nodeAId: 'b', nodeBId: 'c', realMeters: 99);
      await recalculate();
      await repo.delete((await repo.getForFloor(1)).last.id);
      expect(await recalculate(), 0.04);
    });

    test('deleting the last one leaves the scale as it was', () async {
      await repo.add(floorPlanId: 1, nodeAId: 'a', nodeBId: 'b', realMeters: 4);
      await recalculate();
      expect(stored(), 0.04);
      await repo.delete((await repo.getForFloor(1)).single.id);
      db.requests.clear();
      expect(await recalculate(), 0.04);
      expect(db.requestCount('PATCH building_floors'), 0);
    });

    test('an unchanged scale is not written again', () async {
      await addThree();
      await recalculate();
      db.requests.clear();
      await recalculate();
      expect(db.requestCount('PATCH building_floors'), 0);
    });

    test('deleting a node removes its measurements and rescales', () async {
      await addThree();
      await repo.add(floorPlanId: 1, nodeAId: 'b', nodeBId: 'c', realMeters: 99);
      await recalculate();
      db.tables['indoor_nodes'] = [
        {'id': 'b'},
      ];
      // What the foreign key's on delete cascade does on the real server.
      db.onRequest = (key) {
        if (key == 'DELETE indoor_nodes') {
          db.tables['floor_plan_distances']!.removeWhere(
              (r) => r['node_a_id'] == 'b' || r['node_b_id'] == 'b');
        }
      };
      await FloorPlanRepository().deleteIndoorNode('b');
      expect(await repo.getForFloor(1), hasLength(2));
      expect(await recalculate(), 0.04);
    });

    test('only reads this floor', () async {
      await repo.add(floorPlanId: 2, nodeAId: 'a', nodeBId: 'b', realMeters: 4);
      expect(await repo.getForFloor(1), isEmpty);
    });

    group('with no table yet, every call names the SQL file', () {
      final missing = throwsA(isA<FloorDistancesMissing>().having(
          (e) => e.message, 'message', contains('db/floor_plan_distances.sql')));

      setUp(() => db.failureCode = 'PGRST205');

      test('loading', () async {
        db.failing.add('GET floor_plan_distances');
        await expectLater(repo.getForFloor(1), missing);
      });

      test('adding', () async {
        db.failing.add('POST floor_plan_distances');
        await expectLater(
          repo.add(floorPlanId: 1, nodeAId: 'a', nodeBId: 'b', realMeters: 4),
          missing,
        );
      });

      test('editing and ignoring', () async {
        db.failing.add('PATCH floor_plan_distances');
        await expectLater(repo.setMeters('x', 4), missing);
        await expectLater(repo.setIgnored('x', true), missing);
      });

      test('deleting', () async {
        db.failing.add('DELETE floor_plan_distances');
        await expectLater(repo.delete('x'), missing);
      });
    });

    test('another failure is not reported as a missing table', () async {
      db.failing.add('GET floor_plan_distances');
      await expectLater(
        repo.getForFloor(1),
        throwsA(isA<RepositoryException>()
            .having((e) => e, 'type', isNot(isA<FloorDistancesMissing>()))
            .having((e) => e.message, 'message', contains('server exploded'))),
      );
    });

    test('a write Row Level Security blocks is an error', () async {
      await addThree();
      final first = (await repo.getForFloor(1)).first;
      db.rlsBlockedWrites.add('floor_plan_distances');
      await expectLater(repo.setMeters(first.id, 9), throwsA(
          isA<RepositoryException>().having(
              (e) => e.message, 'message', contains('changed nothing'))));
      await expectLater(repo.delete(first.id), throwsA(
          isA<RepositoryException>()));
    });
  });

  group('saveNodeMoves', () {
    late FakePostgrest db;
    const move = NodeMove(id: 'b', fromX: 100, fromY: 0, toX: 200, toY: 50);
    const length = EdgeLengthChange(id: 'e1', oldWeight: 100, newWeight: 206);

    setUp(() {
      db = FakePostgrest()..install();
      db.tables['indoor_nodes'] = [
        {'id': 'b', 'x': 100.0, 'y': 0.0, 'name': 'keep'},
      ];
      db.tables['indoor_edges'] = [
        {'id': 'e1', 'from_node': 'a', 'to_node': 'b', 'weight': 100.0},
      ];
    });
    tearDown(FakePostgrest.uninstall);

    Map<String, dynamic> nodeRow() => db.tables['indoor_nodes']!.single;

    test('writes the position and the edge length', () async {
      await FloorPlanRepository().saveNodeMoves([move], [length]);
      expect(nodeRow()['x'], 200);
      expect(nodeRow()['y'], 50);
      expect(db.tables['indoor_edges']!.single['weight'], 206);
    });

    test('writes only x and y, so a stale copy undoes nothing', () async {
      db.onRequest = (key) {
        if (key == 'PATCH indoor_nodes') nodeRow()['name'] = 'newer';
      };
      await FloorPlanRepository().saveNodeMoves([move], [length]);
      expect(nodeRow()['name'], 'newer');
    });

    test('if an edge fails, the node goes back', () async {
      db.failing.add('PATCH indoor_edges');
      await expectLater(
        FloorPlanRepository().saveNodeMoves([move], [length]),
        throwsA(isA<RepositoryException>().having(
            (e) => e.message, 'message', contains('Nothing was moved'))),
      );
      expect(nodeRow()['x'], 100);
      expect(nodeRow()['y'], 0);
    });

    test('a blocked write counts as a failure and is put back', () async {
      db.rlsBlockedWrites.add('indoor_edges');
      await expectLater(
        FloorPlanRepository().saveNodeMoves([move], [length]),
        throwsA(isA<RepositoryException>()),
      );
      expect(nodeRow()['x'], 100);
    });

    test('names what could not be put back', () async {
      var nodeWrites = 0;
      db.onRequest = (key) {
        if (key == 'PATCH indoor_nodes' && ++nodeWrites == 2) {
          db.failing.add(key);
        }
      };
      db.failing.add('PATCH indoor_edges');
      await expectLater(
        FloorPlanRepository().saveNodeMoves([move], [length]),
        throwsA(isA<RepositoryException>().having(
            (e) => e.message, 'message', contains('node b'))),
      );
    });
  });

  group('db/floor_plan_distances.sql', () {
    final sql = File('db/floor_plan_distances.sql').readAsStringSync();

    test('has the requested columns', () {
      for (final column in [
        'id uuid',
        'floor_plan_id bigint',
        'node_a_id text',
        'node_b_id text',
        'real_meters double precision',
        'ignored boolean not null default false',
        'created_at timestamptz',
        'updated_at timestamptz',
      ]) {
        expect(sql, contains(column));
      }
    });

    test('deleting either node deletes the measurement', () {
      final cascades = RegExp(
              r'references public\.indoor_nodes \(id\) on delete cascade')
          .allMatches(sql);
      expect(cascades, hasLength(2));
    });

    test('only admins can read or write', () {
      expect(sql, contains('enable row level security'));
      expect(sql, contains('for all'));
      expect(sql, contains('using (public.is_admin())'));
      expect(sql, contains('with check (public.is_admin())'));
      expect(RegExp(r'create policy').allMatches(sql), hasLength(1));
      expect(sql, isNot(contains('to anon')));
    });

    test('says to run user_roles.sql first', () {
      expect(sql, contains('RUN db/user_roles.sql FIRST'));
    });
  });

  group('Check distance panel', () {
    Future<void> pumpPanel(
      WidgetTester tester, {
      FloorPlanModel? floor,
      List<FloorDistanceModel> measurements = const [],
      List<IndoorEdgeModel> edges = const [],
      bool tableMissing = false,
      Set<String> movedIds = const {},
      String? selectedId,
      void Function(String)? onCall,
    }) async {
      final summary = computeFloorScale(measurements, nodes);
      final shown = floor ?? plan(summary.metersPerPixel ?? 0.05);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 340,
            child: FloorDistancePanel(
              plan: shown,
              summary: summary,
              edges: edgeDistanceLines(
                  edges, nodes, shown.effectiveMetersPerPixel),
              nodes: nodes,
              tableMissing: tableMissing,
              movedIds: movedIds,
              selectedId: selectedId,
              onClose: () => onCall?.call('close'),
              onSaveScale: () => onCall?.call('save scale'),
              onSelect: (l) => onCall?.call('select ${l.measurement.id}'),
              onEdit: (l) => onCall?.call('edit ${l.measurement.id}'),
              onDelete: (l) => onCall?.call('delete ${l.measurement.id}'),
              onIgnore: (l, v) => onCall?.call('ignore ${l.measurement.id} $v'),
            ),
          ),
        ),
      ));
    }

    const edge = IndoorEdgeModel(id: 'e1', fromNode: 'a', toNode: 'b');

    testWidgets('shows names, meters, pixels, scale and difference',
        (tester) async {
      await pumpPanel(tester, measurements: [
        measure('a', 'b', 5),
        measure('a', 'c', 15),
      ]);
      expect(find.text('a ↔ b'), findsOneWidget);
      expect(find.textContaining('5.0 m · 100 px · 0.05000 m/px'), findsOneWidget);
      expect(find.text('+0.0%'), findsNWidgets(2));
      expect(find.text('Counted measurements: 2'), findsOneWidget);
      expect(find.text('Scale: 0.05 m/px'), findsOneWidget);
      expect(find.text('Spread: 0.0%'), findsOneWidget);
    });

    testWidgets('highlights only the pair over 5%', (tester) async {
      final off = measure('a', 'b', 5);
      final ok = measure('a', 'c', 18);
      await pumpPanel(tester, measurements: [off, ok]);
      expect(find.byKey(ValueKey('outlier-${off.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('outlier-${ok.id}')), findsNothing);
    });

    testWidgets('edit, delete, ignore and tap each reach the screen',
        (tester) async {
      final m = measure('a', 'b', 5);
      final calls = <String>[];
      await pumpPanel(tester, measurements: [m], onCall: calls.add);
      await tester.tap(find.byTooltip('Edit'));
      await tester.tap(find.byTooltip('Delete'));
      await tester.tap(find.byType(Switch));
      await tester.tap(find.text('a ↔ b'));
      expect(calls, [
        'edit ${m.id}',
        'delete ${m.id}',
        'ignore ${m.id} true',
        'select ${m.id}',
      ]);
    });

    testWidgets('an ignored row says so', (tester) async {
      await pumpPanel(tester, measurements: [measure('a', 'b', 5, ignored: true)]);
      expect(find.text('Ignored'), findsOneWidget);
      expect(find.text('Counted measurements: 0'), findsOneWidget);
    });

    testWidgets('shows the warnings', (tester) async {
      await pumpPanel(tester, measurements: [
        measure('a', 'b', 5),
        measure('a', 'c', 18),
      ]);
      expect(find.textContaining('Only 2 counted'), findsOneWidget);
      expect(find.textContaining('The spread is 12.9%'), findsOneWidget);
    });

    testWidgets('with none, says the scale stays', (tester) async {
      await pumpPanel(tester, floor: plan(0.032));
      expect(find.textContaining('last saved 0.032'), findsOneWidget);
      expect(find.text('Scale: 0.032 m/px'), findsOneWidget);
    });

    testWidgets('edges show with no measurements, marked calculated',
        (tester) async {
      await pumpPanel(tester, floor: plan(0.032), edges: [edge]);
      expect(find.text('3.2 m'), findsOneWidget);
      expect(find.text('calculated'), findsOneWidget);
      expect(find.text('not calibrated yet'), findsNothing);
    });

    testWidgets('on the default scale they say not calibrated yet',
        (tester) async {
      await pumpPanel(tester, floor: plan(0.05), edges: [edge]);
      expect(find.text('5.0 m'), findsOneWidget);
      expect(find.text('calculated'), findsOneWidget);
      expect(find.text('not calibrated yet'), findsOneWidget);
    });

    testWidgets('and with no scale saved at all', (tester) async {
      await pumpPanel(tester, floor: plan(null), edges: [edge]);
      expect(find.text('not calibrated yet'), findsOneWidget);
    });

    testWidgets('a cross-building edge is listed with no length',
        (tester) async {
      await pumpPanel(tester, edges: const [
        IndoorEdgeModel(id: 'x', fromNode: 'a', toNode: 'far', weight: 50),
      ]);
      expect(find.textContaining('No length'), findsOneWidget);
      expect(find.text('calculated'), findsNothing);
    });

    testWidgets('a missing table names the file, and edges still show',
        (tester) async {
      await pumpPanel(tester, tableMissing: true, edges: [edge]);
      expect(find.textContaining('db/floor_plan_distances.sql'), findsOneWidget);
      expect(find.text('calculated'), findsOneWidget);
    });

    testWidgets('marks measurements a saved move affected', (tester) async {
      final m = measure('a', 'b', 5);
      await pumpPanel(tester, measurements: [m], movedIds: {m.id});
      expect(find.text('Node moved'), findsOneWidget);
    });

    testWidgets('offers to save when the floor holds a different scale',
        (tester) async {
      final calls = <String>[];
      await pumpPanel(tester,
          floor: plan(0.032),
          measurements: [measure('a', 'b', 5)],
          onCall: calls.add);
      await tester.tap(find.text('Save this scale'));
      expect(calls, ['save scale']);
    });

    testWidgets('no such offer when they agree', (tester) async {
      await pumpPanel(tester, measurements: [measure('a', 'b', 5)]);
      expect(find.text('Save this scale'), findsNothing);
    });
  });

  group('Add distance dialog', () {
    Future<void> open(WidgetTester tester, void Function(double?) done) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async => done(await showDialog<double>(
              context: context,
              builder: (_) => const MeasurementDialog(
                  nameA: 'A', nameB: 'B', pixels: 100),
            )),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('reminds the admin how to measure', (tester) async {
      await open(tester, (_) {});
      expect(find.text('Measure in a straight line between the two nodes.'),
          findsOneWidget);
    });

    testWidgets('refuses a bad number and stays open', (tester) async {
      double? result = -1;
      await open(tester, (v) => result = v);
      await tester.enterText(find.byType(TextFormField), '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a distance greater than 0'), findsOneWidget);
      expect(result, -1);
    });

    testWidgets('returns the meters', (tester) async {
      double? result;
      await open(tester, (v) => result = v);
      await tester.enterText(find.byType(TextFormField), '12.5');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result, 12.5);
    });
  });

  group('the editor', () {
    late FakePostgrest db;
    const imageSize = Size(900, 700);

    setUp(() {
      db = FakePostgrest()..install();
      db.generatedIds.add('floor_plan_distances');
      db.tables['building_floors'] = [
        {'id': 1, 'image_url': 'plan.png', 'meters_per_pixel': 0.05},
      ];
      db.tables['indoor_nodes'] = [
        {'id': 'a', 'floor_plan_id': 1, 'x': 100.0, 'y': 100.0, 'name': 'Door A'},
        {'id': 'b', 'floor_plan_id': 1, 'x': 300.0, 'y': 100.0, 'name': 'Door B'},
        {'id': 'c', 'floor_plan_id': 1, 'x': 100.0, 'y': 500.0, 'name': 'Door C'},
      ];
      db.tables['indoor_edges'] = [
        {
          'id': 'e1',
          'floor_plan_id': 1,
          'from_node': 'a',
          'to_node': 'b',
          'weight': 200.0,
          'is_two_way': true,
        },
      ];
    });
    tearDown(FakePostgrest.uninstall);

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 25; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
    }

    Future<void> pumpEditor(
      WidgetTester tester, {
      Size image = imageSize,
    }) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FloorPlanEditorScreen(floorPlanId: 1, testImageSize: image),
        ),
      ));
      await settle(tester);
    }

    /// How far the plan has been panned.
    Offset panned(WidgetTester tester) {
      final viewer =
          tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      final t = viewer.transformationController!.value.getTranslation();
      return Offset(t.x, t.y);
    }

    Offset onPlan(WidgetTester tester, double x, double y) =>
        tester.getTopLeft(find.byType(InteractiveViewer)) + Offset(x, y);

    Future<void> tapButton(WidgetTester tester, String label) async {
      await tester.tap(find.widgetWithText(ElevatedButton, label));
      await settle(tester);
    }

    Future<void> tapPlan(WidgetTester tester, double x, double y) async {
      await tester.tapAt(onPlan(tester, x, y));
      await settle(tester);
    }

    Future<void> drag(
      WidgetTester tester,
      Offset from,
      Offset to,
    ) async {
      final gesture = await tester.startGesture(onPlan(tester, from.dx, from.dy));
      await tester.pump();
      await gesture.moveTo(onPlan(tester, (from.dx + to.dx) / 2, (from.dy + to.dy) / 2));
      await tester.pump();
      await gesture.moveTo(onPlan(tester, to.dx, to.dy));
      await tester.pump();
      await gesture.up();
      await tester.pump();
    }

    Map<String, dynamic> row(String id) =>
        db.tables['indoor_nodes']!.firstWhere((n) => n['id'] == id);

    testWidgets('both distance buttons sit under every tab', (tester) async {
      await pumpEditor(tester);
      for (final tab in ['Nodes', 'Edges', 'Test Route']) {
        await tester.tap(find.text(tab));
        await tester.pump();
        expect(find.text('Add distance'), findsOneWidget, reason: tab);
        expect(find.text('Check distance'), findsOneWidget, reason: tab);
      }
    });

    testWidgets('measures two unconnected nodes and saves the scale',
        (tester) async {
      await pumpEditor(tester);
      await tapButton(tester, 'Add distance');
      await tapPlan(tester, 300, 100);
      await tapPlan(tester, 100, 500);
      expect(find.text('Door B ↔ Door C'), findsOneWidget);
      expect(find.text(kMeasureHint), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '44.72136');
      await tester.tap(find.descendant(
          of: find.byType(MeasurementDialog), matching: find.text('Save')));
      await settle(tester);

      final saved = db.tables['floor_plan_distances']!.single;
      expect(saved['node_a_id'], 'b');
      expect(saved['node_b_id'], 'c');
      expect(saved['floor_plan_id'], 1);
      expect(db.tables['building_floors']!.single['meters_per_pixel'], 0.1);
    });

    testWidgets('the same node twice is refused', (tester) async {
      await pumpEditor(tester);
      await tapButton(tester, 'Add distance');
      await tapPlan(tester, 300, 100);
      await tapPlan(tester, 300, 100);
      expect(find.text('Pick two different nodes'), findsOneWidget);
      expect(find.byType(MeasurementDialog), findsNothing);
    });

    testWidgets('a missing table names the file on Add distance',
        (tester) async {
      db.failing.add('GET floor_plan_distances');
      db.failureCode = 'PGRST205';
      await pumpEditor(tester);
      await tapButton(tester, 'Add distance');
      expect(find.textContaining('db/floor_plan_distances.sql'), findsOneWidget);
      expect(find.textContaining('Could not load'), findsNothing);
    });

    testWidgets('Check distance opens beside the plan, and a row highlights',
        (tester) async {
      db.tables['floor_plan_distances'] = [
        {
          'id': 'm1',
          'floor_plan_id': 1,
          'node_a_id': 'a',
          'node_b_id': 'c',
          'real_meters': 20.0,
        },
      ];
      await pumpEditor(tester);
      await tapButton(tester, 'Check distance');
      expect(find.byType(FloorDistancePanel), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.text('Door A ↔ Door C'));
      await tester.pump();
      final panel = tester.widget<FloorDistancePanel>(
          find.byType(FloorDistancePanel));
      expect(panel.selectedId, 'm1');
    });

    testWidgets('ignoring a row saves the new scale', (tester) async {
      db.tables['floor_plan_distances'] = [
        {
          'id': 'm1',
          'floor_plan_id': 1,
          'node_a_id': 'a',
          'node_b_id': 'b',
          'real_meters': 20.0,
        },
        {
          'id': 'm2',
          'floor_plan_id': 1,
          'node_a_id': 'a',
          'node_b_id': 'c',
          'real_meters': 20.0,
        },
      ];
      await pumpEditor(tester);
      await tapButton(tester, 'Check distance');
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('measurement-m1')),
          matching: find.byType(Switch)));
      await settle(tester);
      expect(db.tables['floor_plan_distances']!.first['ignored'], isTrue);
      expect(db.tables['building_floors']!.single['meters_per_pixel'], 0.05);
    });

    testWidgets('a dragged node saves with its edge, and rescales',
        (tester) async {
      db.tables['floor_plan_distances'] = [
        {
          'id': 'm1',
          'floor_plan_id': 1,
          'node_a_id': 'a',
          'node_b_id': 'b',
          'real_meters': 40.0,
        },
      ];
      db.tables['building_floors']!.single['meters_per_pixel'] = 0.2;
      await pumpEditor(tester);
      await tapButton(tester, 'Move Nodes');
      await drag(tester, const Offset(300, 100), const Offset(500, 100));

      expect(row('b')['x'], 300, reason: 'nothing is written before saving');
      expect(find.text('1 node moved, not saved yet'), findsOneWidget);
      expect(find.text('Door A ↔ Door B'), findsOneWidget,
          reason: 'lists the affected measurement');

      await tapButton(tester, 'Save Moves');

      expect(row('b')['x'], 500);
      expect(row('b')['y'], 100);
      expect(db.tables['indoor_edges']!.single['weight'], 400);
      expect(db.tables['building_floors']!.single['meters_per_pixel'], 0.1);
      expect(find.text('Node moved'), findsOneWidget);
      expect(find.byType(FloorDistancePanel), findsOneWidget);
      expect(find.textContaining('Measurements affected: Door A ↔ Door B'),
          findsOneWidget);
    });

    testWidgets('undo takes a drag back before saving', (tester) async {
      await pumpEditor(tester);
      await tapButton(tester, 'Move Nodes');
      await drag(tester, const Offset(300, 100), const Offset(500, 100));
      await drag(tester, const Offset(100, 500), const Offset(200, 500));
      expect(find.text('2 nodes moved, not saved yet'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(find.text('1 node moved, not saved yet'), findsOneWidget);

      await tapButton(tester, 'Save Moves');
      expect(row('b')['x'], 500);
      expect(row('c')['x'], 100, reason: 'the undone drag is not saved');
    });

    testWidgets('an undone node is back at its old spot', (tester) async {
      await pumpEditor(tester);
      await tapButton(tester, 'Move Nodes');
      await drag(tester, const Offset(300, 100), const Offset(500, 100));
      await tester.tap(find.text('Undo'));
      await tester.pump();
      await drag(tester, const Offset(300, 100), const Offset(350, 100));
      await tapButton(tester, 'Save Moves');
      expect(row('b')['x'], 350);
    });

    testWidgets('deleting a node drops its measurements and rescales',
        (tester) async {
      db.tables['building_floors']!.single['meters_per_pixel'] = 0.15;
      db.tables['floor_plan_distances'] = [
        {
          'id': 'keep',
          'floor_plan_id': 1,
          'node_a_id': 'a',
          'node_b_id': 'b',
          'real_meters': 20.0,
        },
        {
          'id': 'goes',
          'floor_plan_id': 1,
          'node_a_id': 'a',
          'node_b_id': 'c',
          'real_meters': 80.0,
        },
      ];
      // What the foreign key's on delete cascade does on the real server.
      db.onRequest = (key) {
        if (key == 'DELETE indoor_nodes') {
          db.tables['floor_plan_distances']!
              .removeWhere((r) => r['node_b_id'] == 'c');
        }
      };
      await pumpEditor(tester);
      await tapButton(tester, 'Check distance');
      expect(find.text('Counted measurements: 2'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete').at(2));
      await settle(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await settle(tester);

      expect(find.text('Counted measurements: 1'), findsOneWidget);
      expect(find.text('Door A ↔ Door C'), findsNothing);
      expect(db.tables['building_floors']!.single['meters_per_pixel'], 0.1);
    });

    testWidgets('cancel puts every node back and writes nothing',
        (tester) async {
      await pumpEditor(tester);
      await tapButton(tester, 'Move Nodes');
      await drag(tester, const Offset(300, 100), const Offset(500, 100));
      db.requests.clear();
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(db.requestCount('PATCH indoor_nodes'), 0);
      expect(find.text('Add Node'), findsOneWidget);

      // Back at its old spot, it can be picked up again there.
      await tapButton(tester, 'Add distance');
      await tapPlan(tester, 300, 100);
      await tapPlan(tester, 100, 500);
      expect(find.text('Door B ↔ Door C'), findsOneWidget);
    });

    testWidgets('a drag stays on the image', (tester) async {
      await pumpEditor(tester);
      await tapButton(tester, 'Move Nodes');
      await drag(tester, const Offset(300, 100), const Offset(300, -60));
      await tapButton(tester, 'Save Moves');
      expect(row('b')['y'], 0);
    });

    // The plan is bigger than the viewer here, so it really can pan.
    testWidgets('dragging a node leaves the plan where it is', (tester) async {
      await pumpEditor(tester, image: const Size(4000, 3000));
      await tapButton(tester, 'Move Nodes');
      await drag(tester, const Offset(300, 100), const Offset(500, 100));
      expect(panned(tester), Offset.zero);
      await tapButton(tester, 'Save Moves');
      expect(row('b')['x'], 500);
    });

    testWidgets('dragging away from a node pans the plan', (tester) async {
      await pumpEditor(tester, image: const Size(4000, 3000));
      await tapButton(tester, 'Move Nodes');
      await drag(tester, const Offset(600, 400), const Offset(400, 300));
      expect(panned(tester).dx, lessThan(0));
    });

    testWidgets('dragging away from a node moves nothing', (tester) async {
      await pumpEditor(tester);
      await tapButton(tester, 'Move Nodes');
      await drag(tester, const Offset(600, 400), const Offset(700, 400));
      expect(find.text('0 nodes moved, not saved yet'), findsOneWidget);
    });

    testWidgets('outside Move Nodes a drag does not move a node',
        (tester) async {
      await pumpEditor(tester);
      await drag(tester, const Offset(300, 100), const Offset(500, 100));
      await tapButton(tester, 'Move Nodes');
      expect(find.text('0 nodes moved, not saved yet'), findsOneWidget);
    });
  });
}
