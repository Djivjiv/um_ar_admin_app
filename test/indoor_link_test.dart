import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/data/repositories/building_repository.dart';
import 'package:um_ar_admin/data/repositories/facility_repository.dart';
import 'package:um_ar_admin/data/repositories/floor_plan_repository.dart';
import 'package:um_ar_admin/data/repositories/indoor_link_cleanup.dart';
import 'package:um_ar_admin/data/repositories/repository_exception.dart';
import 'package:um_ar_admin/data/repositories/room_repository.dart';
import 'package:um_ar_admin/domain/models/facility_model.dart';
import 'package:um_ar_admin/domain/models/indoor_node_model.dart';
import 'package:um_ar_admin/domain/models/room_model.dart';

import 'support/fake_postgrest.dart';

void main() {
  late FakePostgrest db;

  Map<String, dynamic> node(String id, int? link, String? table) =>
      db.tables['indoor_nodes']!.firstWhere((n) => n['id'] == id);

  Object? linkOf(String id) => node(id, null, null)['linked_room_id'];
  Object? tableOf(String id) => node(id, null, null)['linked_table'];

  setUp(() {
    db = FakePostgrest()..install();
    db.tables['rooms'] = [
      {'id': 1, 'roomname': 'Lab', 'building_id': 7, 'is_active': true},
      {'id': 2, 'roomname': 'Other', 'building_id': 8, 'is_active': true},
    ];
    db.tables['facilities'] = [
      {'id': 1, 'roomname': 'Clinic', 'building_id': 7, 'is_active': true},
    ];
    db.tables['buildings'] = [
      {'id': 7, 'name': 'Main', 'is_active': true},
    ];
    db.tables['indoor_nodes'] = [
      {'id': 'to-room', 'linked_room_id': 1, 'linked_table': 'rooms'},
      {'id': 'legacy', 'linked_room_id': 1, 'linked_table': null},
      // Same number, different table: must survive room 1 going away.
      {'id': 'to-facility', 'linked_room_id': 1, 'linked_table': 'facilities'},
      {'id': 'unrelated', 'linked_room_id': 2, 'linked_table': 'rooms'},
    ];
  });
  tearDown(FakePostgrest.uninstall);

  group('deleting a room', () {
    test('clears links to it, including legacy null linked_table', () async {
      await RoomRepository().delete(1);
      expect(linkOf('to-room'), isNull);
      expect(tableOf('to-room'), isNull);
      expect(linkOf('legacy'), isNull);
      expect(db.tables['rooms'], hasLength(1));
    });

    test('leaves facility links with the same id alone', () async {
      await RoomRepository().delete(1);
      expect(linkOf('to-facility'), 1);
      expect(linkOf('unrelated'), 2);
    });

    test('puts the links back when the delete fails', () async {
      db.failing.add('DELETE rooms');
      await expectLater(RoomRepository().delete(1), throwsA(isA<Object>()));
      expect(linkOf('to-room'), 1);
      expect(tableOf('to-room'), 'rooms');
      expect(linkOf('legacy'), 1);
      expect(tableOf('legacy'), 'rooms');
      expect(db.tables['rooms'], hasLength(2));
    });

    test('fails clearly when RLS silently blocks the delete', () async {
      db.rlsBlockedWrites.add('rooms');
      await expectLater(
        RoomRepository().delete(1),
        throwsA(isA<RepositoryException>()
            .having((e) => e.message, 'message', contains('changed nothing'))),
      );
      expect(linkOf('to-room'), 1, reason: 'links are restored');
    });

    test('nothing happens when RLS blocks the unlink', () async {
      db.rlsBlockedWrites.add('indoor_nodes');
      await expectLater(
        RoomRepository().delete(1),
        throwsA(isA<RepositoryException>()
            .having((e) => e.message, 'message', contains('Nothing was'))),
      );
      expect(db.tables['rooms'], hasLength(2), reason: 'room must stay');
      expect(linkOf('to-room'), 1);
    });

    test('says which nodes are affected if links cannot be restored',
        () async {
      db.failing.add('DELETE rooms');
      var patches = 0;
      db.onRequest = (key) {
        // The first PATCH unlinks; the next one is the restore.
        if (key == 'PATCH indoor_nodes' && ++patches == 2) {
          db.failing.add(key);
        }
      };
      await expectLater(
        RoomRepository().delete(1),
        throwsA(isA<RepositoryException>()
            .having((e) => e.message, 'message', contains('to-room'))),
      );
    });
  });

  group('making a room inactive', () {
    const room = RoomModel(id: 1, roomname: 'Lab', isActive: false);

    test('toggleActive(false) clears links', () async {
      await RoomRepository().toggleActive(1, false);
      expect(linkOf('to-room'), isNull);
      expect(linkOf('legacy'), isNull);
      expect(db.tables['rooms']!.first['is_active'], isFalse);
    });

    test('saving the form with Active off clears links', () async {
      await RoomRepository().update(room);
      expect(linkOf('to-room'), isNull);
      expect(db.tables['rooms']!.first['is_active'], isFalse);
    });

    test('toggleActive(true) touches no links', () async {
      await RoomRepository().toggleActive(1, true);
      expect(linkOf('to-room'), 1);
      expect(db.requestCount('PATCH indoor_nodes'), 0);
    });

    test('a failed save puts the links back', () async {
      db.failing.add('PATCH rooms');
      await expectLater(
          RoomRepository().toggleActive(1, false), throwsA(isA<Object>()));
      expect(linkOf('to-room'), 1);
    });

    test('linkedNodeCount gives the number for the warning', () async {
      expect(await RoomRepository().linkedNodeCount(1), 2);
      expect(await RoomRepository().linkedNodeCount(2), 1);
      expect(await RoomRepository().linkedNodeCount(99), 0);
    });
  });

  group('facilities', () {
    test('deleting clears only facility links', () async {
      await FacilityRepository().delete(1);
      expect(linkOf('to-facility'), isNull);
      expect(linkOf('to-room'), 1);
      expect(linkOf('legacy'), 1);
    });

    test('saving inactive clears only facility links', () async {
      await FacilityRepository()
          .update(1, const FacilityModel(id: 1, isActive: false));
      expect(linkOf('to-facility'), isNull);
      expect(linkOf('to-room'), 1);
    });

    test('saving active touches no links', () async {
      await FacilityRepository().update(1, const FacilityModel(id: 1));
      expect(linkOf('to-facility'), 1);
    });
  });

  group('deleting a building', () {
    test('clears links to its rooms and facilities', () async {
      await BuildingRepository().delete(7);
      expect(linkOf('to-room'), isNull);
      expect(linkOf('to-facility'), isNull);
      expect(linkOf('unrelated'), 2, reason: 'room 2 is in another building');
    });

    test('puts every link back when the delete fails', () async {
      db.failing.add('DELETE buildings');
      await expectLater(
          BuildingRepository().delete(7), throwsA(isA<Object>()));
      expect(linkOf('to-room'), 1);
      expect(linkOf('to-facility'), 1);
    });
  });

  group('links that are already broken', () {
    const room = RoomModel(id: 1, roomname: 'Lab');
    const facility = FacilityModel(id: 5);

    IndoorNodeModel n(String id, String? link, String? table) =>
        IndoorNodeModel(id: id, linkedRoomId: link, linkedTable: table);

    test('danglingLinkedNodes finds links with no active target', () {
      final found = danglingLinkedNodes(
        [
          n('fine', '1', 'rooms'),
          n('fine-legacy', '1', null),
          n('fine-facility', '5', 'facilities'),
          n('gone', '9', 'rooms'),
          n('wrong-table', '5', 'rooms'),
          n('no-link', null, null),
          n('empty-link', '', null),
        ],
        [room],
        [facility],
      );
      expect(found.map((x) => x.id), ['gone', 'wrong-table']);
    });

    test('clearNodeLinks removes the link and keeps the node', () async {
      await FloorPlanRepository().clearNodeLinks(['to-room', 'legacy']);
      expect(linkOf('to-room'), isNull);
      expect(linkOf('legacy'), isNull);
      expect(db.tables['indoor_nodes'], hasLength(4));
    });

    test('clearNodeLinks reports RLS blocking the update', () async {
      db.rlsBlockedWrites.add('indoor_nodes');
      await expectLater(
        FloorPlanRepository().clearNodeLinks(['to-room']),
        throwsA(isA<RepositoryException>()),
      );
    });
  });
}
