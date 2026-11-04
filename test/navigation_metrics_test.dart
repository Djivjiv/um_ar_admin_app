import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/core/utils/navigation_metrics.dart';
import 'package:um_ar_admin/data/repositories/analytics_repository.dart';
import 'package:um_ar_admin/data/repositories/repository_exception.dart';
import 'package:um_ar_admin/presentation/screens/analytics/navigation_metrics_section.dart';

import 'support/fake_postgrest.dart';

var _nextId = 1;

/// A start row, as the user app writes it.
Map<String, dynamic> start(String trip, {String? mode = 'ar', int? steps}) => {
      'id': _nextId++,
      'trip_id': trip,
      'row_type': 'start',
      'mode': mode,
      'total_steps': steps,
      'completed': false,
      'duration_seconds': null,
      'error_count': null,
      'reroute_count': null,
      'off_route_tracked': null,
      'completed_manually': null,
    };

/// An end row, as the user app writes it.
Map<String, dynamic> end(
  String trip, {
  bool completed = true,
  int? seconds = 60,
  int? errors = 0,
  int? steps = 10,
  bool tracked = true,
  String? mode = 'ar',
  int? reroutes = 0,
  bool manual = false,
}) =>
    {
      'id': _nextId++,
      'trip_id': trip,
      'row_type': 'end',
      'mode': mode,
      'total_steps': steps,
      'completed': completed,
      'duration_seconds': seconds,
      'error_count': errors,
      'reroute_count': reroutes,
      'off_route_tracked': tracked,
      'completed_manually': manual,
    };

NavigationMetrics compute(List<Map<String, dynamic>> rows,
        [List<Map<String, dynamic>> sus = const []]) =>
    computeNavigationMetrics(rows, sus);

void main() {
  group('trips', () {
    test('start and end rows make one trip, not two', () {
      final m = compute([start('a'), end('a')]);
      expect(m.trips, 1);
    });

    test('a start with no end is a trip that did not complete', () {
      final m = compute([start('a'), start('b'), end('b')]);
      expect(m.trips, 2);
      expect(m.modes.single.completedTrips, 1);
    });

    test('rows without a trip_id are left out', () {
      final m = compute([
        start('a'),
        {'id': 99, 'trip_id': null, 'row_type': null, 'mode': null},
      ]);
      expect(m.trips, 1);
    });

    test('an end row whose start row never arrived is left out', () {
      expect(compute([start('a'), end('other')]).trips, 1);
    });

    test('with duplicate end rows, the newest wins', () {
      final m = compute([
        start('a'),
        {...end('a', seconds: 10), 'id': 1000},
        {...end('a', seconds: 90), 'id': 1001},
      ]);
      expect(m.averageCompletionSeconds, 90);
      expect(m.timedTrips, 1);
    });
  });

  group('error rate', () {
    test('is error_count / total_steps', () {
      final m = compute([start('a'), end('a', errors: 2, steps: 8)]);
      expect(m.errorRate, 0.25);
      expect(m.errorRateTrips, 1);
    });

    test('is the mean per trip, not total errors / total steps', () {
      final m = compute([
        start('a'), end('a', errors: 1, steps: 2), // 0.5
        start('b'), end('b', errors: 0, steps: 98), // 0
      ]);
      expect(m.errorRate, 0.25);
    });

    test('a clean trip counts as zero, not as missing', () {
      final m = compute([start('a'), end('a', errors: 0, steps: 5)]);
      expect(m.errorRate, 0);
    });

    test('abandoned trips count too', () {
      final m = compute([
        start('a'),
        end('a', completed: false, errors: 1, steps: 4),
      ]);
      expect(m.errorRate, 0.25);
    });

    test('untracked trips are ignored', () {
      final m = compute([
        start('a'), end('a', errors: 9, steps: 10, tracked: false),
        start('b'), end('b', errors: 1, steps: 10),
      ]);
      expect(m.errorRate, 0.1);
      expect(m.errorRateTrips, 1);
    });

    test('zero steps cannot divide', () {
      final m = compute([start('a', steps: 0), end('a', errors: 1, steps: 0)]);
      expect(m.errorRate, isNull);
    });

    test('total_steps falls back to the start row', () {
      final m = compute([start('a', steps: 4), end('a', errors: 1, steps: null)]);
      expect(m.errorRate, 0.25);
    });

    test('can pass 100%: it is a rate per step, not a share', () {
      final m = compute([start('a'), end('a', errors: 6, steps: 3)]);
      expect(m.errorRate, 2);
      expect(formatPercent(m.errorRate!), '200.0%');
    });
  });

  group('off-route events', () {
    test('are error_count minus reroute_count, summed over trips', () {
      final m = compute([
        start('a'), end('a', errors: 3, reroutes: 1), // 2 off-route
        start('b'), end('b', errors: 2, reroutes: 2), // 0 off-route
      ]);
      expect(m.offRouteEvents, 2);
      expect(m.reroutes, 3);
      expect(m.offRouteTrips, 2);
    });

    test('one rerouted deviation is 2 errors but 1 off-route event', () {
      final m = compute([start('a'), end('a', errors: 2, reroutes: 1)]);
      expect(m.errorRate, 0.2, reason: 'the error rate keeps error_count');
      expect(m.offRouteEvents, 1);
      expect(m.reroutes, 1);
    });

    test('a clean tracked trip is 0, not missing', () {
      final m = compute([start('a'), end('a')]);
      expect(m.offRouteEvents, 0);
      expect(m.reroutes, 0);
    });

    test('untracked trips are ignored', () {
      final m = compute([
        start('a'), end('a', errors: 9, reroutes: 3, tracked: false),
        start('b'), end('b', errors: 1, reroutes: 0),
      ]);
      expect(m.offRouteEvents, 1);
      expect(m.reroutes, 0);
      expect(m.offRouteTrips, 1);
    });

    test('an old row with more reroutes than errors is 0, not negative', () {
      final m = compute([start('a'), end('a', errors: 1, reroutes: 3)]);
      expect(m.offRouteEvents, 0);
    });

    test('a trip with no reroute_count is left out', () {
      final m = compute([
        start('a'), end('a', errors: 2, reroutes: null),
        start('b'), end('b', errors: 1, reroutes: 1),
      ]);
      expect(m.offRouteEvents, 0);
      expect(m.offRouteTrips, 1);
    });

    test('without reroute_count the figure is no data, the rate stays', () {
      final m = compute([
        {...start('a')}..remove('reroute_count'),
        {...end('a', errors: 2)}..remove('reroute_count'),
      ]);
      expect(m.offRouteEvents, isNull);
      expect(m.reroutes, isNull);
      expect(m.missingForOffRoute, ['reroute_count']);
      expect(m.errorRate, 0.2);
    });
  });

  group('task success', () {
    final rows = [
      start('gps1'), end('gps1'),
      start('gps2'), end('gps2'),
      start('manual'), end('manual', manual: true),
      start('left'), end('left', completed: false),
      start('open'),
    ];

    test('Completion Rate counts every completed trip', () {
      final m = compute(rows);
      expect(m.completedTrips, 3);
      expect(m.completionRate, 0.6);
    });

    test('GPS-only arrivals leaves out manual arrivals', () {
      final m = compute(rows);
      expect(m.gpsArrivals, 2);
      expect(m.gpsArrivalRate, 0.4);
    });

    test('manual arrivals are counted apart', () {
      expect(compute(rows).manualArrivals, 1);
    });

    test('a left-early trip is neither, whatever its flag says', () {
      final m = compute([
        start('a'),
        end('a', completed: false, manual: true),
      ]);
      expect(m.gpsArrivals, 0);
      expect(m.manualArrivals, 0);
    });

    test('only a completed trip can be a manual arrival', () {
      final trip = groupNavigationTrips([
        start('a'),
        end('a', completed: false, manual: true),
      ]).single;
      expect(trip.completedManually, isFalse);
      expect(trip.outcome, 'Left early');
    });

    test('with no trips both rates are no data, not 0', () {
      final m = compute([]);
      expect(m.completionRate, isNull);
      expect(m.gpsArrivalRate, isNull);
    });

    test('without completed_manually only the GPS figure is no data', () {
      final m = compute([
        {...start('a')}..remove('completed_manually'),
        {...end('a')}..remove('completed_manually'),
      ]);
      expect(m.completionRate, 1);
      expect(m.gpsArrivalRate, isNull);
      expect(m.manualArrivals, isNull);
      expect(m.missingForGpsArrivals, ['completed_manually']);
    });
  });

  group('average completion time', () {
    test('averages completed trips', () {
      final m = compute([
        start('a'), end('a', seconds: 60),
        start('b'), end('b', seconds: 120),
      ]);
      expect(m.averageCompletionSeconds, 90);
      expect(m.timedTrips, 2);
    });

    test('leaves out abandoned trips and open trips', () {
      final m = compute([
        start('a'), end('a', seconds: 60),
        start('b'), end('b', seconds: 999, completed: false),
        start('c'),
      ]);
      expect(m.averageCompletionSeconds, 60);
    });

    test('a completed trip with no duration does not count as zero', () {
      final m = compute([
        start('a'), end('a', seconds: 60),
        start('b'), end('b', seconds: null),
      ]);
      expect(m.averageCompletionSeconds, 60);
    });

    test('is null with no completed trips', () {
      expect(compute([start('a')]).averageCompletionSeconds, isNull);
    });
  });

  group('AR vs 2D split', () {
    final rows = [
      start('a'), end('a', seconds: 60, errors: 1, steps: 10),
      start('b'), end('b', seconds: 100, errors: 3, steps: 10),
      start('c'),
      start('d', mode: '2d'), end('d', seconds: 40, errors: 0, steps: 10),
    ];

    test('counts trips and shares, AR first', () {
      final m = compute(rows);
      expect(m.modes.map((x) => x.mode), ['ar', '2d']);
      expect(m.modes[0].trips, 3);
      expect(m.modes[0].share, 0.75);
      expect(m.modes[0].completedTrips, 2);
      expect(m.modes[1].trips, 1);
      expect(m.modes[1].share, 0.25);
    });

    test('computes each metric per mode', () {
      final m = compute(rows);
      expect(m.modes[0].averageSeconds, 80);
      expect(m.modes[0].errorRate, 0.2);
      expect(m.modes[1].averageSeconds, 40);
      expect(m.modes[1].errorRate, 0);
    });

    test('a trip with no mode is Unknown, listed last', () {
      final m = compute([
        start('a', mode: null),
        start('b'),
      ]);
      expect(m.modes.map((x) => x.label), ['AR', 'Unknown']);
    });

    test('mode comes from the start row, ignoring case', () {
      final m = compute([start('a', mode: 'AR'), end('a', mode: null)]);
      expect(m.modes.single.mode, 'ar');
    });
  });

  group('SUS', () {
    final rows = [
      start('a'), end('a'),
      start('b', mode: '2d'), end('b', mode: '2d'),
    ];

    test('averages every score, ignoring nulls', () {
      final m = compute(rows, [
        {'id': 1, 'sus_score': 70, 'navigation_session_id': 'a'},
        {'id': 2, 'sus_score': 90, 'navigation_session_id': null},
        {'id': 3, 'sus_score': null, 'navigation_session_id': null},
      ]);
      expect(m.averageSus, 80);
      expect(m.susResponses, 2);
    });

    test('splits by the mode of the linked trip', () {
      final m = compute(rows, [
        {'id': 1, 'sus_score': 70, 'navigation_session_id': 'a'},
        {'id': 2, 'sus_score': 90, 'navigation_session_id': 'a'},
        {'id': 3, 'sus_score': 50, 'navigation_session_id': 'b'},
        {'id': 4, 'sus_score': 10, 'navigation_session_id': 'not-in-range'},
      ]);
      expect(m.modes[0].averageSus, 80);
      expect(m.modes[1].averageSus, 50);
    });
  });

  group('missing columns', () {
    test('no rows means no data, and nothing is reported missing', () {
      final m = compute([]);
      expect(m.trips, 0);
      expect(m.errorRate, isNull);
      expect(m.averageCompletionSeconds, isNull);
      expect(m.modes, isEmpty);
      expect(m.missingForErrorRate, isEmpty);
    });

    test('a table from before the evaluation SQL gives no metrics', () {
      final m = compute([
        {'id': 1, 'to_name': 'Library', 'completed': true, 'duration_seconds': 5},
      ]);
      expect(m.trips, 0);
      expect(m.averageCompletionSeconds, isNull);
      expect(m.missingForErrorRate, kErrorRateColumns.toSet()
          .difference({'id'}).toList());
      expect(m.missingForCompletionTime, ['trip_id', 'row_type']);
      expect(m.missingForModeSplit, ['trip_id', 'row_type', 'mode']);
    });

    test('one missing column only blanks the metrics that need it', () {
      final rows = [
        {...start('a')}..remove('off_route_tracked'),
        {...end('a')}..remove('off_route_tracked'),
      ];
      final m = compute(rows);
      expect(m.errorRate, isNull);
      expect(m.missingForErrorRate, ['off_route_tracked']);
      expect(m.averageCompletionSeconds, 60);
      expect(m.modes.single.errorRate, isNull);
      expect(m.modes.single.averageSeconds, 60);
    });

    test('without mode the split is empty, not 100% Unknown', () {
      final rows = [
        {...start('a')}..remove('mode'),
      ];
      final m = compute(rows);
      expect(m.trips, 1);
      expect(m.modes, isEmpty);
      expect(m.missingForModeSplit, ['mode']);
    });

    test('sus_responses without the link column keeps the overall score', () {
      final m = compute([start('a'), end('a')], [
        {'id': 1, 'sus_score': 70},
      ]);
      expect(m.averageSus, 70);
      expect(m.missingForSusByMode, ['navigation_session_id']);
      expect(m.modes.single.averageSus, isNull);
    });
  });

  group('formatTripSeconds', () {
    test('picks a readable unit', () {
      expect(formatTripSeconds(45), '45s');
      expect(formatTripSeconds(185), '3m 05s');
      expect(formatTripSeconds(3720), '1h 02m');
      expect(formatTripSeconds(59.6), '1m 00s');
    });
  });

  group('AnalyticsRepository', () {
    late FakePostgrest db;

    setUp(() => db = FakePostgrest()..install());
    tearDown(FakePostgrest.uninstall);

    test('reads both tables and computes', () async {
      db.tables['navigation_sessions'] = [
        {...start('a'), 'started_at': '2026-01-01'},
        {...end('a', seconds: 30), 'started_at': '2026-01-01'},
      ];
      db.tables['sus_responses'] = [
        {'id': 1, 'sus_score': 75, 'submitted_at': '2026-01-01'},
      ];
      final m = await AnalyticsRepository().getNavigationMetrics();
      expect(m.trips, 1);
      expect(m.averageCompletionSeconds, 30);
      expect(m.averageSus, 75);
    });

    test('filters both tables by the date range', () async {
      db.tables['navigation_sessions'] = [
        {...start('in'), 'started_at': '2026-03-01'},
        {...start('out'), 'started_at': '2026-05-01'},
      ];
      db.tables['sus_responses'] = [
        {'id': 1, 'sus_score': 80, 'submitted_at': '2026-03-01'},
        {'id': 2, 'sus_score': 20, 'submitted_at': '2026-05-01'},
      ];
      final m = await AnalyticsRepository().getNavigationMetrics(
        from: DateTime.utc(2026, 2),
        to: DateTime.utc(2026, 4),
      );
      expect(m.trips, 1);
      expect(m.averageSus, 80);
    });

    test('pages past 1000 rows', () async {
      db.tables['navigation_sessions'] = [
        for (var i = 0; i < 1500; i++) ...[
          {...start('t$i'), 'started_at': '2026-01-01'},
          {...end('t$i'), 'started_at': '2026-01-01'},
        ],
      ];
      final m = await AnalyticsRepository().getNavigationMetrics();
      expect(m.trips, 1500);
    });

    test('a missing sus_responses table is not a failure', () async {
      db.failing.add('GET sus_responses');
      db.failureCode = 'PGRST205';
      final m = await AnalyticsRepository().getNavigationMetrics();
      expect(m.susTableAvailable, isFalse);
      expect(m.averageSus, isNull);
    });

    test('a failed request is an error, not "No data yet"', () async {
      db.failing.add('GET navigation_sessions');
      await expectLater(AnalyticsRepository().getNavigationMetrics(),
          throwsA(isA<RepositoryException>()));
      db.failing
        ..clear()
        ..add('GET sus_responses');
      await expectLater(AnalyticsRepository().getNavigationMetrics(),
          throwsA(isA<RepositoryException>()));
    });
  });

  group('section', () {
    Future<void> pump(WidgetTester tester, NavigationMetrics m) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
              child: NavigationMetricsSection(metrics: m)),
        ),
      ));
    }

    testWidgets('shows values when there is data', (tester) async {
      await pump(
        tester,
        compute([
          start('a'), end('a', seconds: 185, errors: 1, steps: 8),
          start('b', mode: '2d'), end('b', mode: '2d', seconds: 185,
              errors: 1, steps: 8),
        ], [
          {'id': 1, 'sus_score': 72.5},
        ]),
      );
      expect(find.text('12.5%'), findsWidgets);
      expect(find.text('3m 05s'), findsWidgets);
      expect(find.text('72.5'), findsWidgets);
      expect(find.text('AR'), findsWidgets);
      expect(find.text('2D'), findsWidgets);
      expect(find.text('No data yet'), findsNothing);
    });

    testWidgets('says No data yet and lists the expected columns',
        (tester) async {
      await pump(tester, compute([]));
      expect(find.text('No data yet'), findsNWidgets(7));
      expect(find.textContaining('error_count, total_steps'), findsOneWidget);
      expect(find.textContaining('duration_seconds'), findsOneWidget);
      expect(find.textContaining('Expected columns: sus_score'), findsOneWidget);
      expect(find.textContaining('row_type, mode'), findsOneWidget);
    });

    testWidgets('labels errors honestly and explains both figures',
        (tester) async {
      await pump(
        tester,
        compute([start('a'), end('a', errors: 3, reroutes: 1, steps: 10)]),
      );
      expect(find.text('Errors per route step'), findsOneWidget);
      expect(find.text('30.0%'), findsWidgets);
      expect(find.text('Off-route events'), findsWidgets);
      expect(find.text('2'), findsOneWidget);
      expect(find.textContaining('1 reroute,'), findsOneWidget);
      expect(find.textContaining('error_count minus reroute_count'),
          findsOneWidget);
      expect(find.text('Navigation Error Rate'), findsNothing);
      expect(find.textContaining('Off-route events per route step'),
          findsNothing);
    });

    testWidgets('shows both success figures and the manual count',
        (tester) async {
      await pump(
        tester,
        compute([
          start('a'), end('a'),
          start('b'), end('b', manual: true),
          start('c'), end('c', completed: false),
          start('d'),
        ]),
      );
      expect(find.text('Completion Rate'), findsOneWidget);
      expect(find.text('50.0%'), findsWidgets);
      expect(find.text('GPS-only arrivals'), findsOneWidget);
      expect(find.text('25.0%'), findsWidgets);
      expect(find.textContaining('plus 1 manual arrival'), findsOneWidget);
    });

    testWidgets('names a column that is really missing', (tester) async {
      await pump(
        tester,
        compute([
          {'id': 1, 'to_name': 'Library'},
        ]),
      );
      expect(find.textContaining('Missing: trip_id, row_type, mode'),
          findsOneWidget);
    });
  });
}
