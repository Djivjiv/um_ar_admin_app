import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/data/repositories/floor_plan_repository.dart';
import 'package:um_ar_admin/data/repositories/repository_exception.dart';

import 'support/fake_postgrest.dart';

void main() {
  group('FloorGraphStats', () {
    FloorGraphStats stats(
      int nodes,
      Set<String> navigable,
      List<(String, String)> edges,
    ) =>
        FloorGraphStats.compute(
          nodeCount: nodes,
          navigableIds: navigable,
          edges: edges,
        );

    test('no nodes is empty', () {
      expect(stats(0, {}, []).status, RoutingStatus.empty);
    });

    test('one navigable node is not routable', () {
      expect(stats(3, {'a'}, []).status, RoutingStatus.notRoutable);
    });

    test('navigable nodes with no edges are not routable', () {
      final s = stats(2, {'a', 'b'}, []);
      expect(s.status, RoutingStatus.notRoutable);
      expect(s.disconnectedCount, 1);
    });

    test('every navigable node connected is ready', () {
      final s = stats(3, {'a', 'b', 'c'}, [('a', 'b'), ('b', 'c')]);
      expect(s.status, RoutingStatus.ready);
      expect(s.disconnectedCount, 0);
    });

    test('nodes outside the largest group make it partial', () {
      final s = stats(4, {'a', 'b', 'c', 'd'}, [('a', 'b'), ('b', 'c')]);
      expect(s.status, RoutingStatus.partial);
      expect(s.disconnectedCount, 1);
    });

    test('edge direction does not matter', () {
      final s = stats(3, {'a', 'b', 'c'}, [('b', 'a'), ('b', 'c')]);
      expect(s.status, RoutingStatus.ready);
    });

    test('edges through a non-navigable node do not connect', () {
      final s = stats(3, {'a', 'c'}, [('a', 'info'), ('info', 'c')]);
      expect(s.status, RoutingStatus.notRoutable);
      expect(s.edgeCount, 2, reason: 'every edge still counts as an edge');
    });

    test('counts are carried through', () {
      final s = FloorGraphStats.compute(
        nodeCount: 5,
        navigableIds: {'a', 'b'},
        edges: const [('a', 'b')],
        crossBuildingLinks: 2,
        crossBuildingPending: 1,
      );
      expect(s.nodeCount, 5);
      expect(s.navigableCount, 2);
      expect(s.crossBuildingLinks, 2);
      expect(s.crossBuildingPending, 1);
    });
  });

  group('deleting a floor plan', () {
    late FakePostgrest db;

    Map<String, dynamic> outdoor(String id) =>
        db.tables['outdoor_nodes']!.firstWhere((r) => r['id'] == id);
    Map<String, dynamic> indoor(String id) =>
        db.tables['indoor_nodes']!.firstWhere((r) => r['id'] == id);

    setUp(() {
      db = FakePostgrest()..install();
      db.tables['building_floors'] = [
        {'id': 1, 'building_id': 7},
        {'id': 2, 'building_id': 7},
      ];
      db.tables['indoor_nodes'] = [
        {'id': 'n1', 'floor_plan_id': 1, 'outdoor_node_id': 'p1'},
        // The outdoor side points here, but the reverse was never written.
        {'id': 'n2', 'floor_plan_id': 1, 'outdoor_node_id': null},
        // The reverse points out, but nothing points back.
        {'id': 'n3', 'floor_plan_id': 1, 'outdoor_node_id': 'p3'},
        {'id': 'other', 'floor_plan_id': 2, 'outdoor_node_id': 'p9'},
      ];
      db.tables['outdoor_nodes'] = [
        {'id': 'p1', 'indoor_node_id': 'n1', 'is_entrance': true},
        {'id': 'p2', 'indoor_node_id': 'n2', 'is_entrance': true},
        {'id': 'p3', 'indoor_node_id': null, 'is_entrance': true},
        {'id': 'p9', 'indoor_node_id': 'other', 'is_entrance': true},
      ];
    });
    tearDown(FakePostgrest.uninstall);

    test('clears the outdoor side, even for one-way links', () async {
      await FloorPlanRepository().delete(1);
      expect(outdoor('p1')['indoor_node_id'], isNull);
      expect(outdoor('p2')['indoor_node_id'], isNull);
    });

    test('clears the indoor side', () async {
      await FloorPlanRepository().delete(1);
      expect(indoor('n1')['outdoor_node_id'], isNull);
      expect(indoor('n3')['outdoor_node_id'], isNull);
    });

    test('leaves other floors alone and keeps the entrances', () async {
      await FloorPlanRepository().delete(1);
      expect(outdoor('p9')['indoor_node_id'], 'other');
      expect(indoor('other')['outdoor_node_id'], 'p9');
      expect(outdoor('p1')['is_entrance'], isTrue);
      expect(db.tables['building_floors'], hasLength(1));
    });

    test('puts both sides back when the delete fails', () async {
      db.failing.add('DELETE building_floors');
      await expectLater(FloorPlanRepository().delete(1), throwsA(isA<Object>()));
      expect(outdoor('p1')['indoor_node_id'], 'n1');
      expect(outdoor('p2')['indoor_node_id'], 'n2');
      expect(indoor('n1')['outdoor_node_id'], 'p1');
      expect(indoor('n3')['outdoor_node_id'], 'p3');
      expect(db.tables['building_floors'], hasLength(2));
    });

    test('RLS blocking the delete puts both sides back', () async {
      db.rlsBlockedWrites.add('building_floors');
      await expectLater(
        FloorPlanRepository().delete(1),
        throwsA(isA<RepositoryException>()
            .having((e) => e.message, 'message', contains('changed nothing'))),
      );
      expect(outdoor('p1')['indoor_node_id'], 'n1');
    });

    test('nothing is deleted when the links can\'t be cleared', () async {
      db.rlsBlockedWrites.add('outdoor_nodes');
      await expectLater(
        FloorPlanRepository().delete(1),
        throwsA(isA<RepositoryException>()
            .having((e) => e.message, 'message', contains('Nothing was'))),
      );
      expect(db.tables['building_floors'], hasLength(2));
    });

    group('when the indoor clear fails after the outdoor one worked', () {
      test('RLS: the outdoor links go back', () async {
        db.rlsBlockedWrites.add('indoor_nodes');
        await expectLater(
          FloorPlanRepository().delete(1),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message',
              allOf(contains('Nothing was deleted'), contains('put back')))),
        );
        expect(outdoor('p1')['indoor_node_id'], 'n1');
        expect(outdoor('p2')['indoor_node_id'], 'n2');
        expect(db.tables['building_floors'], hasLength(2));
      });

      test('server error: the outdoor links go back', () async {
        db.failing.add('PATCH indoor_nodes');
        await expectLater(
          FloorPlanRepository().delete(1),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message',
              allOf(contains('Nothing was deleted'), contains('put back'),
                  contains('server exploded')))),
        );
        expect(outdoor('p1')['indoor_node_id'], 'n1');
        expect(outdoor('p2')['indoor_node_id'], 'n2');
        expect(indoor('n1')['outdoor_node_id'], 'p1');
        expect(db.tables['building_floors'], hasLength(2));
      });

      test('the message does not claim links went back if they did not',
          () async {
        db.failing.add('PATCH indoor_nodes');
        var outdoorWrites = 0;
        db.onRequest = (key) {
          // The clear gets through; the restore that follows does not.
          if (key == 'PATCH outdoor_nodes' && ++outdoorWrites == 2) {
            db.failing.add(key);
          }
        };
        await expectLater(
          FloorPlanRepository().delete(1),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message',
              allOf(contains('could not be put back'), contains('p1'),
                  contains('p2')))),
        );
      });

      test('one failed restore does not stop the next', () async {
        db.failing.add('DELETE building_floors');
        var indoorWrites = 0;
        db.onRequest = (key) {
          // The first outdoor restore fails, then later writes get through.
          if (key == 'PATCH outdoor_nodes' && ++indoorWrites == 2) {
            db.failing.add(key);
          } else if (key == 'PATCH outdoor_nodes') {
            db.failing.remove(key);
          }
        };
        await expectLater(
          FloorPlanRepository().delete(1),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message',
              allOf(contains('p1'), isNot(contains('p2'))))),
        );
        expect(outdoor('p2')['indoor_node_id'], 'n2');
        expect(indoor('n1')['outdoor_node_id'], 'p1');
      });
    });

    test('a partial outdoor clear is put back before giving up', () async {
      // Only one row answers: what RLS does to a mixed set of rows.
      db.tables['outdoor_nodes']!.removeWhere((r) => r['id'] == 'p9');
      final realRows = [...db.tables['outdoor_nodes']!];
      db.onRequest = (key) {
        if (key == 'PATCH outdoor_nodes') {
          db.tables['outdoor_nodes'] = [realRows.first];
        } else if (key == 'GET indoor_nodes') {
          db.tables['outdoor_nodes'] = [...realRows];
        }
      };
      await expectLater(
        FloorPlanRepository().delete(1),
        throwsA(isA<RepositoryException>()
            .having((e) => e.message, 'message', contains('only 1 of 2'))),
      );
      expect(realRows.first['indoor_node_id'], 'n1');
      expect(db.tables['building_floors'], hasLength(2));
    });

    test('a floor plan with no links just deletes', () async {
      db.tables['indoor_nodes']!.clear();
      await FloorPlanRepository().delete(2);
      expect(db.requestCount('PATCH outdoor_nodes'), 0);
    });

    test('handles more nodes than one URL can carry', () async {
      db.tables['indoor_nodes'] = [
        for (var i = 0; i < 450; i++) {'id': 'm$i', 'floor_plan_id': 1},
      ];
      db.tables['outdoor_nodes'] = [
        {'id': 'far', 'indoor_node_id': 'm440', 'is_entrance': true},
      ];
      await FloorPlanRepository().delete(1);
      expect(outdoor('far')['indoor_node_id'], isNull);
      expect(db.requestCount('GET outdoor_nodes'), 3);
    });
  });
}
