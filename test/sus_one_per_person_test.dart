import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/core/utils/sus_dedupe.dart';
import 'package:um_ar_admin/data/repositories/analytics_repository.dart';
import 'package:um_ar_admin/data/repositories/dashboard_repository.dart';
import 'package:um_ar_admin/data/repositories/sus_repository.dart';

import 'support/fake_postgrest.dart';

Map<String, dynamic> _sus(
  int id,
  double score, {
  String? user,
  String? device,
  String date = '2026-03-01',
  String type = 'student',
}) =>
    {
      'id': id,
      'sus_score': score,
      'user_id': user,
      'device_code': device,
      'submitted_at': date,
      'user_type': type,
    };

List<Object?> _ids(SusDedupeResult r) => [for (final x in r.kept) x['id']];

void main() {
  group('one response per person', () {
    test('keeps a signed-in user\'s first response', () {
      final r = dedupeSusRows([
        _sus(3, 90, user: 'u', date: '2026-03-03'),
        _sus(1, 50, user: 'u', date: '2026-03-01'),
        _sus(2, 70, user: 'u', date: '2026-03-02'),
      ]);
      expect(_ids(r), [1]);
      expect(r.duplicatesIgnored, 2);
    });

    test('falls back to device_code for anonymous responses', () {
      final r = dedupeSusRows([
        _sus(1, 50, device: 'd', date: '2026-03-01'),
        _sus(2, 90, device: 'd', date: '2026-03-02'),
        _sus(3, 60, device: 'other'),
      ]);
      expect(_ids(r), [1, 3]);
      expect(r.duplicatesIgnored, 1);
    });

    test('user_id wins when a row has both', () {
      final r = dedupeSusRows([
        _sus(1, 50, user: 'u', device: 'shared'),
        _sus(2, 90, user: 'v', device: 'shared'),
      ]);
      expect(r.kept, hasLength(2), reason: 'two people, one device');
    });

    test('the same date falls back to the lower id', () {
      final r = dedupeSusRows([
        _sus(9, 90, user: 'u'),
        _sus(2, 50, user: 'u'),
      ]);
      expect(_ids(r), [2]);
    });

    test('a dated response beats one with no date', () {
      final r = dedupeSusRows([
        {..._sus(1, 90, user: 'u'), 'submitted_at': null},
        _sus(2, 50, user: 'u'),
      ]);
      expect(_ids(r), [2]);
    });

    test('rows with no id at all each count, and are reported', () {
      final r = dedupeSusRows([_sus(1, 50), _sus(2, 90, device: '  ')]);
      expect(r.kept, hasLength(2));
      expect(r.unidentified, 2);
      expect(r.duplicatesIgnored, 0);
    });

    test('no rows, nothing to report', () {
      final r = dedupeSusRows([]);
      expect(r.kept, isEmpty);
      expect(r.missingColumns, isEmpty);
      expect(susDedupeNote(r), isNull);
    });

    test('a missing column is named, and matching still works', () {
      final r = dedupeSusRows([
        {'id': 1, 'sus_score': 50.0, 'user_id': 'u'},
        {'id': 2, 'sus_score': 90.0, 'user_id': 'u'},
        {'id': 3, 'sus_score': 70.0, 'user_id': null},
      ]);
      expect(r.missingColumns, ['device_code']);
      expect(r.kept, hasLength(2));
      final note = susDedupeNote(r)!;
      expect(note, contains('1 duplicate ignored'));
      expect(note, contains('Expected columns: user_id, device_code'));
      expect(note, contains('Missing: device_code'));
      expect(note, contains('1 anonymous response'));
    });
  });

  group('SUS bands', () {
    double count(List<double> scores, String band) => susBands(scores)
        .firstWhere((p) => p.label == band)
        .value;

    test('always lists the five bands, in order', () {
      expect(susBands(const []).map((p) => p.label),
          ['0-25', '26-50', '51-68', '69-80', '81-100']);
    });

    test('each band includes its top score', () {
      expect(count([25], '0-25'), 1);
      expect(count([50], '26-50'), 1);
      expect(count([68], '51-68'), 1);
      expect(count([80], '69-80'), 1);
      expect(count([100], '81-100'), 1);
    });

    test('just over a boundary moves up', () {
      expect(count([25.5], '26-50'), 1);
      expect(count([68.5], '69-80'), 1);
      expect(count([80.5], '81-100'), 1);
    });
  });

  group('statistics use one response per person', () {
    final rows = [
      _sus(1, 40, user: 'u', date: '2026-03-01', type: 'student'),
      _sus(2, 100, user: 'u', date: '2026-03-02', type: 'student'),
      _sus(3, 80, user: 'v', date: '2026-03-01', type: 'faculty'),
    ];

    test('count, average, bands and user types', () {
      final s = computeSusStats(rows);
      expect(s.responses, hasLength(2));
      expect(s.average, 60);
      expect(
          s.distribution.firstWhere((p) => p.label == '81-100').value, 0);
      expect(s.byUserType.firstWhere((p) => p.label == 'student').value, 40);
      expect(s.dedupe.duplicatesIgnored, 1);
    });

    group('from the database', () {
      late FakePostgrest db;

      setUp(() {
        db = FakePostgrest()..install();
        db.tables['sus_responses'] = [for (final r in rows) {...r}];
      });
      tearDown(FakePostgrest.uninstall);

      test('the export has one row per person', () async {
        final export = await SusRepository().exportRows();
        expect(export, hasLength(3), reason: 'header + 2 people');
      });

      test('the dashboard summary agrees', () async {
        final s = await DashboardRepository().getSusSummary();
        expect(s.totalResponses, 2);
        expect(s.averageScore, 60);
        expect(s.note, contains('1 duplicate ignored'));
      });

      test('Analytics agrees', () async {
        final m = await AnalyticsRepository().getNavigationMetrics();
        expect(m.susResponses, 2);
        expect(m.averageSus, 60);
        expect(m.susNote, contains('1 duplicate ignored'));
      });

      test('a later response stays ignored when the first is out of range',
          () async {
        final m = await AnalyticsRepository().getNavigationMetrics(
          from: DateTime(2026, 3, 2),
          to: DateTime(2026, 3, 3),
        );
        expect(m.susResponses, 0,
            reason: "u's second response must not become their first");
      });
    });
  });
}
