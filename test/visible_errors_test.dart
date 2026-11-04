import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/core/utils/ui_helpers.dart';
import 'package:um_ar_admin/data/repositories/building_repository.dart';
import 'package:um_ar_admin/data/repositories/facility_repository.dart';
import 'package:um_ar_admin/data/repositories/floor_plan_repository.dart';
import 'package:um_ar_admin/data/repositories/node_repository.dart';
import 'package:um_ar_admin/data/repositories/outdoor_ar_repository.dart';
import 'package:um_ar_admin/data/repositories/repository_exception.dart';
import 'package:um_ar_admin/data/repositories/user_repository.dart';
import 'package:um_ar_admin/presentation/screens/buildings/buildings_screen.dart';
import 'package:um_ar_admin/presentation/screens/rooms/rooms_screen.dart';
import 'package:um_ar_admin/presentation/screens/users/users_screen.dart';
import 'package:um_ar_admin/presentation/widgets/error_banner.dart';

import 'support/fake_postgrest.dart';

/// Puts [screen] on a window big enough for its tables.
Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
}

/// Lets the fake server answer; the screens' loads are several awaits deep.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

void main() {
  late FakePostgrest db;

  setUp(() {
    db = FakePostgrest()..install();
  });
  tearDown(FakePostgrest.uninstall);

  group('repositories do not hide failures', () {
    test('entrance nodes throw instead of returning an empty list', () async {
      db.failing.add('GET outdoor_nodes');
      await expectLater(
        NodeRepository().getEntranceNodesForBuilding(1),
        throwsA(isA<RepositoryException>().having(
            (e) => e.message, 'message', contains('entrance nodes'))),
      );
    });

    test('facilities do not fall back to a list without details', () async {
      db.failing.add('GET facilities');
      await expectLater(
        FacilityRepository().getAll(),
        throwsA(isA<RepositoryException>().having(
            (e) => e.message, 'message', contains('server exploded'))),
      );
      expect(db.requestCount('GET facilities'), 1);
    });

    test('a failed page is not returned as a shorter list', () async {
      db.tables['buildings'] = [
        for (var i = 1; i <= 1500; i++) {'id': i, 'name': 'B$i'},
      ];
      var gets = 0;
      db.onRequest = (key) {
        if (key == 'GET buildings' && ++gets == 2) db.failing.add(key);
      };
      await expectLater(
          BuildingRepository().getAll(), throwsA(isA<RepositoryException>()));
    });
  });

  group('writes blocked by RLS are not reported as success', () {
    const blocked = 'changed nothing';
    Matcher failsWith(String text) => throwsA(isA<RepositoryException>()
        .having((e) => e.message, 'message', contains(text)));

    test('building delete', () async {
      db.tables['buildings'] = [
        {'id': 1, 'name': 'B'},
      ];
      db.rlsBlockedWrites.add('buildings');
      await expectLater(BuildingRepository().delete(1), failsWith(blocked));
    });

    test('floor plan delete', () async {
      db.tables['building_floors'] = [
        {'id': 1},
      ];
      db.rlsBlockedWrites.add('building_floors');
      await expectLater(FloorPlanRepository().delete(1), failsWith(blocked));
    });

    test('AR node delete', () async {
      db.tables['outdoor_ar_nodes'] = [
        {'id': 'a'},
      ];
      db.rlsBlockedWrites.add('outdoor_ar_nodes');
      await expectLater(
          OutdoorArRepository().deleteNode('a'), failsWith(blocked));
    });

    test('outdoor node link', () async {
      db.tables['outdoor_nodes'] = [
        {'id': 'a'},
      ];
      db.rlsBlockedWrites.add('outdoor_nodes');
      await expectLater(
          NodeRepository().setIndoorLink('a', 'b'), failsWith(blocked));
    });

    test('user approval', () async {
      db.tables['user_profiles'] = [
        {'id': 'a'},
      ];
      db.rlsBlockedWrites.add('user_profiles');
      await expectLater(UserRepository().approveUser('a'), failsWith(blocked));
    });
  });

  group('ErrorBanner', () {
    testWidgets('shows the message and a working Retry', (tester) async {
      var retries = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ErrorBanner(
            message: 'Could not load rooms',
            onRetry: () => retries++,
          ),
        ),
      ));
      expect(find.text('Could not load rooms'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('can label its action', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ErrorBanner(
              message: 'x', retryLabel: 'Clear links', onRetry: () {}),
        ),
      ));
      expect(find.text('Clear links'), findsOneWidget);
    });
  });

  group('showError', () {
    Future<BuildContext> pumpContext(WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (c) {
            context = c;
            return const SizedBox();
          }),
        ),
      ));
      return context;
    }

    testWidgets('offers Retry when given a callback', (tester) async {
      final context = await pumpContext(tester);
      var retries = 0;
      context.showError('Failed to save room', onRetry: () => retries++);
      await tester.pumpAndSettle();
      expect(find.text('Failed to save room'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('stays up until handled when it has a Retry', (tester) async {
      final context = await pumpContext(tester);
      context.showError('Failed to save room', onRetry: () {});
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(find.text('Failed to save room'), findsOneWidget);
    });

    testWidgets('has no Retry for plain validation messages', (tester) async {
      final context = await pumpContext(tester);
      context.showError('Select a building');
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
    });
  });

  group('screens', () {
    testWidgets('a failed room load shows why and recovers on Retry',
        (tester) async {
      db.tables['buildings'] = [
        {'id': 1, 'name': 'Main', 'is_active': true},
      ];
      db.tables['rooms'] = [
        {'id': 1, 'roomname': 'Lab', 'building_id': 1, 'is_active': true},
      ];
      db.failing.add('GET rooms');

      await pumpScreen(tester, const RoomsScreen());
      await settle(tester);
      expect(find.textContaining('Failed to load rooms'), findsOneWidget);
      expect(find.text('Lab'), findsNothing);
      expect(find.text('No records found'), findsNothing,
          reason: 'a failure must not look like an empty list');

      db.failing.clear();
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(find.text('Lab'), findsOneWidget);
      expect(find.textContaining('Failed to load rooms'), findsNothing);
    });

    testWidgets('a failed building load shows why and offers Retry',
        (tester) async {
      db.failing.add('GET buildings');
      await pumpScreen(tester, const BuildingsScreen());
      await settle(tester);
      expect(find.textContaining('Failed to load buildings'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No buildings found'), findsNothing);
    });

    testWidgets('a failed user load shows why and offers Retry',
        (tester) async {
      db.failing.add('GET user_profiles');
      await pumpScreen(tester, const UsersScreen());
      await settle(tester);
      expect(find.textContaining('Failed to load users'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    group('the Users screen', () {
      void seedUsers() {
        db.tables['user_profiles'] = [
          {
            'id': 'fac',
            'full_name': 'Ana Faculty',
            'email': 'ana@umindanao.edu.ph',
            'role': 'faculty',
            'is_verified': false,
            'is_active': true,
          },
          {
            'id': 'stu',
            'full_name': 'Ben Student',
            'email': 'b.student.123456@umindanao.edu.ph',
            'role': 'student',
            'is_verified': false,
            'is_active': true,
          },
        ];
      }

      testWidgets('lists pending accounts and approves one', (tester) async {
        seedUsers();
        await pumpScreen(tester, const UsersScreen());
        await settle(tester);
        expect(find.text('Pending Approval (1)'), findsOneWidget);

        await tester.tap(find.byTooltip('Approve'));
        await settle(tester);
        expect(db.tables['user_profiles']!.first['is_verified'], isTrue);
        expect(find.textContaining('Pending Approval'), findsNothing);
      });

      testWidgets('rejects a pending account after confirming',
          (tester) async {
        seedUsers();
        await pumpScreen(tester, const UsersScreen());
        await settle(tester);

        await tester.tap(find.byTooltip('Reject'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Reject'));
        await settle(tester);
        final row = db.tables['user_profiles']!.first;
        expect(row['is_active'], isFalse);
        expect(row['is_verified'], isFalse);
        expect(find.textContaining('Pending Approval'), findsNothing);
      });

      testWidgets('a failed approval shows why, with Retry', (tester) async {
        seedUsers();
        await pumpScreen(tester, const UsersScreen());
        await settle(tester);

        db.failing.add('PATCH user_profiles');
        await tester.tap(find.byTooltip('Approve'));
        await settle(tester);
        expect(find.textContaining('Approving the account failed'),
            findsOneWidget);

        db.failing.clear();
        await tester.pumpAndSettle(); // the snackbar slides in
        await tester.tap(find.text('Retry'));
        await settle(tester);
        expect(db.tables['user_profiles']!.first['is_verified'], isTrue);
      });
    });

    testWidgets('deactivating a linked room warns, then clears the link',
        (tester) async {
      db.tables['buildings'] = [
        {'id': 1, 'name': 'Main', 'is_active': true},
      ];
      db.tables['rooms'] = [
        {'id': 1, 'roomname': 'Lab', 'building_id': 1, 'is_active': true},
      ];
      db.tables['indoor_nodes'] = [
        {'id': 'n1', 'linked_room_id': 1, 'linked_table': 'rooms'},
      ];
      await pumpScreen(tester, const RoomsScreen());
      await settle(tester);

      await tester.tap(find.byTooltip('Deactivate'));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('1 floor plan node points'), findsOneWidget);

      await tester.tap(find.text('Unlink and deactivate'));
      await settle(tester);
      expect(db.tables['rooms']!.single['is_active'], isFalse);
      expect(db.tables['indoor_nodes']!.single['linked_room_id'], isNull);
      expect(find.text('Lab'), findsNothing, reason: 'now hidden by the filter');
    });

    testWidgets('cancelling the warning changes nothing', (tester) async {
      db.tables['buildings'] = [
        {'id': 1, 'name': 'Main', 'is_active': true},
      ];
      db.tables['rooms'] = [
        {'id': 1, 'roomname': 'Lab', 'building_id': 1, 'is_active': true},
      ];
      db.tables['indoor_nodes'] = [
        {'id': 'n1', 'linked_room_id': 1, 'linked_table': 'rooms'},
      ];
      await pumpScreen(tester, const RoomsScreen());
      await settle(tester);

      await tester.tap(find.byTooltip('Deactivate'));
      await settle(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(db.tables['rooms']!.single['is_active'], isTrue);
      expect(db.tables['indoor_nodes']!.single['linked_room_id'], 1);
    });

    testWidgets('the Rooms screen hides inactive rooms until filtered',
        (tester) async {
      db.tables['buildings'] = [
        {'id': 1, 'name': 'Main', 'is_active': true},
      ];
      db.tables['rooms'] = [
        {'id': 1, 'roomname': 'Lab', 'building_id': 1, 'is_active': true},
        {'id': 2, 'roomname': 'Closed', 'building_id': 1, 'is_active': false},
      ];
      await pumpScreen(tester, const RoomsScreen());
      await settle(tester);
      expect(find.text('Lab'), findsOneWidget);
      expect(find.text('Closed'), findsNothing);

      await tester.tap(find.text('Active').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactive').last);
      await settle(tester);
      expect(find.text('Closed'), findsOneWidget);
      expect(find.text('Lab'), findsNothing);
    });
  });
}
