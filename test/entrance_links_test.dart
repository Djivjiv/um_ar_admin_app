import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/core/utils/entrance_links.dart';
import 'package:um_ar_admin/data/repositories/building_repository.dart';
import 'package:um_ar_admin/data/repositories/entrance_link_repository.dart';
import 'package:um_ar_admin/data/repositories/node_repository.dart';
import 'package:um_ar_admin/data/repositories/repository_exception.dart';
import 'package:um_ar_admin/domain/models/floor_plan_model.dart';
import 'package:um_ar_admin/domain/models/indoor_node_model.dart';
import 'package:um_ar_admin/domain/models/outdoor_node_model.dart';
import 'package:um_ar_admin/presentation/screens/campus_map/campus_map_editor_screen.dart';
import 'package:um_ar_admin/presentation/screens/outdoor_ar/entrance_status_section.dart';

import 'support/fake_postgrest.dart';

IndoorNodeModel _indoor(
  String id, {
  int? building = 1,
  int? plan,
  int floor = 1,
  String label = 'entrance',
  bool active = true,
  bool navigable = true,
  String? name,
}) =>
    IndoorNodeModel(
      id: id,
      buildingId: building,
      floorPlanId: plan,
      floor: floor,
      label: label,
      isActive: active,
      isNavigable: navigable,
      name: name,
    );

OutdoorNodeModel _outdoor(
  String id, {
  String? building = '1',
  String? target,
  bool entrance = true,
  bool active = true,
}) =>
    OutdoorNodeModel(
      id: id,
      buildingId: building,
      indoorNodeId: target,
      isEntrance: entrance,
      isActive: active,
    );

Matcher _failsWith(String text) => throwsA(isA<RepositoryException>()
    .having((e) => e.message, 'message', contains(text)));

void main() {
  group('form validation', () {
    test('a non-entrance needs nothing', () {
      expect(
        entranceFormError(
            isEntrance: false, buildingId: null, indoorNodeId: null),
        isNull,
      );
    });

    test('an entrance needs a building', () {
      expect(
        entranceFormError(
            isEntrance: true, buildingId: null, indoorNodeId: 'n1'),
        contains('building'),
      );
    });

    test('an entrance needs an indoor node', () {
      for (final empty in [null, '']) {
        expect(
          entranceFormError(
              isEntrance: true, buildingId: '1', indoorNodeId: empty),
          contains('indoor entrance node'),
        );
      }
    });

    test('an entrance with both is fine', () {
      expect(
        entranceFormError(
            isEntrance: true, buildingId: '1', indoorNodeId: 'n1'),
        isNull,
      );
    });
  });

  group('indoor entrance nodes', () {
    test('are active, navigable and labelled entrance', () {
      expect(isIndoorEntranceNode(_indoor('a')), isTrue);
      expect(isIndoorEntranceNode(_indoor('a', label: 'hallway')), isFalse);
      expect(isIndoorEntranceNode(_indoor('a', active: false)), isFalse);
      expect(isIndoorEntranceNode(_indoor('a', navigable: false)), isFalse);
    });

    test('use the floor plan for building and floor when they can', () {
      const plans = {7: FloorPlanModel(id: 7, buildingId: 3, floorNumber: 2)};
      final n = _indoor('a', building: null, plan: 7, floor: 9);
      expect(indoorNodeBuilding(n, plans), 3);
      expect(indoorNodeFloor(n, plans), 2);
      expect(indoorNodeFloor(_indoor('b', floor: 4), plans), 4);
    });

    test('are labelled with floor, name and id', () {
      expect(entranceNodeLabel(_indoor('n1', name: 'Main Door'), const {}),
          'Floor 1 · Main Door (n1)');
      expect(entranceNodeLabel(_indoor('n1'), const {}), 'Floor 1 · n1');
    });
  });

  group('the same-building rule', () {
    String? check(IndoorNodeModel? target, {int? building = 1}) =>
        entranceLinkBlocker(
          outdoorId: 'p1',
          buildingId: building,
          indoorNodeId: 'n1',
          target: target,
          plans: const {7: FloorPlanModel(id: 7, buildingId: 2)},
          entrances: const [],
        );

    test('allows a node in the same building', () {
      expect(check(_indoor('n1')), isNull);
    });

    test('refuses a node in another building', () {
      expect(check(_indoor('n1', building: 2)), contains('different building'));
    });

    test('goes by the floor plan when building_id is empty', () {
      final n = _indoor('n1', building: null, plan: 7);
      expect(check(n, building: 2), isNull);
      expect(check(n, building: 1), contains('different building'));
    });

    test('refuses a node that is gone or is not an entrance', () {
      expect(check(null), contains('no longer exists'));
      expect(check(_indoor('n1', label: 'hallway')),
          contains('not an active entrance'));
    });
  });

  group('the one-to-one rule', () {
    String? check(List<OutdoorNodeModel> entrances) => entranceLinkBlocker(
          outdoorId: 'p1',
          buildingId: 1,
          indoorNodeId: 'n1',
          target: _indoor('n1'),
          plans: const {},
          entrances: entrances,
        );

    test('allows an indoor node nothing else uses', () {
      expect(check([_outdoor('p2', target: 'n2')]), isNull);
    });

    test('refuses an indoor node another entrance uses', () {
      expect(check([_outdoor('p2', target: 'n1')]), contains('p2'));
    });

    test('an inactive entrance still holds the node', () {
      expect(check([_outdoor('p2', target: 'n1', active: false)]), isNotNull);
    });

    test('an entrance can keep its own node', () {
      expect(check([_outdoor('p1', target: 'n1')]), isNull);
    });

    test('a node no longer flagged as an entrance does not hold it', () {
      expect(check([_outdoor('p2', target: 'n1', entrance: false)]), isNull);
    });

    test('indoorNodesInUse marks taken nodes but not this entrance\'s', () {
      final used = indoorNodesInUse([
        _outdoor('p1', target: 'n1'),
        _outdoor('p2', target: 'n2'),
        _outdoor('p3'),
      ], exceptOutdoorId: 'p1');
      expect(used, {'n2': 'p2'});
    });
  });

  group('the floor warning', () {
    final nodes = [
      _indoor('g', floor: 1),
      _indoor('u', floor: 3),
      _indoor('basement-hall', floor: -1, label: 'hallway'),
    ];

    String? warn(IndoorNodeModel n) => entranceFloorWarning(
        target: n, buildingNodes: nodes, plans: const {});

    test('is quiet on the lowest entrance floor', () {
      expect(warn(nodes[0]), isNull);
    });

    test('flags a higher floor', () {
      expect(warn(nodes[1]), contains('floor 3'));
      expect(warn(nodes[1]), contains('floor 1'));
    });

    test('ignores floors that have no entrance', () {
      expect(warn(nodes[0]), isNull, reason: 'the basement has no entrance');
    });
  });

  group('status list', () {
    List<EntranceStatusRow> list(
      List<OutdoorNodeModel> entrances,
      List<IndoorNodeModel> indoor, {
      Set<int>? active,
    }) =>
        entranceStatusList(
          entrances: entrances,
          indoorNodes: indoor,
          plans: const {},
          activeBuildingIds: active,
        );

    test('linked', () {
      final rows = list([_outdoor('p1', target: 'n1')], [_indoor('n1')]);
      expect(rows.single.status, EntranceStatus.linked);
      expect(rows.single.isLinked, isTrue);
    });

    test('missing indoor node: none chosen, deleted, or not an entrance', () {
      final rows = list([
        _outdoor('p1'),
        _outdoor('p2', target: 'gone'),
        _outdoor('p3', target: 'hall'),
      ], [
        _indoor('hall', label: 'hallway'),
      ]);
      expect(rows.map((r) => r.status),
          everyElement(EntranceStatus.missingIndoorNode));
      expect(rows[1].detail, contains('no longer exists'));
    });

    test('indoor node in a different building', () {
      final rows =
          list([_outdoor('p1', target: 'n1')], [_indoor('n1', building: 2)]);
      expect(rows.single.status, EntranceStatus.differentBuilding);
    });

    test('an entrance with no building is not reported as linked', () {
      final rows = list(
          [_outdoor('p1', building: null, target: 'n1')], [_indoor('n1')]);
      expect(rows.single.status, EntranceStatus.differentBuilding);
      expect(rows.single.buildingId, isNull);
    });

    test('an indoor node shared by two entrances flags both', () {
      final rows = list([
        _outdoor('p1', target: 'n1'),
        _outdoor('p2', target: 'n1'),
      ], [
        _indoor('n1'),
      ]);
      expect(rows.map((r) => r.status),
          everyElement(EntranceStatus.sharedIndoorNode));
    });

    test('leaves out non-entrances, inactive ones and inactive buildings', () {
      final rows = list([
        _outdoor('kept'),
        _outdoor('not-entrance', entrance: false),
        _outdoor('off', active: false),
        _outdoor('closed', building: '9'),
      ], const [], active: {1});
      expect(rows.map((r) => r.entrance.id), ['kept']);
    });

    test('keeps an entrance with no building even with a building filter', () {
      final rows = list([_outdoor('p1', building: null)], const [], active: {1});
      expect(rows, hasLength(1));
    });

    test('unlinkedByBuilding counts buildings, not entrances', () {
      final rows = list([
        _outdoor('a1'),
        _outdoor('a2'),
        _outdoor('b1', building: '2', target: 'n2'),
        _outdoor('c1', building: '3'),
      ], [
        _indoor('n2', building: 2),
      ]);
      final grouped = unlinkedByBuilding(rows);
      expect(grouped.keys, unorderedEquals([1, 3]));
      expect(grouped[1], hasLength(2));
    });
  });

  group('saving', () {
    late FakePostgrest db;

    Map<String, dynamic> indoorRow(String id) =>
        db.tables['indoor_nodes']!.firstWhere((r) => r['id'] == id);
    Map<String, dynamic>? outdoorRow(String id) => db.tables['outdoor_nodes']!
        .where((r) => r['id'] == id)
        .firstOrNull;

    setUp(() {
      db = FakePostgrest()..install();
      db.tables['building_floors'] = [
        {'id': 10, 'building_id': 1, 'floor_number': 1},
        {'id': 20, 'building_id': 2, 'floor_number': 1},
      ];
      db.tables['indoor_nodes'] = [
        for (final (id, building, plan) in [
          ('n1', 1, 10),
          ('n2', 1, 10),
          ('other', 2, 20),
        ])
          {
            'id': id,
            'building_id': building,
            'floor_plan_id': plan,
            'label': 'entrance',
            'is_navigable': true,
            'is_active': true,
            'is_entrance': false,
            'outdoor_node_id': null,
          },
      ];
      db.tables['outdoor_nodes'] = [
        {
          'id': 'taken',
          'building_id': '1',
          'is_entrance': true,
          'indoor_node_id': 'n2',
        },
      ];
      db.tables['outdoor_edges'] = [];
    });
    tearDown(FakePostgrest.uninstall);

    test('a new entrance writes both sides', () async {
      await EntranceLinkRepository().save(_outdoor('p1', target: 'n1'));
      expect(outdoorRow('p1')!['indoor_node_id'], 'n1');
      expect(indoorRow('n1')['outdoor_node_id'], 'p1');
      expect(indoorRow('n1')['is_entrance'], isTrue);
    });

    test('refuses to save an entrance with no indoor node', () async {
      await expectLater(EntranceLinkRepository().save(_outdoor('p1')),
          _failsWith('indoor entrance node'));
      expect(outdoorRow('p1'), isNull);
    });

    test('refuses a node another entrance holds, and writes nothing', () async {
      await expectLater(
        EntranceLinkRepository().save(_outdoor('p1', target: 'n2')),
        _failsWith('already linked to outdoor entrance taken'),
      );
      expect(outdoorRow('p1'), isNull);
    });

    test('refuses a node in another building', () async {
      await expectLater(
        EntranceLinkRepository().save(_outdoor('p1', target: 'other')),
        _failsWith('different building'),
      );
    });

    test('moving to another node clears the old reverse link', () async {
      final repo = EntranceLinkRepository();
      final first = await repo.save(_outdoor('p1', target: 'n1'));
      db.tables['outdoor_nodes']!.removeWhere((r) => r['id'] == 'taken');

      await repo.save(_outdoor('p1', target: 'n2'), previous: first);
      expect(indoorRow('n1')['outdoor_node_id'], isNull);
      expect(indoorRow('n2')['outdoor_node_id'], 'p1');
    });

    test('turning entrance off clears the reverse link', () async {
      final repo = EntranceLinkRepository();
      final first = await repo.save(_outdoor('p1', target: 'n1'));
      await repo.save(_outdoor('p1', entrance: false), previous: first);
      expect(indoorRow('n1')['outdoor_node_id'], isNull);
      expect(outdoorRow('p1')!['is_entrance'], isFalse);
    });

    test('re-saving a one-way link fills in the reverse side', () async {
      final repo = EntranceLinkRepository();
      db.tables['outdoor_nodes']!.add({
        'id': 'p1',
        'building_id': '1',
        'is_entrance': true,
        'indoor_node_id': 'n1',
      });
      final old = _outdoor('p1', target: 'n1');
      await repo.save(old, previous: old);
      expect(indoorRow('n1')['outdoor_node_id'], 'p1');
    });

    test('a failed indoor write undoes a new outdoor node', () async {
      db.failing.add('PATCH indoor_nodes');
      await expectLater(
        EntranceLinkRepository().save(_outdoor('p1', target: 'n1')),
        _failsWith('Nothing was changed'),
      );
      expect(outdoorRow('p1'), isNull);
    });

    test('a failed indoor write puts an edited node back', () async {
      final repo = EntranceLinkRepository();
      final first = await repo.save(_outdoor('p1', target: 'n1'));
      db.tables['outdoor_nodes']!.removeWhere((r) => r['id'] == 'taken');
      var patches = 0;
      db.onRequest = (key) {
        // The first PATCH clears n1; the second, linking n2, fails.
        if (key == 'PATCH indoor_nodes' && ++patches == 2) db.failing.add(key);
        if (key == 'PATCH outdoor_nodes' && patches == 2) {
          db.failing.remove('PATCH indoor_nodes');
        }
      };
      await expectLater(
        repo.save(_outdoor('p1', target: 'n2'), previous: first),
        _failsWith('Nothing was changed'),
      );
      expect(outdoorRow('p1')!['indoor_node_id'], 'n1');
      expect(indoorRow('n1')['outdoor_node_id'], 'p1');
    });

    test('RLS blocking the indoor write is not a silent success', () async {
      db.rlsBlockedWrites.add('indoor_nodes');
      await expectLater(
        EntranceLinkRepository().save(_outdoor('p1', target: 'n1')),
        _failsWith('Nothing was changed'),
      );
      expect(outdoorRow('p1'), isNull);
    });

    test('deleting an outdoor node clears the indoor side', () async {
      await EntranceLinkRepository().save(_outdoor('p1', target: 'n1'));
      await NodeRepository().deleteNode('p1');
      expect(indoorRow('n1')['outdoor_node_id'], isNull);
    });

    test('a failed outdoor delete puts the indoor side back', () async {
      await EntranceLinkRepository().save(_outdoor('p1', target: 'n1'));
      db.failing.add('DELETE outdoor_nodes');
      await expectLater(
          NodeRepository().deleteNode('p1'), throwsA(isA<Object>()));
      expect(indoorRow('n1')['outdoor_node_id'], 'p1');
    });

    group('from the floor plan editor', () {
      test('allows linking an unlinked entrance of the building', () async {
        db.tables['outdoor_nodes']!.add({
          'id': 'free',
          'building_id': '1',
          'is_entrance': true,
          'indoor_node_id': null,
        });
        final node = IndoorNodeModel(
            id: 'n1', buildingId: 1, outdoorNodeId: 'free');
        final repo = EntranceLinkRepository();
        await repo.checkIndoorSide(node);
        await repo.syncFromIndoor(node);
        expect(outdoorRow('free')!['indoor_node_id'], 'n1');
      });

      test('refuses an entrance linked to a different indoor node', () async {
        await expectLater(
          EntranceLinkRepository().checkIndoorSide(
              const IndoorNodeModel(
                  id: 'n1', buildingId: 1, outdoorNodeId: 'taken')),
          _failsWith('already linked to indoor node n2'),
        );
      });

      test('refuses a typed id that is missing or from another building',
          () async {
        final repo = EntranceLinkRepository();
        await expectLater(
          repo.checkIndoorSide(const IndoorNodeModel(
              id: 'n1', buildingId: 1, outdoorNodeId: 'nope')),
          _failsWith('does not exist'),
        );
        await expectLater(
          repo.checkIndoorSide(const IndoorNodeModel(
              id: 'other', buildingId: 2, outdoorNodeId: 'taken')),
          _failsWith('different building'),
        );
      });

      test('unlinking there clears the outdoor side only if it matched',
          () async {
        final repo = EntranceLinkRepository();
        await repo.syncFromIndoor(
          const IndoorNodeModel(id: 'n1'),
          previous: const IndoorNodeModel(id: 'n1', outdoorNodeId: 'taken'),
        );
        expect(outdoorRow('taken')!['indoor_node_id'], 'n2',
            reason: 'taken points at n2, not n1');

        await repo.syncFromIndoor(
          const IndoorNodeModel(id: 'n2'),
          previous: const IndoorNodeModel(id: 'n2', outdoorNodeId: 'taken'),
        );
        expect(outdoorRow('taken')!['indoor_node_id'], isNull);
      });

      test('deleting an indoor node clears what pointed at it', () async {
        await EntranceLinkRepository().clearLinksToIndoorNode('n2');
        expect(outdoorRow('taken')!['indoor_node_id'], isNull);
      });
    });

    group('loading', () {
      test('finds nodes by floor plan when building_id is empty', () async {
        db.tables['indoor_nodes']!.add({
          'id': 'plan-only',
          'building_id': null,
          'floor_plan_id': 10,
          'label': 'entrance',
          'is_navigable': true,
        });
        final data = await EntranceLinkRepository().loadForBuilding(1);
        expect(data.entranceNodes.map((n) => n.id),
            containsAll(['n1', 'n2', 'plan-only']));
        expect(data.entranceNodes.map((n) => n.id), isNot(contains('other')));
      });

      test('getStatusList reports what the database holds', () async {
        final rows = await EntranceLinkRepository().getStatusList();
        expect(rows.single.entrance.id, 'taken');
        expect(rows.single.status, EntranceStatus.linked);
      });

      test('a failed load is an error, not an empty list', () async {
        db.failing.add('GET outdoor_nodes');
        await expectLater(EntranceLinkRepository().getStatusList(),
            _failsWith('Failed to load building entrances'));
        await expectLater(EntranceLinkRepository().loadForBuilding(1),
            _failsWith('Failed to load'));
      });

      test('sees past the 1000-row cap', () async {
        db.tables['outdoor_nodes'] = [
          for (var i = 0; i < 1500; i++)
            {
              'id': 'p${i.toString().padLeft(4, '0')}',
              'building_id': '1',
              'is_entrance': true,
            },
        ];
        final rows = await EntranceLinkRepository().getStatusList();
        expect(rows, hasLength(1500));
      });
    });
  });

  group('the form', () {
    late FakePostgrest db;

    setUp(() {
      db = FakePostgrest()..install();
      db.tables['buildings'] = [
        {'id': 1, 'name': 'Main', 'is_active': true},
      ];
      db.tables['building_floors'] = [
        {'id': 10, 'building_id': 1, 'floor_number': 1},
      ];
      db.tables['indoor_nodes'] = [
        {
          'id': 'n1',
          'building_id': 1,
          'floor_plan_id': 10,
          'label': 'entrance',
          'name': 'Main Door',
          'is_navigable': true,
          'is_active': true,
        },
      ];
      db.tables['outdoor_nodes'] = [];
    });
    tearDown(FakePostgrest.uninstall);

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
    }

    /// Opens the dialog; [saved] receives what it pops.
    Future<void> open(
      WidgetTester tester,
      OutdoorNodeModel existing,
      void Function(OutdoorNodeModel?) saved,
    ) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved(await showDialog<OutdoorNodeModel>(
                  context: context,
                  builder: (_) => CampusNodeDialog(
                    existing: existing,
                    buildingRepo: BuildingRepository(),
                  ),
                ));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await settle(tester);
    }

    testWidgets('refuses Save with no indoor node, and says why',
        (tester) async {
      OutdoorNodeModel? result;
      await open(tester, _outdoor('p1'), (m) => result = m);
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.textContaining('Choose the indoor entrance node'),
          findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(result, isNull);
    });

    testWidgets('saves once a node is picked, taking its floor',
        (tester) async {
      OutdoorNodeModel? result;
      await open(tester, _outdoor('p1'), (m) => result = m);
      await tester.tap(find.text('Indoor entrance node *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Floor 1 · Main Door (n1)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(result?.indoorNodeId, 'n1');
      expect(result?.floor, 1);
    });

    testWidgets('says when the building has no entrance nodes',
        (tester) async {
      db.tables['indoor_nodes'] = [];
      await open(tester, _outdoor('p1'), (_) {});
      expect(find.textContaining('no indoor entrance nodes'), findsOneWidget);
    });

    testWidgets('a failed load shows why, and Retry recovers', (tester) async {
      db.failing.add('GET indoor_nodes');
      await open(tester, _outdoor('p1'), (_) {});
      expect(find.textContaining('Could not load indoor nodes'), findsOneWidget);

      db.failing.clear();
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(find.text('Indoor entrance node *'), findsOneWidget);
    });

    testWidgets('a stale link is called out, not silently kept',
        (tester) async {
      await open(tester, _outdoor('p1', target: 'gone'), (_) {});
      expect(find.textContaining('saved link (gone)'), findsOneWidget);
    });
  });

  group('the AR check section', () {
    Future<void> pump(
      WidgetTester tester, {
      List<EntranceStatusRow>? rows,
      Object? error,
      VoidCallback? onRetry,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EntranceStatusSection(
              rows: rows,
              error: error,
              onRetry: onRetry ?? () {},
              buildingName: (id) => id == null ? 'No building' : 'B$id',
            ),
          ),
        ),
      ));
    }

    testWidgets('counts buildings and lists what is wrong', (tester) async {
      await pump(tester, rows: const [
        EntranceStatusRow(
          entrance: OutdoorNodeModel(id: 'p1'),
          buildingId: 1,
          status: EntranceStatus.missingIndoorNode,
          detail: 'No indoor node chosen',
        ),
        EntranceStatusRow(
          entrance: OutdoorNodeModel(id: 'p2'),
          buildingId: 1,
          status: EntranceStatus.differentBuilding,
          detail: 'Indoor node n9 belongs to another building',
        ),
        EntranceStatusRow(
          entrance: OutdoorNodeModel(id: 'p3'),
          buildingId: 2,
          status: EntranceStatus.linked,
        ),
      ]);
      expect(find.text('Buildings with unlinked entrances (1)'), findsOneWidget);
      expect(find.text('B1'), findsOneWidget);
      expect(find.text('No indoor node chosen'), findsOneWidget);
      expect(find.textContaining('1 of 3 entrances'), findsOneWidget);
    });

    testWidgets('lists every entrance when expanded', (tester) async {
      await pump(tester, rows: const [
        EntranceStatusRow(
          entrance: OutdoorNodeModel(id: 'p3'),
          buildingId: 2,
          status: EntranceStatus.linked,
        ),
      ]);
      expect(find.text('Buildings with unlinked entrances (0)'), findsOneWidget);
      await tester.tap(find.text('All entrances (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Linked'), findsOneWidget);
    });

    testWidgets('a failure shows why, with Retry', (tester) async {
      var retries = 0;
      await pump(tester, error: 'boom', onRetry: () => retries++);
      expect(find.textContaining('Could not check building entrances'),
          findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });
  });
}
