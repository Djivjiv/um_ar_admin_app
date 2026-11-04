import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/core/utils/csv_export.dart';
import 'package:um_ar_admin/core/utils/date_range.dart';
import 'package:um_ar_admin/data/repositories/feedback_repository.dart';
import 'package:um_ar_admin/data/repositories/repository_exception.dart';
import 'package:um_ar_admin/domain/models/feedback_comment_model.dart';
import 'package:um_ar_admin/presentation/screens/feedback/feedback_comments_screen.dart';

import 'support/fake_postgrest.dart';

Map<String, dynamic> _row(
  int id, {
  String comment = 'Nice app',
  String? role = 'student',
  String created = '2026-03-15T10:00:00Z',
  String? context,
  String? device = 'device-1',
  String? user,
}) =>
    {
      'id': id,
      'comment': comment,
      'rating_context': context,
      'role': role,
      'device_code': device,
      'user_id': user,
      'created_at': created,
    };

void main() {
  group('privacy', () {
    test('the anonymous id hides the reference but is stable', () {
      const uuid = '3f1c9a2e-0000-4000-8000-1234567890ab';
      final id = anonymousId(uuid);
      expect(id, hasLength(8));
      expect(id, anonymousId(uuid));
      expect(id, isNot(anonymousId('$uuid-2')));
      expect(uuid.toUpperCase(), isNot(contains(id)));
    });

    test('the hash matches a known value, so web and Windows agree', () {
      expect(anonymousId('a'), 'E40C292C');
      expect(anonymousId(''), '811C9DC5');
    });

    test('emails typed into a comment are removed', () {
      expect(removeEmails('Email me at ana.cruz@umindanao.edu.ph, thanks'),
          'Email me at [email removed], thanks');
      expect(removeEmails('no address @ here'), 'no address @ here');
    });

    test('names and emails on the row go nowhere', () {
      final model = FeedbackCommentModel.fromJson({
        ..._row(1, user: 'uid-1', device: 'device-1'),
        'full_name': 'Ana Cruz',
        'email': 'ana@umindanao.edu.ph',
      });
      final export = jsonEncode(feedbackExportRows([model]));
      expect(export, isNot(contains('Ana')));
      expect(export, isNot(contains('ana@')));
      expect(export, isNot(contains('uid-1')));
      expect(export, isNot(contains('device-1')));
    });

    test('the reference is user_id when signed in, else device_code', () {
      expect(FeedbackCommentModel.fromJson(_row(1, user: 'u', device: 'd'))
          .anonymousRef, anonymousId('u'));
      expect(FeedbackCommentModel.fromJson(_row(1, device: 'd')).anonymousRef,
          anonymousId('d'));
      expect(FeedbackCommentModel.fromJson(_row(1, device: null)).anonymousRef,
          isNull);
    });
  });

  group('filters', () {
    final rows = [
      FeedbackCommentModel.fromJson(_row(1, comment: 'Map is great')),
      FeedbackCommentModel.fromJson(
          _row(2, comment: 'Too slow', role: 'faculty', context: 'Rated 2')),
      FeedbackCommentModel.fromJson(_row(3, comment: 'ok', role: 'Visitor')),
    ];

    test('by role, ignoring case in the data', () {
      expect(filterFeedback(rows, role: 'visitor').map((r) => r.id), ['3']);
    });

    test('search looks in the comment and rating context', () {
      expect(filterFeedback(rows, search: 'GREAT').map((r) => r.id), ['1']);
      expect(filterFeedback(rows, search: 'rated').map((r) => r.id), ['2']);
    });

    test('both narrow together; nothing set keeps everything', () {
      expect(filterFeedback(rows, role: 'student', search: 'slow'), isEmpty);
      expect(filterFeedback(rows), hasLength(3));
    });
  });

  group('CSV', () {
    test('quotes commas, quotes and line breaks', () {
      expect(
        csvEncode([
          ['a,b', 'say "hi"', 'two\nlines', null, 5],
        ]),
        '"a,b","say ""hi""","two\nlines",,5',
      );
    });

    test('text that Excel would run as a formula is made harmless', () {
      for (final attack in ['=1+1', '+1', '-1', '@SUM(A1)']) {
        expect(csvEncode([
          [attack],
        ]), "'$attack");
      }
    });

    test('numbers are left alone', () {
      expect(csvEncode([
        [-5],
      ]), '-5');
    });
  });

  group('repository', () {
    late FakePostgrest db;

    setUp(() => db = FakePostgrest()..install());
    tearDown(FakePostgrest.uninstall);

    test('newest first, past 1000 rows', () async {
      db.tables['feedback_comments'] = [
        for (var i = 0; i < 2500; i++)
          _row(i,
              created: DateTime.utc(2026, 1, 1)
                  .add(Duration(minutes: i))
                  .toIso8601String()),
      ];
      final load = await FeedbackRepository().getComments();
      expect(load.rows, hasLength(2500));
      expect(load.rows.first.id, '2499');
      expect(load.rows.map((r) => r.id).toSet(), hasLength(2500));
    });

    test('a missing table is no data, not an error', () async {
      db.failing.add('GET feedback_comments');
      db.failureCode = 'PGRST205';
      final load = await FeedbackRepository().getComments();
      expect(load.tableExists, isFalse);
      expect(load.rows, isEmpty);
    });

    test('a missing column on the query is reported by name', () async {
      db.tables['feedback_comments'] = [
        {'id': 1, 'comment': 'x'},
      ];
      var gets = 0;
      db.onRequest = (key) {
        if (key != 'GET feedback_comments') return;
        // The ordered query fails; the one-row sample after it works.
        if (++gets == 1) {
          db.failing.add(key);
          db.failureCode = '42703';
          db.failureMessage = 'column created_at does not exist';
        } else {
          db.failing.clear();
        }
      };
      final load = await FeedbackRepository().getComments();
      expect(load.tableExists, isTrue);
      expect(load.rows, isEmpty);
      expect(load.missingColumns, contains('created_at'));
    });

    test('rows without a required column show no data, naming it', () async {
      db.tables['feedback_comments'] = [
        {'id': 1, 'created_at': '2026-01-01'},
      ];
      final load = await FeedbackRepository().getComments();
      expect(load.rows, isEmpty);
      expect(load.missingColumns, contains('comment'));
    });

    test('a missing optional column keeps the rows', () async {
      db.tables['feedback_comments'] = [
        {'id': 1, 'comment': 'x', 'created_at': '2026-01-01'},
      ];
      final load = await FeedbackRepository().getComments();
      expect(load.rows, hasLength(1));
      expect(load.missingColumns, contains('rating_context'));
    });

    test('a failed query is an error, not an empty list', () async {
      db.failing.add('GET feedback_comments');
      await expectLater(
        FeedbackRepository().getComments(),
        throwsA(isA<RepositoryException>().having(
            (e) => e.message, 'message', contains('server exploded'))),
      );
    });

    test('the date range includes the whole last day', () async {
      String iso(DateTime d) => d.toUtc().toIso8601String();
      db.tables['feedback_comments'] = [
        _row(1, created: iso(DateTime(2026, 3, 10, 23, 30))),
        _row(2, created: iso(DateTime(2026, 3, 11, 0, 30))),
      ];
      final span = wholeDays(DateTime(2026, 3, 1), DateTime(2026, 3, 10));
      final load =
          await FeedbackRepository().getComments(from: span.from, to: span.to);
      expect(load.rows.map((r) => r.id), ['1']);
    });
  });

  group('screen', () {
    late FakePostgrest db;

    setUp(() => db = FakePostgrest()..install());
    tearDown(FakePostgrest.uninstall);

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: FeedbackCommentsScreen())));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
    }

    testWidgets('no rows: No data yet, with the expected columns',
        (tester) async {
      await pump(tester);
      expect(find.text('No data yet'), findsOneWidget);
      expect(find.textContaining('rating_context, role, device_code'),
          findsOneWidget);
    });

    testWidgets('a missing table says so', (tester) async {
      db.failing.add('GET feedback_comments');
      db.failureCode = '42P01';
      await pump(tester);
      expect(find.text('No data yet'), findsOneWidget);
      expect(find.textContaining('table was not found'), findsOneWidget);
    });

    testWidgets('a failure shows why, and Retry recovers', (tester) async {
      db.tables['feedback_comments'] = [_row(1, comment: 'Back again')];
      db.failing.add('GET feedback_comments');
      await pump(tester);
      expect(find.textContaining('Failed to load comments'), findsOneWidget);
      expect(find.text('No data yet'), findsNothing);

      db.failing.clear();
      await tester.tap(find.text('Retry'));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
      expect(find.text('Back again'), findsOneWidget);
    });

    testWidgets('shows role and anonymous id, never the reference',
        (tester) async {
      db.tables['feedback_comments'] = [
        {..._row(1, device: 'device-secret'), 'email': 'a@um.edu.ph'},
      ];
      await pump(tester);
      expect(find.text('student'), findsWidgets);
      expect(find.text(anonymousId('device-secret')), findsOneWidget);
      expect(find.textContaining('device-secret'), findsNothing);
      expect(find.textContaining('a@um.edu.ph'), findsNothing);
    });
  });
}
