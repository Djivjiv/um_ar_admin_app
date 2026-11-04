import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/core/utils/excel_export.dart';
import 'package:um_ar_admin/core/utils/navigation_metrics.dart';
import 'package:um_ar_admin/core/utils/trip_export.dart';
import 'package:um_ar_admin/data/repositories/analytics_repository.dart';
import 'package:um_ar_admin/data/repositories/sus_repository.dart';
import 'package:um_ar_admin/domain/models/feedback_comment_model.dart';
import 'package:um_ar_admin/domain/models/sus_response_model.dart';
import 'package:um_ar_admin/presentation/screens/analytics/navigation_metrics_section.dart';

import 'support/fake_postgrest.dart';

var _id = 1;

Map<String, dynamic> _start(
  String trip, {
  String? mode = 'ar',
  String? user,
  String? device = 'raw-device-code',
  String at = '2026-03-10T09:30:00',
  num? distance = 120,
  int? steps = 10,
}) =>
    {
      'id': _id++,
      'trip_id': trip,
      'row_type': 'start',
      'mode': mode,
      'user_id': user,
      'device_code': device,
      'started_at': at,
      'distance_meters': distance,
      'total_steps': steps,
      'to_name': 'a.student.123@umindanao.edu.ph',
      'completed': false,
      'off_route_tracked': null,
      'error_count': null,
      'reroute_count': null,
      'completed_manually': null,
      'duration_seconds': null,
    };

Map<String, dynamic> _end(
  String trip, {
  String? mode = 'ar',
  String? user,
  String? device = 'raw-device-code',
  String at = '2026-03-10T09:30:00',
  bool completed = true,
  bool manual = false,
  int? seconds = 90,
  int? errors = 3,
  int? reroutes = 1,
  bool tracked = true,
  int? steps = 10,
}) =>
    {
      ..._start(trip, mode: mode, user: user, device: device, at: at),
      'row_type': 'end',
      'total_steps': steps,
      'completed': completed,
      'completed_manually': manual,
      'duration_seconds': seconds,
      'error_count': errors,
      'reroute_count': reroutes,
      'off_route_tracked': tracked,
    };

/// A cell of [rows] by column name, on row [row] (1 = first data row).
Object? cell(List<List<Object?>> rows, String column, [int row = 1]) =>
    rows[row][rows.first.indexOf(column)];

void main() {
  group('tripExportRows', () {
    test('has every requested column', () {
      expect(tripExportRows([], []).single, [
        'trip_id',
        'date',
        'mode',
        'user_type',
        'anonymous_device_id',
        'completed',
        'completed_manually',
        'duration_seconds',
        'distance_meters',
        'error_count',
        'reroute_count',
        'off_route_events',
        'total_steps',
        'sus_score',
      ]);
    });

    test('one row per trip, not one per database row', () {
      final rows = tripExportRows([
        _start('a'), _end('a'),
        _start('b'),
      ], []);
      expect(rows, hasLength(3), reason: 'a header and two trips');
    });

    test('older rows with no trip_id are left out', () {
      final rows = tripExportRows([
        {..._start('x'), 'trip_id': null, 'row_type': null},
        {..._start('y'), 'trip_id': null},
        {..._start('z'), 'trip_id': ''},
      ], []);
      expect(rows, hasLength(1), reason: 'just the header');
    });

    test('fills a finished trip from both of its rows', () {
      final rows = tripExportRows([_start('a'), _end('a')], []);
      expect(cell(rows, 'trip_id'), 'a');
      expect(cell(rows, 'date'), '2026-03-10 09:30');
      expect(cell(rows, 'mode'), 'AR');
      expect(cell(rows, 'completed'), true);
      expect(cell(rows, 'completed_manually'), false);
      expect(cell(rows, 'duration_seconds'), 90);
      expect(cell(rows, 'distance_meters'), 120);
      expect(cell(rows, 'error_count'), 3);
      expect(cell(rows, 'reroute_count'), 1);
      expect(cell(rows, 'off_route_events'), 2);
      expect(cell(rows, 'total_steps'), 10);
    });

    test('mode reads 2D or AR', () {
      final rows = tripExportRows(
          [_start('a', mode: '2d'), _start('b', mode: null)], []);
      expect(cell(rows, 'mode', 1), '2D');
      expect(cell(rows, 'mode', 2), 'Unknown');
    });

    test('user type is signed-in or visitor', () {
      final rows = tripExportRows([
        _start('a', user: 'u1'),
        _start('b'),
        {..._start('c'), 'is_visitor': false},
      ], []);
      expect(cell(rows, 'user_type', 1), 'signed-in');
      expect(cell(rows, 'user_type', 2), 'visitor');
      expect(cell(rows, 'user_type', 3), 'signed-in');
    });

    test('the device is the short id, the same one Suggestions uses', () {
      final rows = tripExportRows([_start('a')], []);
      expect(cell(rows, 'anonymous_device_id'), anonymousId('raw-device-code'));
    });

    test('never holds a raw device code, user id or email', () {
      final text = tripExportRows([
        _start('a', user: 'real-user-id'),
        _end('a', user: 'real-user-id'),
      ], []).expand((r) => r).join(' ');
      expect(text, isNot(contains('raw-device-code')));
      expect(text, isNot(contains('real-user-id')));
      expect(text, isNot(contains('@')));
    });

    test('no device code leaves the column empty', () {
      final rows = tripExportRows([_start('a', device: null)], []);
      expect(cell(rows, 'anonymous_device_id'), '');
    });

    test('an unknown distance stays empty, not 0', () {
      final rows = tripExportRows([_start('a', distance: 0)], []);
      expect(cell(rows, 'distance_meters'), isNull);
    });

    test('the error columns stay empty on an untracked trip', () {
      final rows = tripExportRows([
        _start('a'), _end('a', tracked: false),
      ], []);
      expect(cell(rows, 'error_count'), isNull);
      expect(cell(rows, 'reroute_count'), isNull);
      expect(cell(rows, 'off_route_events'), isNull);
    });

    test('a trip with no end row has no outcome figures', () {
      final rows = tripExportRows([_start('a')], []);
      expect(cell(rows, 'completed'), false);
      expect(cell(rows, 'duration_seconds'), isNull);
      expect(cell(rows, 'total_steps'), 10, reason: 'from the start row');
    });

    test('a left-early trip keeps its duration', () {
      final rows = tripExportRows([
        _start('a'), _end('a', completed: false, seconds: 40),
      ], []);
      expect(cell(rows, 'completed'), false);
      expect(cell(rows, 'duration_seconds'), 40);
    });

    test('a manual arrival is marked', () {
      final rows = tripExportRows([_start('a'), _end('a', manual: true)], []);
      expect(cell(rows, 'completed_manually'), true);
    });

    test('links the SUS score by trip', () {
      final rows = tripExportRows([
        _start('a'), _start('b'),
      ], [
        {'id': 1, 'sus_score': 72.5, 'navigation_session_id': 'b'},
      ]);
      expect(cell(rows, 'sus_score', 1), isNull);
      expect(cell(rows, 'sus_score', 2), 72.5);
    });
  });

  group('summaryExportRows', () {
    List<List<Object?>> summary() => summaryExportRows(
          computeNavigationMetrics(
            [
              _start('a'), _end('a', errors: 2, reroutes: 1, steps: 10),
              _start('b', mode: '2d'),
              _end('b', mode: '2d', manual: true, errors: 0, reroutes: 0),
              _start('c', user: 'v1'), _end('c', user: 'v1', errors: 0,
                  reroutes: 0, seconds: 30),
              _start('d', user: 'other'), _end('d', user: 'other'),
            ],
            [
              {'id': 1, 'sus_score': 80, 'navigation_session_id': 'a'},
              {'id': 2, 'sus_score': 60, 'user_id': 'v1'},
            ],
            verifiedUserIds: {'v1'},
          ),
          range: '2026-03-01 to 2026-03-31',
        );

    List<Object?> row(List<List<Object?>> rows, String group) =>
        rows.firstWhere((r) => r.isNotEmpty && r.first == group);

    Object? value(List<List<Object?>> rows, String group, String column) =>
        row(rows, group)[rows.first.indexOf(column)];

    test('has all trips, each mode and both user groups', () {
      final groups = [for (final r in summary()) if (r.isNotEmpty) r.first];
      expect(groups, containsAllInOrder(
          ['Group', 'All trips', 'AR', '2D', 'Visitors', 'Verified users']));
    });

    test('gives each figure per mode', () {
      final rows = summary();
      expect(value(rows, 'AR', 'Trips'), 3);
      expect(value(rows, 'AR', 'Completion rate (%)'), 100);
      expect(value(rows, '2D', 'GPS-only arrivals'), 0);
      expect(value(rows, '2D', 'GPS-only rate (%)'), 0);
      expect(value(rows, '2D', 'Manual arrivals'), 1);
      expect(value(rows, 'AR', 'Average SUS'), 80);
    });

    test('rates are percentages, rounded to one place', () {
      final rows = summary();
      expect(value(rows, 'All trips', 'GPS-only rate (%)'), 75);
      expect(value(rows, 'All trips', 'Errors per step (%)'), 12.5);
    });

    test('the comparison is on the sheet', () {
      final rows = summary();
      expect(value(rows, 'Visitors', 'Trips'), 2);
      expect(value(rows, 'Verified users', 'Trips'), 1);
      expect(value(rows, 'Verified users', 'Average time (s)'), 30);
      expect(value(rows, 'Verified users', 'Average SUS'), 60);
    });

    test('says what the groups mean and what is left out', () {
      final text = summary().expand((r) => r).join(' ');
      expect(text, contains('Visitor = no user_id'));
      expect(text, contains('in neither group: 1'));
      expect(text, contains('2026-03-01 to 2026-03-31'));
    });
  });

  group('the workbook', () {
    test('holds both sheets, in order, and no empty default sheet', () {
      final bytes = buildExcelBytes(const [
        ExcelSheetData('Trips', [
          ['trip_id', 'completed'],
          ['a', true],
        ]),
        ExcelSheetData('Summary', [
          ['Group', 'Trips'],
          ['All trips', 1],
          [''],
          ['A note'],
        ]),
      ])!;
      final book = Excel.decodeBytes(bytes);
      expect(book.tables.keys, ['Trips', 'Summary']);
      final summary = book.tables['Summary']!.rows;
      expect(summary[1][0]?.value.toString(), 'All trips');
      expect(summary[3][0]?.value.toString(), 'A note');
      expect(book.tables['Trips']!.rows[1][0]?.value.toString(), 'a');
    });

    test('the summary keeps its blank line before the notes', () {
      final rows = summaryExportRows(const NavigationMetrics(), range: 'x');
      final bytes = buildExcelBytes([ExcelSheetData('Summary', rows)])!;
      final sheet = Excel.decodeBytes(bytes).tables['Summary']!.rows;
      final blank = rows.indexWhere((r) => r.length == 1 && r.single == '');
      expect(blank, greaterThan(0));
      expect(sheet[blank + 1][0]?.value.toString(), 'Range: x');
      expect(sheet, hasLength(rows.length));
    });

    test('a single sheet still works', () {
      final bytes = buildExcelBytes(const [
        ExcelSheetData('Users', [
          ['name'],
        ]),
      ])!;
      expect(Excel.decodeBytes(bytes).tables.keys, ['Users']);
    });

    test('the repository builds Trips and Summary', () async {
      final db = FakePostgrest()..install();
      addTearDown(FakePostgrest.uninstall);
      db.tables['navigation_sessions'] = [_start('a'), _end('a')];
      db.tables['sus_responses'] = [
        {
          'id': 1,
          'sus_score': 70,
          'user_id': 'u',
          'navigation_session_id': 'a',
          'submitted_at': '2026-03-10T10:00:00',
        },
        {
          'id': 2,
          'sus_score': 10,
          'user_id': 'u',
          'navigation_session_id': 'a',
          'submitted_at': '2026-03-11T10:00:00',
        },
      ];
      final sheets = await AnalyticsRepository()
          .exportTripWorkbook(rangeLabel: 'all time');
      expect(sheets.map((s) => s.name), ['Trips', 'Summary']);
      expect(cell(sheets.first.rows, 'sus_score'), 70,
          reason: 'one SUS per person: the first answer counts');
      expect(sheets.last.rows.expand((r) => r).join(' '), contains('all time'));
    });
  });

  group('SUS export', () {
    SusResponseModel response(Map<String, dynamic> row) =>
        SusResponseModel.fromJson({'id': 1, ...row});

    test('adds the anonymous id, the trip, the user type and the mode', () {
      final rows = susExportRows([
        response({
          'device_code': 'raw-device-code',
          'navigation_session_id': 't1',
          'user_type': 'visitor',
        }),
      ], {
        't1': 'AR',
      });
      expect(cell(rows, 'anonymous_device_id'), anonymousId('raw-device-code'));
      expect(cell(rows, 'navigation_session_id'), 't1');
      expect(cell(rows, 'mode'), 'AR');
      expect(cell(rows, 'user_type'), 'visitor');
      expect(cell(rows, 'role'), 'visitor');
    });

    test('never holds the raw device code', () {
      final text = susExportRows([
        response({'device_code': 'raw-device-code'}),
      ], const {}).expand((r) => r).join(' ');
      expect(text, isNot(contains('raw-device-code')));
    });

    test('the identifying columns are only the requested ones', () {
      final header = susExportRows(const [], const {}).single;
      expect(header, isNot(contains('user_id')));
      expect(header, isNot(contains('visitor_session_id')));
      expect(header, isNot(contains('id')));
      expect(header.take(5), [
        'anonymous_device_id',
        'navigation_session_id',
        'mode',
        'user_type',
        'role',
      ]);
    });

    test('no raw account or session id reaches a cell', () {
      final text = susExportRows([
        response({
          'id': 'raw-row-id',
          'user_id': 'raw-user-id',
          'visitor_session_id': 'raw-session-id',
        }),
      ], const {}).expand((r) => r).join(' ');
      expect(text, isNot(contains('raw-row-id')));
      expect(text, isNot(contains('raw-user-id')));
      expect(text, isNot(contains('raw-session-id')));
    });

    test('the Trips sheet holds no raw account or session id either', () {
      final rows = tripExportRows([
        {
          ..._start('a', user: 'raw-user-id'),
          'visitor_session_id': 'raw-session-id',
        },
      ], []);
      expect(rows.first, isNot(contains('user_id')));
      expect(rows.first, isNot(contains('visitor_session_id')));
      final text = rows.expand((r) => r).join(' ');
      expect(text, isNot(contains('raw-user-id')));
      expect(text, isNot(contains('raw-session-id')));
    });

    test('user type is signed-in or visitor, role is kept apart', () {
      final rows = susExportRows([
        response({'user_id': 'u1', 'user_type': 'student'}),
      ], const {});
      expect(cell(rows, 'user_type'), 'signed-in');
      expect(cell(rows, 'role'), 'student');
    });

    test('an answer with no linked trip has no mode', () {
      final rows = susExportRows([response({})], {'t1': 'AR'});
      expect(cell(rows, 'mode'), '');
    });

    group('from the database', () {
      late FakePostgrest db;

      setUp(() => db = FakePostgrest()..install());
      tearDown(FakePostgrest.uninstall);

      Map<String, dynamic> sus(int id, String at, {String? device}) => {
            'id': id,
            'device_code': device ?? 'phone',
            'navigation_session_id': 't1',
            'sus_score': 70,
            'submitted_at': at,
          };

      test('keeps one SUS per person', () async {
        db.tables['sus_responses'] = [
          sus(1, '2026-03-10T10:00:00'),
          sus(2, '2026-03-11T10:00:00'),
          sus(3, '2026-03-11T10:00:00', device: 'other'),
        ];
        final rows = await SusRepository().exportRows();
        expect(rows, hasLength(3), reason: 'a header and two people');
      });

      test('takes the mode from the linked trip', () async {
        db.tables['sus_responses'] = [sus(1, '2026-03-10T10:00:00')];
        db.tables['navigation_sessions'] = [_start('t1', mode: '2d')];
        expect(cell(await SusRepository().exportRows(), 'mode'), '2D');
      });

      test('with no trips table the export still works', () async {
        db.tables['sus_responses'] = [sus(1, '2026-03-10T10:00:00')];
        db.failing.add('GET navigation_sessions');
        db.failureCode = 'PGRST205';
        expect(cell(await SusRepository().exportRows(), 'mode'), '');
      });
    });
  });

  group('visitors vs verified users', () {
    NavigationMetrics compute() => computeNavigationMetrics(
          [
            _start('v'), _end('v', seconds: 60, errors: 1, reroutes: 0),
            _start('w'),
            _start('good', user: 'ok'),
            _end('good', user: 'ok', seconds: 120, errors: 2, reroutes: 0),
            _start('bad', user: 'pending'),
            _end('bad', user: 'pending', seconds: 999, errors: 9, reroutes: 0),
          ],
          [
            {'id': 1, 'sus_score': 40, 'device_code': 'phone'},
            {'id': 2, 'sus_score': 90, 'user_id': 'ok'},
            {'id': 3, 'sus_score': 10, 'user_id': 'pending'},
          ],
          verifiedUserIds: {'ok'},
        );

    test('a visitor is a trip with no user_id', () {
      final c = compute().comparison;
      expect(c.visitors.trips, 2);
      expect(c.visitors.completionRate, 0.5);
      expect(c.visitors.averageSeconds, 60);
      expect(c.visitors.errorRate, 0.1);
      expect(c.visitors.averageSus, 40);
    });

    test('verified is signed in with is_verified true', () {
      final c = compute().comparison;
      expect(c.verified.trips, 1);
      expect(c.verified.completionRate, 1);
      expect(c.verified.averageSeconds, 120);
      expect(c.verified.errorRate, 0.2);
      expect(c.verified.averageSus, 90);
    });

    test('a signed-in account that is not verified is in neither', () {
      expect(compute().comparison.otherSignedInTrips, 1);
    });

    test('is_visitor decides when the column exists', () {
      final c = computeNavigationMetrics([
        {..._start('a', user: 'ok'), 'is_visitor': true},
      ], [], verifiedUserIds: {'ok'}).comparison;
      expect(c.visitors.trips, 1);
      expect(c.verified.trips, 0);
    });

    test('an empty group has no rates, not 0', () {
      final c = computeNavigationMetrics([], []).comparison;
      expect(c.visitors.trips, 0);
      expect(c.visitors.completionRate, isNull);
      expect(c.verified.errorRate, isNull);
    });

    test('the repository reads is_verified', () async {
      final db = FakePostgrest()..install();
      addTearDown(FakePostgrest.uninstall);
      db.tables['user_profiles'] = [
        {'id': 'yes', 'is_verified': true},
        {'id': 'no', 'is_verified': false},
        {'id': 'null', 'is_verified': null},
      ];
      db.tables['navigation_sessions'] = [
        _start('a', user: 'yes'),
        _start('b', user: 'no'),
        _start('c', user: 'null'),
      ];
      final c = (await AnalyticsRepository().getNavigationMetrics()).comparison;
      expect(c.verified.trips, 1);
      expect(c.otherSignedInTrips, 2);
    });

    testWidgets('the table shows both groups', (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NavigationMetricsSection(metrics: compute()),
          ),
        ),
      ));
      expect(find.text('Visitors vs Verified Users'), findsOneWidget);
      expect(find.text('Visitors'), findsOneWidget);
      expect(find.text('Verified users'), findsOneWidget);
      expect(find.text('Completion rate'), findsOneWidget);
      expect(find.text('2m 00s'), findsOneWidget);
      expect(find.text('90.0'), findsOneWidget);
      expect(find.textContaining('Visitor = no user_id'), findsOneWidget);
      expect(find.textContaining('1 trip by signed-in accounts'),
          findsOneWidget);
    });
  });
}
