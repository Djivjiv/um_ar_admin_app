import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/data/repositories/dashboard_repository.dart';
import 'package:um_ar_admin/data/repositories/repository_exception.dart';
import 'package:um_ar_admin/data/repositories/visitor_session_repository.dart';
import 'package:um_ar_admin/domain/models/visitor_session_model.dart';
import 'package:um_ar_admin/presentation/screens/users/users_screen.dart';
import 'package:um_ar_admin/presentation/screens/visitor_sessions/visitor_sessions_screen.dart';

import 'support/fake_postgrest.dart';

var _id = 1;

Map<String, dynamic> _start(
  String trip, {
  String? session,
  String? device = 'dev-1',
  String? user,
  String at = '2026-03-10T09:00:00Z',
  String to = 'Library',
}) =>
    {
      'id': _id++,
      'trip_id': trip,
      'row_type': 'start',
      'mode': 'ar',
      'user_id': user,
      'visitor_session_id': session,
      'device_code': device,
      'from_name': 'Gate',
      'to_name': to,
      'distance_meters': 120,
      'started_at': at,
      'completed': false,
    };

Map<String, dynamic> _end(
  String trip, {
  String? session,
  String? device = 'dev-1',
  bool completed = true,
  bool manual = false,
  String at = '2026-03-10T09:00:00Z',
  String to = 'Library',
}) =>
    {
      ..._start(trip, session: session, device: device, at: at, to: to),
      'row_type': 'end',
      'completed': completed,
      'completed_manually': manual,
    };

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

Future<void> pumpScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: VisitorSessionsScreen())));
  await settle(tester);
}

/// Taps [text]'s table row and waits for the panel and its history.
Future<void> openRow(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await settle(tester);
}

void main() {
  late FakePostgrest db;

  setUp(() => db = FakePostgrest()..install());
  tearDown(FakePostgrest.uninstall);

  group('who counts as an active visitor', () {
    final now = DateTime.utc(2026, 3, 10, 12);
    final later = now.add(const Duration(hours: 1));
    final earlier = now.subtract(const Duration(hours: 1));

    VisitorSessionModel session(bool expired, DateTime? expires) =>
        VisitorSessionModel(id: 's', isExpired: expired, expiresAt: expires);

    test('live: not expired, and expires in the future', () {
      expect(session(false, later).isActiveAt(now), isTrue);
    });

    test('a session left to run out is not active, though is_expired is false',
        () {
      expect(session(false, earlier).isActiveAt(now), isFalse);
    });

    test('a session marked expired is not active, whatever the time', () {
      expect(session(true, later).isActiveAt(now), isFalse);
    });

    test('no expires_at is not active', () {
      expect(session(false, null).isActiveAt(now), isFalse);
    });

    test('expiring this very moment is not active', () {
      expect(session(false, now).isActiveAt(now), isFalse);
    });

    test('the Dashboard and the Visitor screen agree', () async {
      String at(Duration d) => DateTime.now().toUtc().add(d).toIso8601String();
      const hour = Duration(hours: 1);
      db.tables['visitor_sessions'] = [
        {'id': 'live', 'is_expired': false, 'expires_at': at(hour)},
        {'id': 'null-flag', 'is_expired': null, 'expires_at': at(hour)},
        {'id': 'ran-out', 'is_expired': false, 'expires_at': at(-hour)},
        {'id': 'ended', 'is_expired': true, 'expires_at': at(hour)},
      ];
      final stats = await DashboardRepository().getTopStats();
      final sessions = await VisitorSessionRepository().getAll();
      expect(stats.activeVisitors, 2);
      expect(sessions.where((s) => s.isActive).length, stats.activeVisitors);
      expect(stats.activeUsers, 2, reason: 'no accounts, just the visitors');
    });
  });

  group('device code', () {
    test('device_code is read first', () {
      final s = VisitorSessionModel.fromJson(
          {'id': 's', 'device_code': 'new', 'device_id': 'old'});
      expect(s.deviceCode, 'new');
    });

    test('a row from before device_code falls back to device_id', () {
      final s =
          VisitorSessionModel.fromJson({'id': 's', 'device_id': 'old'});
      expect(s.deviceCode, 'old');
    });
  });

  group('offlineVisitorEntries', () {
    test('one entry per device, whatever the number of rows', () {
      final entries = offlineVisitorEntries([
        _start('a'), _end('a'), _start('b'),
        {'id': 1, 'device_code': 'dev-1', 'submitted_at': '2026-03-11'},
      ]);
      expect(entries.single.deviceCode, 'dev-1');
      expect(entries.single.isOffline, isTrue);
    });

    test('a signed-in row is not an offline visitor', () {
      expect(offlineVisitorEntries([_start('a', user: 'u')]), isEmpty);
    });

    test('is_visitor wins over user_id when the column exists', () {
      expect(
          offlineVisitorEntries([
            {..._start('a'), 'is_visitor': false},
          ]),
          isEmpty);
    });

    test('a row with no device_code cannot be identified', () {
      expect(offlineVisitorEntries([_start('a', device: null)]), isEmpty);
      expect(offlineVisitorEntries([_start('a', device: '  ')]), isEmpty);
    });

    test('keeps the first and last time seen', () {
      final entry = offlineVisitorEntries([
        _start('b', at: '2026-03-12T09:00:00Z'),
        _start('a', at: '2026-03-10T09:00:00Z'),
        _start('c', at: '2026-03-14T09:00:00Z'),
      ]).single;
      expect(entry.startedAt!.toUtc(), DateTime.utc(2026, 3, 10, 9));
      expect(entry.lastSeenAt!.toUtc(), DateTime.utc(2026, 3, 14, 9));
    });
  });

  group('getEntries', () {
    test('lists sessions and offline visitors, newest first', () async {
      db.tables['visitor_sessions'] = [
        {'id': 's1', 'device_code': 'online', 'started_at': '2026-03-11T09:00:00Z'},
      ];
      db.tables['navigation_sessions'] = [
        _start('a', device: 'offline', at: '2026-03-12T09:00:00Z'),
        _start('b', session: 's1', device: 'online'),
        _start('c', user: 'u', device: 'phone'),
      ];
      final entries = await VisitorSessionRepository().getEntries();
      expect(entries.map((e) => (e.deviceCode, e.statusLabel)),
          [('offline', 'Offline'), ('online', 'Expired')]);
    });

    test('finds a visitor who only answered the SUS', () async {
      db.tables['sus_responses'] = [
        {
          'id': 1,
          'device_code': 'sus-only',
          'user_id': null,
          'visitor_session_id': null,
          'submitted_at': '2026-03-10T09:00:00Z',
        },
      ];
      final entry = (await VisitorSessionRepository().getEntries()).single;
      expect(entry.deviceCode, 'sus-only');
      expect(entry.isOffline, isTrue);
      expect(entry.startedAt!.toUtc(), DateTime.utc(2026, 3, 10, 9));
    });

    test('a device in both tables is one visitor', () async {
      db.tables['navigation_sessions'] = [_start('a')];
      db.tables['sus_responses'] = [
        {'id': 1, 'device_code': 'dev-1', 'submitted_at': '2026-03-10'},
      ];
      expect(await VisitorSessionRepository().getEntries(), hasLength(1));
    });

    test('sessions still load when sus_responses does not exist', () async {
      db.tables['navigation_sessions'] = [_start('a')];
      db.failing.add('GET sus_responses');
      db.failureCode = 'PGRST205';
      expect(await VisitorSessionRepository().getEntries(), hasLength(1));
    });

    test('a failed read is an error, not fewer visitors', () async {
      db.failing.add('GET navigation_sessions');
      await expectLater(VisitorSessionRepository().getEntries(),
          throwsA(isA<RepositoryException>()));
    });

    test('pages past 1000 rows', () async {
      db.tables['navigation_sessions'] = [
        for (var i = 0; i < 1500; i++) _start('t$i', device: 'd$i'),
      ];
      expect(await VisitorSessionRepository().getEntries(), hasLength(1500));
    });
  });

  group('getTripHistory', () {
    final sessionEntry = VisitorEntry.fromSession(
        const VisitorSessionModel(id: 's1', deviceCode: 'dev-1'));
    const offlineEntry = VisitorEntry(deviceCode: 'dev-1');

    test('a finished trip is one line, not two', () async {
      db.tables['navigation_sessions'] = [
        _start('a', session: 's1'), _end('a', session: 's1'),
      ];
      final h = await VisitorSessionRepository().getTripHistory(sessionEntry);
      expect(h.trips, hasLength(1));
      expect(h.trips.single.outcome, 'Completed');
    });

    test('each outcome reads from the end row', () async {
      db.tables['navigation_sessions'] = [
        _start('open', session: 's1', at: '2026-03-13T09:00:00Z'),
        _start('left', session: 's1', at: '2026-03-12T09:00:00Z'),
        _end('left', session: 's1', at: '2026-03-12T09:00:00Z', completed: false),
        _start('hand', session: 's1', at: '2026-03-11T09:00:00Z'),
        _end('hand', session: 's1', at: '2026-03-11T09:00:00Z', manual: true),
      ];
      final h = await VisitorSessionRepository().getTripHistory(sessionEntry);
      expect(h.trips.map((t) => t.outcome),
          ['Not finished', 'Left early', 'Completed (manual)']);
    });

    test('rows with no trip_id are left out and counted', () async {
      db.tables['navigation_sessions'] = [
        _start('a', session: 's1'),
        {..._start('x', session: 's1'), 'trip_id': null, 'row_type': null},
      ];
      final h = await VisitorSessionRepository().getTripHistory(sessionEntry);
      expect(h.trips, hasLength(1));
      expect(h.rowsWithoutTrip, 1);
    });

    test('a session sees only its own trips', () async {
      db.tables['navigation_sessions'] = [
        _start('mine', session: 's1'),
        _start('other', session: 's2'),
      ];
      final h = await VisitorSessionRepository().getTripHistory(sessionEntry);
      expect(h.trips.map((t) => t.start['trip_id']), ['mine']);
    });

    test('an offline visitor is found by device_code alone', () async {
      db.tables['navigation_sessions'] = [
        _start('mine'), _end('mine'),
        _start('other device', device: 'dev-2'),
        _start('signed in on this phone', user: 'u'),
        _start('from a real session', session: 's1'),
      ];
      final h = await VisitorSessionRepository().getTripHistory(offlineEntry);
      expect(h.trips.map((t) => t.start['trip_id']), ['mine']);
      expect(h.trips.single.outcome, 'Completed');
    });
  });

  group('Users screen Visitor box', () {
    Future<void> pumpUsers(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: UsersScreen())));
      await settle(tester);
    }

    void seed() {
      db.tables['visitor_sessions'] = [
        {
          'id': 'session-1',
          'device_code': 'online-phone',
          'started_at': '2026-03-10T09:00:00Z',
          'expires_at': '2026-03-10T11:00:00Z',
        },
      ];
      db.tables['navigation_sessions'] = [
        _start('a', device: 'offline-phone'),
        _end('a', device: 'offline-phone'),
      ];
    }

    testWidgets('lists offline visitors, marked Offline', (tester) async {
      seed();
      await pumpUsers(tester);
      expect(find.text('Visitor Sessions (2)'), findsOneWidget);
      expect(find.text('offline-…'), findsOneWidget);
      expect(find.text('online-p…'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Expired'), findsOneWidget);
    });

    testWidgets('an offline visitor has no session id or duration',
        (tester) async {
      seed();
      await pumpUsers(tester);
      expect(find.text('session-…'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(3),
          reason: 'session id, expiry and duration of the offline row');
    });

    testWidgets('the Offline filter shows only them', (tester) async {
      seed();
      await pumpUsers(tester);
      final dropdowns = find.byWidgetPredicate((w) =>
          w is DropdownButtonFormField<String>);
      await tester.tap(dropdowns.at(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Offline').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Visitor Sessions (1)'), findsOneWidget);
      expect(find.text('offline-…'), findsOneWidget);
      expect(find.text('online-p…'), findsNothing);
    });

    testWidgets('the Expired filter leaves offline visitors out',
        (tester) async {
      seed();
      await pumpUsers(tester);
      final dropdowns = find.byWidgetPredicate((w) =>
          w is DropdownButtonFormField<String>);
      await tester.tap(dropdowns.at(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Expired').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Visitor Sessions (1)'), findsOneWidget);
      expect(find.text('online-p…'), findsOneWidget);
      expect(find.text('offline-…'), findsNothing);
    });

    testWidgets('a missing navigation table does not break the screen',
        (tester) async {
      db.tables['visitor_sessions'] = [
        {'id': 'session-1', 'device_code': 'online-phone'},
      ];
      db.failing.add('GET navigation_sessions');
      db.failureCode = 'PGRST205';
      await pumpUsers(tester);
      expect(find.text('online-p…'), findsOneWidget);
    });
  });

  group('Visitor screen', () {
    testWidgets('marks a visitor with no session row as Offline',
        (tester) async {
      db.tables['navigation_sessions'] = [_start('a', device: 'lonely-phone')];
      await pumpScreen(tester);
      expect(find.text('lonely-p…'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
      expect(find.textContaining('1 offline'), findsOneWidget);
    });

    testWidgets('shows device_code, not device_id', (tester) async {
      db.tables['visitor_sessions'] = [
        {'id': 's1', 'device_code': 'the-code', 'device_id': 'the-old-id'},
      ];
      await pumpScreen(tester);
      expect(find.text('the-code'), findsOneWidget);
      expect(find.text('the-old-id'), findsNothing);
    });

    testWidgets('the detail panel lists one row per trip', (tester) async {
      db.tables['visitor_sessions'] = [
        {'id': 's1', 'device_code': 'the-code'},
      ];
      db.tables['navigation_sessions'] = [
        _start('a', session: 's1', device: 'the-code'),
        _end('a', session: 's1', device: 'the-code'),
      ];
      await pumpScreen(tester);
      await openRow(tester, 'the-code');
      expect(find.text('Gate → Library'), findsOneWidget);
      expect(find.textContaining('120 m · AR · Completed'), findsOneWidget);
      expect(find.textContaining('incomplete'), findsNothing);
    });

    testWidgets('each trip is marked visitor or signed in', (tester) async {
      db.tables['visitor_sessions'] = [
        {'id': 's1', 'device_code': 'the-code'},
      ];
      db.tables['navigation_sessions'] = [
        {..._start('a', session: 's1', device: 'the-code'), 'is_visitor': true},
        {..._start('b', session: 's1', device: 'the-code'), 'is_visitor': false},
      ];
      await pumpScreen(tester);
      await openRow(tester, 'the-code');
      expect(find.textContaining('· Visitor'), findsOneWidget);
      expect(find.textContaining('· Signed in'), findsOneWidget);
    });

    testWidgets('a row from before is_visitor still gets a marker',
        (tester) async {
      db.tables['visitor_sessions'] = [
        {'id': 's1', 'device_code': 'the-code'},
      ];
      db.tables['navigation_sessions'] = [
        _start('a', session: 's1', device: 'the-code'),
      ];
      await pumpScreen(tester);
      await openRow(tester, 'the-code');
      expect(find.textContaining('· Visitor'), findsOneWidget);
    });

    testWidgets('an offline visitor opens by device code', (tester) async {
      db.tables['navigation_sessions'] = [
        _start('a', device: 'lonely-phone'),
        _end('a', device: 'lonely-phone'),
      ];
      await pumpScreen(tester);
      await openRow(tester, 'lonely-p…');
      expect(find.text('Offline Visitor'), findsOneWidget);
      expect(find.text('Gate → Library'), findsOneWidget);
      expect(find.textContaining('No session row'), findsOneWidget);
    });

    testWidgets('Retry on the detail panel reloads after an error',
        (tester) async {
      db.tables['visitor_sessions'] = [
        {'id': 's1', 'device_code': 'the-code'},
      ];
      db.tables['navigation_sessions'] = [_start('a', session: 's1')];
      await pumpScreen(tester);

      db.failing.add('GET navigation_sessions');
      await openRow(tester, 'the-code');
      expect(find.textContaining('server exploded'), findsOneWidget);
      expect(find.text('Gate → Library'), findsNothing);

      db.failing.clear();
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(find.textContaining('server exploded'), findsNothing);
      expect(find.text('Gate → Library'), findsOneWidget);
    });
  });
}
