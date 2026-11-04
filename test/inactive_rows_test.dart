import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/data/repositories/building_repository.dart';
import 'package:um_ar_admin/data/repositories/facility_repository.dart';
import 'package:um_ar_admin/data/repositories/paged_query.dart';
import 'package:um_ar_admin/data/repositories/room_repository.dart';
import 'package:um_ar_admin/domain/models/building_model.dart';

import 'support/fake_postgrest.dart';

void main() {
  late FakePostgrest db;

  setUp(() {
    db = FakePostgrest()..install();
    db.tables['buildings'] = [
      {'id': 1, 'name': 'Open', 'is_active': true},
      {'id': 2, 'name': 'Closed', 'is_active': false},
      {'id': 3, 'name': 'Legacy', 'is_active': null},
    ];
    db.tables['rooms'] = [
      {'id': 1, 'roomname': 'A', 'building_id': 1, 'is_active': true},
      {'id': 2, 'roomname': 'B', 'building_id': 1, 'is_active': false},
    ];
    db.tables['facilities'] = [
      {'id': 1, 'roomname': 'Clinic', 'building_id': 1, 'is_active': true},
      {'id': 2, 'roomname': 'Old', 'building_id': 1, 'is_active': false},
    ];
  });
  tearDown(FakePostgrest.uninstall);

  group('repositories hide inactive rows unless asked', () {
    test('buildings default to active, and null counts as active', () async {
      final names = [
        for (final b in await BuildingRepository().getAll()) b.name,
      ];
      expect(names, unorderedEquals(['Open', 'Legacy']));
    });

    test('buildings: inactive and all are explicit choices', () async {
      final repo = BuildingRepository();
      final inactive = await repo.getAll(status: ActiveFilter.inactive);
      expect(inactive.map((b) => b.name), ['Closed']);
      expect(await repo.getAll(status: ActiveFilter.all), hasLength(3));
    });

    test('rooms default to active', () async {
      final repo = RoomRepository();
      expect((await repo.getAll()).map((r) => r.roomname), ['A']);
      expect((await repo.getByBuilding(1)).map((r) => r.roomname), ['A']);
    });

    test('rooms: inactive and all are explicit choices', () async {
      final repo = RoomRepository();
      final inactive = await repo.getByBuilding(1,
          status: ActiveFilter.inactive);
      expect(inactive.map((r) => r.roomname), ['B']);
      expect(await repo.getAll(status: ActiveFilter.all), hasLength(2));
    });

    test('facilities default to active', () async {
      final repo = FacilityRepository();
      expect((await repo.getAll()).map((f) => f.roomname), ['Clinic']);
    });

    test('the node link dropdown never offers inactive facilities', () async {
      final facilities = await FacilityRepository().getByBuilding(1);
      expect(facilities.map((f) => f.roomname), ['Clinic']);
      expect(facilities.single.isActive, isTrue);
    });

    test('facilities: inactive is an explicit choice', () async {
      final inactive =
          await FacilityRepository().getAll(status: ActiveFilter.inactive);
      expect(inactive.map((f) => f.roomname), ['Old']);
    });
  });

  group('building pickers', () {
    const open = BuildingModel(id: 1, name: 'Open');
    const closed = BuildingModel(id: 2, name: 'Closed', isActive: false);

    test('offer only active buildings', () {
      expect(selectableBuildings([open, closed], null), [open]);
    });

    test('keep the inactive building a row is already attached to', () {
      expect(selectableBuildings([open, closed], 2), [open, closed]);
      expect(selectableBuildings([open, closed], 1), [open]);
    });

    test('label an inactive option so it is never silent', () {
      expect(buildingOptionLabel(open), 'Open');
      expect(buildingOptionLabel(closed), 'Closed (inactive)');
    });
  });
}
