import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/data/repositories/analytics_repository.dart';
import 'package:um_ar_admin/data/repositories/dashboard_repository.dart';
import 'package:um_ar_admin/data/repositories/kiosk_repository.dart';
import 'package:um_ar_admin/data/repositories/repository_exception.dart';
import 'package:um_ar_admin/domain/models/feedback_comment_model.dart';
import 'package:um_ar_admin/domain/models/kiosk_session_model.dart';
import 'package:um_ar_admin/presentation/screens/analytics/analytics_screen.dart';
import 'package:um_ar_admin/presentation/screens/dashboard/dashboard_screen.dart';
import 'package:um_ar_admin/presentation/screens/kiosk/kiosk_management_screen.dart';

import 'support/fake_postgrest.dart';

final _day = DateTime(2026, 3, 10);

String _on(DateTime day, {int hour = 12}) =>
    DateTime(day.year, day.month, day.day, hour).toUtc().toIso8601String();

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
  await settle(tester);
}

Map<String, dynamic> _nav(
  String trip, {
  String? user,
  String? device,
  required String at,
}) =>
    {
      'id': trip,
      'trip_id': trip,
      'row_type': 'start',
      'user_id': user,
      'device_code': device,
      'started_at': at,
    };

void main() {
  late FakePostgrest db;

  setUp(() => db = FakePostgrest()..install());
  tearDown(FakePostgrest.uninstall);

  group('Dashboard comments', () {
    Map<String, dynamic> comment(
      int id,
      String text, {
      String? role = 'student',
      String? user = 'user-1',
      String? device,
      DateTime? day,
    }) =>
        {
          'id': id,
          'comment': text,
          'rating_context': 'sus',
          'role': role,
          'user_id': user,
          'device_code': device,
          'created_at': _on(day ?? _day),
        };

    test('reads feedback_comments', () async {
      db.tables['feedback_comments'] = [comment(1, 'Great map')];
      final entries = await DashboardRepository().getComments(_day);
      expect(entries.single.text, 'Great map');
      expect(entries.single.userType, 'Student');
    });

    test('no longer reads comments from sus_responses', () async {
      db.tables['sus_responses'] = [
        {'id': 1, 'comment': 'old', 'submitted_at': _on(_day)},
      ];
      expect(await DashboardRepository().getComments(_day), isEmpty);
      expect(db.requestCount('GET sus_responses'), 0);
    });

    test('is anonymised as on the Suggestions screen', () async {
      db.tables['feedback_comments'] = [
        comment(1, 'Mail me at a.student.123@umindanao.edu.ph please'),
      ];
      final entry = (await DashboardRepository().getComments(_day)).single;
      expect(entry.text, isNot(contains('umindanao')));
      expect(entry.text, contains('[email removed]'));
      expect(entry.anonymousRef, anonymousId('user-1'));
      expect(entry.anonymousRef, isNot('user-1'));
    });

    test('a visitor is identified by the hash of device_code', () async {
      db.tables['feedback_comments'] = [
        comment(1, 'Hi', role: 'visitor', user: null, device: 'dev-1'),
      ];
      final entry = (await DashboardRepository().getComments(_day)).single;
      expect(entry.userType, 'Visitor');
      expect(entry.anonymousRef, anonymousId('dev-1'));
    });

    test('a row with no role reads Unknown role', () async {
      db.tables['feedback_comments'] = [comment(1, 'Hi', role: null)];
      final entry = (await DashboardRepository().getComments(_day)).single;
      expect(entry.userType, 'Unknown role');
    });

    test('keeps only the picked day', () async {
      db.tables['feedback_comments'] = [
        comment(1, 'that day'),
        comment(2, 'next day', day: _day.add(const Duration(days: 1))),
      ];
      final entries = await DashboardRepository().getComments(_day);
      expect(entries.map((e) => e.text), ['that day']);
    });

    test('a comment late on the day counts', () async {
      db.tables['feedback_comments'] = [
        {...comment(1, 'late'), 'created_at': _on(_day, hour: 23)},
      ];
      expect(await DashboardRepository().getComments(_day), hasLength(1));
    });

    test('kiosk comments come from kiosk_survey_responses', () async {
      db.tables['kiosk_survey_responses'] = [
        {
          'id': 1,
          'comments': 'Nice kiosk, write to me@mail.com',
          'created_at': _on(_day),
        },
        {'id': 2, 'comments': '  ', 'created_at': _on(_day)},
      ];
      final entry = (await DashboardRepository().getComments(_day)).single;
      expect(entry.userType, 'Kiosk');
      expect(entry.text, 'Nice kiosk, write to [email removed]');
      expect(entry.anonymousRef, isNull);
      expect(db.requestCount('GET kiosk_sus_responses'), 0);
    });

    test('tables not created yet give no comments, not an error', () async {
      db.failing
        ..add('GET feedback_comments')
        ..add('GET kiosk_survey_responses');
      db.failureCode = 'PGRST205';
      expect(await DashboardRepository().getComments(_day), isEmpty);
    });

    test('a failed read is an error, not an empty day', () async {
      db.failing.add('GET feedback_comments');
      await expectLater(DashboardRepository().getComments(_day),
          throwsA(isA<RepositoryException>()));
    });
  });

  group('Dashboard SUS summary', () {
    test('kiosk surveys are counted apart from SUS', () async {
      db.tables['sus_responses'] = [
        {'id': 1, 'sus_score': 80, 'user_id': 'u'},
      ];
      db.tables['kiosk_survey_responses'] = [
        {'id': 1, 'overall_rating': 5},
        {'id': 2, 'overall_rating': 1},
      ];
      final s = await DashboardRepository().getSusSummary();
      expect(s.totalResponses, 1, reason: 'a 1 to 5 rating is not a SUS score');
      expect(s.kioskSurveys, 2);
      expect(s.averageScore, 80);
      expect(db.requestCount('GET kiosk_sus_responses'), 0);
    });

    test('no kiosk table is 0 surveys, not an error', () async {
      db.failing.add('HEAD kiosk_survey_responses');
      db.failureCode = 'PGRST205';
      final s = await DashboardRepository().getSusSummary();
      expect(s.kioskSurveys, 0);
    });

    test('any other failed count is still an error', () async {
      db.failing.add('HEAD kiosk_survey_responses');
      await expectLater(DashboardRepository().getSusSummary(),
          throwsA(isA<RepositoryException>()));
    });
  });

  test('top stats survive a kiosk_sessions table not created yet', () async {
    db.failing.add('HEAD kiosk_sessions');
    db.failureCode = 'PGRST205';
    expect((await DashboardRepository().getTopStats()).kioskUsers, 0);
  });

  group('System status', () {
    Map<String, dynamic> row(String id, bool? active) =>
        {'id': id, 'is_active': active};

    test('counts only active nodes and floors', () async {
      db.tables['outdoor_nodes'] = [
        row('o1', true), row('o2', null), row('o3', false),
      ];
      db.tables['indoor_nodes'] = [row('i1', true), row('i2', false)];
      db.tables['building_floors'] = [row('f1', false), row('f2', true)];
      final s = await DashboardRepository().getSystemStatus();
      expect(s.totalOutdoorNodes, 2, reason: 'null counts as active');
      expect(s.totalIndoorNodes, 1);
      expect(s.totalFloorPlans, 1);
    });

    test('a failed count still says Could not load', () async {
      db.failing.add('HEAD indoor_nodes');
      final s = await DashboardRepository().getSystemStatus();
      expect(s.totalIndoorNodes, isNull);
      expect(s.errors.join(), contains('indoor nodes'));
    });
  });

  group('Dashboard screen', () {
    testWidgets('keeps trips and kiosk sessions on separate charts',
        (tester) async {
      await pumpScreen(tester, const DashboardScreen());
      expect(find.text('Daily Trips'), findsOneWidget);
      expect(find.text('Signed-in trips'), findsOneWidget);
      expect(find.text('Visitor trips'), findsOneWidget);
      expect(find.text('Daily Kiosk Sessions'), findsOneWidget);
      expect(find.text('Kiosk sessions'), findsOneWidget);
      expect(find.text('Visitor sessions'), findsNothing);
    });

    testWidgets('labels the status counts as active', (tester) async {
      await pumpScreen(tester, const DashboardScreen());
      expect(find.text('Active Outdoor Nodes'), findsOneWidget);
      expect(find.text('Active Indoor Nodes'), findsOneWidget);
      expect(find.text('Active Floor Plans'), findsOneWidget);
    });

    testWidgets('does not pass kiosk surveys off as SUS', (tester) async {
      db.tables['kiosk_survey_responses'] = [
        {'id': 1},
      ];
      await pumpScreen(tester, const DashboardScreen());
      expect(find.textContaining('1 kiosk survey (not SUS)'), findsOneWidget);
      expect(find.textContaining('App + kiosk'), findsNothing);
    });

    testWidgets('a comment shows its short id and not the real one',
        (tester) async {
      db.tables['feedback_comments'] = [
        {
          'id': 1,
          'comment': 'Great map',
          'role': 'student',
          'user_id': 'user-1',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
      ];
      await pumpScreen(tester, const DashboardScreen());
      expect(find.text('Great map'), findsOneWidget);
      expect(find.text(anonymousId('user-1')), findsOneWidget);
      expect(find.text('user-1'), findsNothing);
    });
  });

  group('summarizePeople', () {
    final roles = {'s': 'student', 'f': 'Faculty', 'none': null, 'blank': ' '};

    Map<String, double> count(List<Map<String, dynamic>> rows) => {
          for (final p in summarizePeople(rows, roles).points) p.label: p.value,
        };

    test('one person with many rows counts once', () {
      expect(
        count([
          {'user_id': 's'},
          {'user_id': 's', 'device_code': 'phone'},
          {'user_id': 's'},
        ]),
        {'student': 1},
      );
    });

    test('one device with many visitor sessions counts once', () {
      expect(
        count([
          {'device_code': 'phone'},
          {'device_code': 'phone'},
          {'device_code': 'other'},
        ]),
        {'visitor': 2},
      );
    });

    test('accounts with role visitor add to the visitors, not vanish', () {
      final points = summarizePeople([
        {'user_id': 'v'},
        {'device_code': 'phone'},
      ], {
        'v': 'visitor',
      }).points;
      expect(points.single.label, 'visitor');
      expect(points.single.value, 2);
    });

    test('an account with no role reads No role yet', () {
      expect(
        count([
          {'user_id': 'none'},
          {'user_id': 'blank'},
          {'user_id': 'not-in-profiles'},
        ]),
        {kNoRoleLabel: 3},
      );
      expect(kNoRoleLabel, 'No role yet');
    });

    test('roles group whatever their case', () {
      expect(
        count([
          {'user_id': 'f'},
        ]),
        {'faculty': 1},
      );
    });

    test('rows with neither id are reported, not counted', () {
      final d = summarizePeople([
        {'id': 1},
        {'id': 2, 'user_id': '', 'device_code': ''},
      ], roles);
      expect(d.points, isEmpty);
      expect(d.rowsWithoutPerson, 2);
    });
  });

  group('getUserDistribution', () {
    final inside = DateTime(2026, 3, 10);
    final outside = DateTime(2026, 5, 10);
    final from = DateTime(2026, 3, 1);
    final to = DateTime(2026, 4, 1);

    Future<Map<String, double>> load() async {
      final d =
          await AnalyticsRepository().getUserDistribution(from: from, to: to);
      return {for (final p in d.points) p.label: p.value};
    }

    setUp(() {
      db.tables['user_profiles'] = [
        {'id': 'a', 'role': 'student'},
        {'id': 'b', 'role': 'faculty'},
        {'id': 'c', 'role': null},
        {'id': 'idle', 'role': 'employee'},
      ];
    });

    test('only people active in the range count', () async {
      db.tables['navigation_sessions'] = [
        _nav('1', user: 'a', at: _on(inside)),
        _nav('2', user: 'b', at: _on(outside)),
      ];
      expect(await load(), {'student': 1},
          reason: 'faculty b was outside the range, employee never came');
    });

    test('a visitor device with two sessions is one person', () async {
      db.tables['visitor_sessions'] = [
        {'id': 's1', 'device_code': 'phone', 'started_at': _on(inside)},
        {'id': 's2', 'device_code': 'phone', 'started_at': _on(inside)},
        {'id': 's3', 'device_code': 'away', 'started_at': _on(outside)},
      ];
      expect(await load(), {'visitor': 1});
    });

    test('an old session row counts by device_id', () async {
      db.tables['visitor_sessions'] = [
        {'id': 's1', 'device_id': 'phone', 'started_at': _on(inside)},
      ];
      expect(await load(), {'visitor': 1});
    });

    test('someone who only answered the SUS counts', () async {
      db.tables['sus_responses'] = [
        {'id': 1, 'user_id': 'c', 'submitted_at': _on(inside)},
      ];
      expect(await load(), {kNoRoleLabel: 1});
    });

    test('someone in several tables counts once', () async {
      db.tables['navigation_sessions'] = [
        _nav('1', device: 'phone', at: _on(inside)),
      ];
      db.tables['sus_responses'] = [
        {'id': 1, 'device_code': 'phone', 'submitted_at': _on(inside)},
      ];
      db.tables['visitor_sessions'] = [
        {'id': 's', 'device_code': 'phone', 'started_at': _on(inside)},
      ];
      expect(await load(), {'visitor': 1});
    });

    test('a missing sus_responses table is not a failure', () async {
      db.tables['navigation_sessions'] = [
        _nav('1', user: 'a', at: _on(inside)),
      ];
      db.failing.add('GET sus_responses');
      db.failureCode = 'PGRST205';
      expect(await load(), {'student': 1});
    });

    test('a failed read is an error', () async {
      db.failing.add('GET navigation_sessions');
      await expectLater(load(), throwsA(isA<RepositoryException>()));
    });
  });

  group('Analytics screen', () {
    testWidgets('states what the notes promise', (tester) async {
      await pumpScreen(tester, const AnalyticsScreen());
      expect(find.textContaining('ignores trips with a distance of 0'),
          findsOneWidget);
      expect(find.textContaining('one per user_id, or per device_code'),
          findsOneWidget);
    });
  });

  group('kiosk columns', () {
    test('reads destinations_viewed, as the kiosk writes it', () {
      final s = KioskSessionModel.fromJson(
          {'id': 'k', 'destinations_viewed': 4, 'buildings_viewed': 99});
      expect(s.destinationsViewed, 4);
    });

    test('the usage total adds destinations_viewed', () async {
      db.tables['kiosk_sessions'] = [
        {
          'id': 'k1',
          'started_at': _on(_day),
          'destinations_viewed': 3,
          'buildings_viewed': 50,
        },
        {'id': 'k2', 'started_at': _on(_day), 'destinations_viewed': 2},
      ];
      final a = await KioskRepository().getSessionAnalytics(
        from: _day,
        to: _day.add(const Duration(days: 1)),
      );
      expect(a.totalDestinationViews, 5);
    });

    testWidgets('the survey switch does not claim to be SUS', (tester) async {
      db.tables['kiosk_settings'] = [
        {'id': 1, 'is_survey_enabled': true},
      ];
      await pumpScreen(tester, const KioskManagementScreen());
      expect(find.text('Post-navigation survey enabled'), findsOneWidget);
      expect(find.textContaining('SUS'), findsNothing);
    });

    testWidgets('neither does the preview', (tester) async {
      db.tables['kiosk_settings'] = [
        {'id': 1, 'is_survey_enabled': true},
      ];
      await pumpScreen(tester, const KioskManagementScreen());
      await tester.tap(find.text('Preview'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Survey shown at the end of a session'), findsOneWidget);
      expect(find.textContaining('SUS'), findsNothing);
    });
  });
}
