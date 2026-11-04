import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/core/utils/date_range.dart';
import 'package:um_ar_admin/data/repositories/analytics_repository.dart';
import 'package:um_ar_admin/data/repositories/dashboard_repository.dart';

import 'support/fake_postgrest.dart';

var _id = 1;

Map<String, dynamic> _start(
  String trip, {
  String to = 'Library',
  String at = '2026-03-10T09:00:00',
  String? user,
  double? distance,
}) =>
    {
      'id': _id++,
      'trip_id': trip,
      'row_type': 'start',
      'to_name': to,
      'started_at': at,
      'user_id': user,
      'distance_meters': distance,
      'completed': false,
    };

Map<String, dynamic> _end(
  String trip, {
  bool completed = true,
  String to = 'Library',
  String at = '2026-03-10T09:00:00',
  String? user,
  double? distance,
}) =>
    {
      'id': _id++,
      'trip_id': trip,
      'row_type': 'end',
      'to_name': to,
      'started_at': at,
      'user_id': user,
      'distance_meters': distance,
      'completed': completed,
      'duration_seconds': 60,
    };

Map<String, dynamic> _old({String to = 'Old Hall'}) => {
      'id': _id++,
      'trip_id': null,
      'row_type': null,
      'to_name': to,
      'started_at': '2026-03-10T09:00:00',
      'completed': true,
    };

void main() {
  group('summarizeTrips', () {
    test('a finished trip counts once, not twice', () {
      final s = summarizeTrips([_start('a'), _end('a')]);
      expect(s.trips, 1);
      expect(s.perDay.single.value, 1);
    });

    test('completion rate is per trip, so all done reads 100%', () {
      final s = summarizeTrips([
        _start('a'), _end('a'),
        _start('b'), _end('b'),
      ]);
      expect(s.completionRate, 100,
          reason: 'counting rows would give 50%');
    });

    test('abandoned and unfinished trips bring it down', () {
      final s = summarizeTrips([
        _start('a'), _end('a'),
        _start('b'), _end('b', completed: false),
        _start('c'),
        _start('d'),
      ]);
      expect(s.completedTrips, 1);
      expect(s.completionRate, 25);
    });

    test('most visited counts trips, busiest first', () {
      final s = summarizeTrips([
        _start('a', to: 'Gym'), _end('a', to: 'Gym'),
        _start('b', to: 'Library'), _end('b', to: 'Library'),
        _start('c', to: 'Library'),
      ]);
      expect(s.mostVisited.map((p) => (p.label, p.value)),
          [('Library', 2.0), ('Gym', 1.0)]);
    });

    test('peak hours count trips', () {
      final s = summarizeTrips([_start('a'), _end('a')]);
      expect(s.peakHours, hasLength(24));
      expect(s.peakHours[9].value, 1);
    });

    test('distance is averaged per trip', () {
      final s = summarizeTrips([
        _start('a', distance: 100), _end('a', distance: 100),
        _start('b', distance: 300),
      ]);
      expect(s.averageDistance, 200);
    });

    test('trips with a distance of 0 or null do not lower the average', () {
      final s = summarizeTrips([
        _start('a', distance: 100), _end('a', distance: 100),
        _start('b', distance: 0), _end('b', distance: 0),
        _start('c'), _end('c'),
      ]);
      expect(s.averageDistance, 100,
          reason: 'counting the 0 as a length would give 50');
    });

    test('only unknown distances gives no average, not 0', () {
      final s = summarizeTrips([_start('a', distance: 0)]);
      expect(s.averageDistance, isNull);
    });

    test('a 0 on the start row falls back to the end row', () {
      final s = summarizeTrips([
        _start('a', distance: 0), _end('a', distance: 250),
      ]);
      expect(s.averageDistance, 250);
    });

    test('rows with no trip_id are left out, and counted for the note', () {
      final s = summarizeTrips([_start('a'), _end('a'), _old(), _old()]);
      expect(s.trips, 1);
      expect(s.rowsWithoutTrip, 2);
      expect(s.mostVisited.map((p) => p.label), ['Library']);
    });

    test('only old rows gives no trips and no rate', () {
      final s = summarizeTrips([_old()]);
      expect(s.trips, 0);
      expect(s.completionRate, isNull);
      expect(s.averageDistance, isNull);
    });
  });

  group('from the database', () {
    late FakePostgrest db;

    setUp(() {
      db = FakePostgrest()..install();
      db.tables['visitor_sessions'] = [];
      db.tables['kiosk_sessions'] = [];
    });
    tearDown(FakePostgrest.uninstall);

    test('the old cards agree with Navigation Evaluation', () async {
      db.tables['navigation_sessions'] = [
        for (final row in [
          _start('a'), _end('a'),
          _start('b'), _end('b', completed: false),
          _start('c'),
          _old(),
        ])
          {...row, 'mode': 'ar'},
      ];
      final repo = AnalyticsRepository();
      final cards = await repo.getTripSummary();
      final metrics = await repo.getNavigationMetrics();
      expect(cards.trips, metrics.trips);
      expect(cards.trips, 3);
      expect(cards.completedTrips, metrics.modes.single.completedTrips);
    });

    test('dashboard Most Visited counts trips and skips old rows', () async {
      db.tables['navigation_sessions'] = [
        _start('a'), _end('a'),
        _old(), _old(), _old(),
      ];
      final visits = await DashboardRepository().getMostVisited();
      expect(visits.map((v) => (v.name, v.count)), [('Library', 1)]);
    });

    test('Daily Trips splits trips into signed-in and visitor', () async {
      final today = DateTime.now().copyWith(hour: 12).toIso8601String();
      db.tables['navigation_sessions'] = [
        _start('a', at: today, user: 'u'), _end('a', at: today, user: 'u'),
        _start('b', at: today),
        {..._old(), 'started_at': today},
      ];
      final series = await DashboardRepository().getDailySeries(1);
      expect(series.registered, [1]);
      expect(series.visitor, [1]);
    });

    test('the visitor line is trips, never visitor sessions', () async {
      final today = DateTime.now().copyWith(hour: 12).toIso8601String();
      db.tables['navigation_sessions'] = [_start('a', at: today)];
      db.tables['visitor_sessions'] = [
        for (var i = 0; i < 5; i++) {'id': 'v$i', 'started_at': today},
      ];
      final series = await DashboardRepository().getDailySeries(1);
      expect(series.visitor, [1],
          reason: 'five sessions and one trip must read as one trip');
      expect(db.requestCount('GET visitor_sessions'), 0);
    });

    test('is_visitor decides the line when the column exists', () async {
      final today = DateTime.now().copyWith(hour: 12).toIso8601String();
      db.tables['navigation_sessions'] = [
        {..._start('a', at: today, user: 'u'), 'is_visitor': false},
        {..._start('b', at: today), 'is_visitor': true},
      ];
      final series = await DashboardRepository().getDailySeries(1);
      expect(series.registered, [1]);
      expect(series.visitor, [1]);
    });

    test('kiosk sessions stay in their own series', () async {
      final today = DateTime.now().copyWith(hour: 12).toIso8601String();
      db.tables['navigation_sessions'] = [_start('a', at: today)];
      db.tables['kiosk_sessions'] = [
        {'id': 'k1', 'started_at': today},
        {'id': 'k2', 'started_at': today},
      ];
      final series = await DashboardRepository().getDailySeries(1);
      expect(series.kiosk, [2]);
      expect(series.visitor, [1]);
    });

    test('a table without the trip columns gives no trips, not an error',
        () async {
      db.tables['navigation_sessions'] = [
        {'id': 1, 'to_name': 'Hall', 'started_at': '2026-03-10T09:00:00'},
      ];
      expect(await DashboardRepository().getMostVisited(), isEmpty);
      expect((await AnalyticsRepository().getTripSummary()).rowsWithoutTrip, 1);
    });

    test('Trips Today counts one for a finished trip', () async {
      final today = DateTime.now().toUtc().toIso8601String();
      db.tables['navigation_sessions'] = [
        _start('a', at: today), _end('a', at: today),
      ];
      expect(await AnalyticsRepository().getTripsTodayCount(), 1);
    });
  });

  group('date range end', () {
    test('covers the whole last day', () {
      final span = wholeDays(DateTime(2026, 3, 1), DateTime(2026, 3, 10));
      expect(span.from, DateTime(2026, 3, 1));
      expect(span.to, DateTime(2026, 3, 11));
    });

    test('a time on the picked dates is ignored', () {
      final span =
          wholeDays(DateTime(2026, 3, 1, 15, 30), DateTime(2026, 3, 10, 15, 30));
      expect(span.from, DateTime(2026, 3, 1));
      expect(span.to, DateTime(2026, 3, 11));
    });

    test('rolls over month and year ends', () {
      expect(wholeDays(DateTime(2026, 2, 1), DateTime(2026, 2, 28)).to,
          DateTime(2026, 3, 1));
      expect(wholeDays(DateTime(2026, 12, 1), DateTime(2026, 12, 31)).to,
          DateTime(2027, 1, 1));
    });

    test('one day is a whole day', () {
      final span = wholeDays(DateTime(2026, 3, 10), DateTime(2026, 3, 10));
      expect(span.to.difference(span.from), const Duration(hours: 24));
    });

    test('withinSpan keeps the last minute and drops the next midnight', () {
      final span = wholeDays(DateTime(2026, 3, 1), DateTime(2026, 3, 10));
      bool has(DateTime d) => withinSpan(d, span.from, span.to);
      expect(has(DateTime(2026, 3, 1)), isTrue);
      expect(has(DateTime(2026, 3, 10, 23, 59, 59)), isTrue);
      expect(has(DateTime(2026, 3, 11)), isFalse);
      expect(has(DateTime(2026, 2, 28, 23, 59, 59)), isFalse);
    });

    test('a trip late on the last day is counted', () async {
      final db = FakePostgrest()..install();
      addTearDown(FakePostgrest.uninstall);
      String iso(DateTime d) => d.toUtc().toIso8601String();
      db.tables['navigation_sessions'] = [
        _start('late', at: iso(DateTime(2026, 3, 10, 23, 30))),
        _start('next', at: iso(DateTime(2026, 3, 11, 0, 30))),
      ];
      final span = wholeDays(DateTime(2026, 3, 1), DateTime(2026, 3, 10));
      final repo = AnalyticsRepository();
      final cards = await repo.getTripSummary(from: span.from, to: span.to);
      expect(cards.trips, 1);
      final metrics =
          await repo.getNavigationMetrics(from: span.from, to: span.to);
      expect(metrics.trips, 1);
    });

    test('a SUS answer late on the last day is counted', () async {
      final db = FakePostgrest()..install();
      addTearDown(FakePostgrest.uninstall);
      db.tables['sus_responses'] = [
        {
          'id': 1,
          'sus_score': 70,
          'user_id': 'u',
          'submitted_at': DateTime(2026, 3, 10, 23, 30).toIso8601String(),
        },
      ];
      final span = wholeDays(DateTime(2026, 3, 1), DateTime(2026, 3, 10));
      final m = await AnalyticsRepository()
          .getNavigationMetrics(from: span.from, to: span.to);
      expect(m.averageSus, 70);
    });
  });
}
