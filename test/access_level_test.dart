import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:um_ar_admin/data/repositories/facility_repository.dart';
import 'package:um_ar_admin/data/repositories/paged_query.dart';
import 'package:um_ar_admin/data/repositories/repository_exception.dart';
import 'package:um_ar_admin/data/repositories/room_repository.dart';
import 'package:um_ar_admin/domain/models/access_level.dart';
import 'package:um_ar_admin/domain/models/facility_model.dart';
import 'package:um_ar_admin/domain/models/room_model.dart';
import 'package:um_ar_admin/presentation/widgets/access_level_fields.dart';

import 'support/fake_postgrest.dart';

void main() {
  group('values', () {
    test('are the three levels, public first', () {
      expect(kAccessLevels, ['public', 'students_and_faculty', 'staff_only']);
      expect(kDefaultAccessLevel, 'public');
    });

    test('labels read well, and empty means public', () {
      expect(accessLevelLabel('public'), 'Public');
      expect(accessLevelLabel('students_and_faculty'), 'Students & Faculty');
      expect(accessLevelLabel('staff_only'), 'Staff Only');
      expect(accessLevelLabel(null), 'Public');
      expect(accessLevelLabel('  '), 'Public');
    });

    test('an older free-text value is shown as typed', () {
      expect(accessLevelLabel('Faculty only'), 'Faculty only');
    });

    test('a form starts on the stored value, else the default', () {
      expect(selectedAccessLevel(null), 'public');
      expect(selectedAccessLevel(''), 'public');
      expect(selectedAccessLevel('staff_only'), 'staff_only');
      expect(selectedAccessLevel('Faculty only'), 'Faculty only');
    });

    test('an older value stays a choice, so opening a form keeps it', () {
      expect(accessLevelOptions('staff_only'), kAccessLevels);
      expect(accessLevelOptions(null), kAccessLevels);
      expect(accessLevelOptions('Faculty only'),
          [...kAccessLevels, 'Faculty only']);
    });

    test('the default is not written over a row with no value', () {
      expect(accessLevelToSave('public', null), isNull);
      expect(accessLevelToSave('public', ''), isNull);
    });

    test('a real choice, or a move back to public, is written', () {
      expect(accessLevelToSave('staff_only', null), 'staff_only');
      expect(accessLevelToSave('public', 'staff_only'), 'public');
      expect(accessLevelToSave('Faculty only', 'Faculty only'), 'Faculty only');
    });
  });

  group('models', () {
    test('read access_level, and tolerate the column being absent', () {
      expect(
          FacilityModel.fromJson({'access_level': 'staff_only'}).accessLevel,
          'staff_only');
      expect(FacilityModel.fromJson({}).accessLevel, isNull);
      expect(RoomModel.fromJson({'roomname': 'A', 'access_level': 'public'})
          .accessLevel, 'public');
    });

    test('null is left out of saves, so they work before the SQL has run', () {
      expect(const FacilityModel().facilityJson(),
          isNot(contains('access_level')));
      expect(const RoomModel(roomname: 'A').toJson(),
          isNot(contains('access_level')));
    });

    test('a value is saved', () {
      expect(
          const FacilityModel(accessLevel: 'staff_only')
              .facilityJson()['access_level'],
          'staff_only');
      expect(
          const RoomModel(roomname: 'A', accessLevel: 'staff_only')
              .toJson()['access_level'],
          'staff_only');
    });
  });

  group('filters', () {
    late FakePostgrest db;

    setUp(() {
      db = FakePostgrest()..install();
      db.tables['rooms'] = [
        {'id': 1, 'roomname': 'Open', 'building_id': 1, 'access_level': 'public'},
        {'id': 2, 'roomname': 'Empty', 'building_id': 1, 'access_level': null},
        {'id': 3, 'roomname': 'Staff', 'building_id': 1, 'access_level': 'staff_only'},
        {'id': 4, 'roomname': 'Old', 'building_id': 1, 'access_level': 'Faculty only'},
        {'id': 5, 'roomname': 'Gone', 'building_id': 1, 'access_level': 'staff_only', 'is_active': false},
      ];
      db.tables['facilities'] = [
        {'id': 1, 'roomname': 'Clinic', 'building_id': 1},
        {'id': 2, 'roomname': 'HR', 'building_id': 1, 'access_level': 'staff_only'},
        {'id': 3, 'roomname': 'Library', 'building_id': 2, 'access_level': 'students_and_faculty'},
      ];
    });
    tearDown(FakePostgrest.uninstall);

    test('no filter returns every level', () async {
      expect(await RoomRepository().getAll(), hasLength(4));
    });

    test('public includes rows with no value', () async {
      final rooms = await RoomRepository().getAll(accessLevel: 'public');
      expect(rooms.map((r) => r.roomname), unorderedEquals(['Open', 'Empty']));
    });

    test('a level matches exactly and still respects the status filter',
        () async {
      final repo = RoomRepository();
      final active = await repo.getAll(accessLevel: 'staff_only');
      expect(active.map((r) => r.roomname), ['Staff']);
      final all = await repo.getAll(
          accessLevel: 'staff_only', status: ActiveFilter.all);
      expect(all, hasLength(2));
    });

    test('rooms of one building can be filtered', () async {
      final rooms =
          await RoomRepository().getByBuilding(1, accessLevel: 'staff_only');
      expect(rooms.map((r) => r.roomname), ['Staff']);
    });

    test('facilities filter, alone and with a building', () async {
      final repo = FacilityRepository();
      final staff = await repo.getAll(accessLevel: 'staff_only');
      expect(staff.map((f) => f.roomname), ['HR']);
      final public = await repo.getAll(accessLevel: 'public');
      expect(public.map((f) => f.roomname), ['Clinic']);
      final none =
          await repo.getAll(accessLevel: 'staff_only', buildingId: 2);
      expect(none, isEmpty);
    });

    test('a missing column says which SQL file to run', () async {
      db.failing.add('GET rooms');
      db.failureCode = '42703';
      db.failureMessage = 'column rooms.access_level does not exist';
      await expectLater(
        RoomRepository().getAll(accessLevel: 'staff_only'),
        throwsA(isA<RepositoryException>().having(
            (e) => e.message, 'message', contains('db/access_level.sql'))),
      );
    });

    test('saving a level before the SQL has run says the same', () async {
      db.failing.add('PATCH facilities');
      db.failureCode = 'PGRST204';
      db.failureMessage = "Could not find the 'access_level' column";
      await expectLater(
        FacilityRepository()
            .update(1, const FacilityModel(accessLevel: 'staff_only')),
        throwsA(isA<RepositoryException>().having(
            (e) => e.message, 'message', contains('db/access_level.sql'))),
      );
    });

    test('saving a level writes it; saving the default leaves it alone',
        () async {
      await FacilityRepository()
          .update(1, const FacilityModel(accessLevel: 'staff_only'));
      expect(db.tables['facilities']!.first['access_level'], 'staff_only');

      await RoomRepository().update(const RoomModel(id: 4, roomname: 'Old'));
      expect(db.tables['rooms']![3]['access_level'], 'Faculty only');
    });
  });

  test('isMissingColumn ignores other errors', () {
    expect(
      isMissingColumn(
          const PostgrestException(message: 'x access_level', code: '42501'),
          'access_level'),
      isFalse,
    );
    expect(
      isMissingColumn(
          const PostgrestException(message: 'column y', code: '42703'),
          'access_level'),
      isFalse,
    );
  });

  group('form field', () {
    Future<void> pump(WidgetTester tester, String value, String? stored) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: AccessLevelField(
              value: value,
              stored: stored,
              onChanged: (_) {},
            ),
          ),
        ));

    testWidgets('warns when a value will show on the mobile AR card',
        (tester) async {
      await pump(tester, 'staff_only', 'staff_only');
      expect(find.textContaining('Access: staff_only'), findsOneWidget);
    });

    testWidgets('says nothing for public', (tester) async {
      await pump(tester, 'public', null);
      expect(find.textContaining('mobile AR card'), findsNothing);
    });

    testWidgets('shows an older value instead of crashing', (tester) async {
      await pump(tester, 'Faculty only', 'Faculty only');
      expect(find.text('Faculty only'), findsOneWidget);
    });
  });
}
