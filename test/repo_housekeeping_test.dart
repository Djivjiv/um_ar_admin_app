import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The numbered rows of the README's SQL table: step, from, file.
List<(int, String, String)> sqlSteps() {
  final row = RegExp(r'^\| (\d+) \| ([a-z ]+) \| `([a-z0-9_]+\.sql)` \|');
  return [
    for (final line in File('README.md').readAsLinesSync())
      if (row.firstMatch(line) case final m?)
        (int.parse(m[1]!), m[2]!, m[3]!),
  ];
}

Iterable<File> dartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  group('README SQL section', () {
    int step(String file) =>
        sqlSteps().firstWhere((s) => s.$3 == file).$1;

    void before(String first, String second) {
      expect(step(first), lessThan(step(second)),
          reason: '$first must run before $second');
    }

    test('steps are numbered from 1 with no gaps', () {
      final numbers = sqlSteps().map((s) => s.$1).toList();
      expect(numbers, [for (var i = 1; i <= numbers.length; i++) i]);
    });

    test('lists every SQL file in db/ except the data files', () {
      const dataFiles = {'seed_mock_data.sql', 'be_floors_3_4_nodes.sql'};
      final inDb = {
        for (final f in Directory('db').listSync().whereType<File>())
          f.uri.pathSegments.last,
      }.difference(dataFiles);
      final listed = sqlSteps().map((s) => s.$3).toSet();
      expect(inDb.difference(listed), isEmpty);
      final readme = File('README.md').readAsStringSync();
      for (final f in dataFiles) {
        expect(readme, contains('db/$f'));
      }
    });

    test('lists the user app and kiosk files', () {
      final listed = sqlSteps().map((s) => s.$3).toSet();
      expect(listed, containsAll(const [
        'navigation_evaluation.sql',
        'visitor_sessions.sql',
        'sus_once_per_person.sql',
        'feedback_comments.sql',
        'kiosk_sessions_tracking.sql',
        'kiosk_events.sql',
        'kiosk_survey.sql',
        'kiosk_settings_read.sql',
        'kiosk_exit_pin.sql',
        'kiosk_announcements_read.sql',
        'kiosk_offline_queue.sql',
        'kiosk_device_code.sql',
      ]));
    });

    test('says which repository each file is in', () {
      String from(String file) =>
          sqlSteps().firstWhere((s) => s.$3 == file).$2;
      expect(from('user_roles.sql'), 'admin');
      expect(from('visitor_sessions.sql'), 'user');
      expect(from('kiosk_exit_pin.sql'), 'kiosk');
      expect(from('feedback_comments.sql'), 'admin or user');
    });

    test('keeps the order the files themselves ask for', () {
      before('outdoor_node_entrances.sql', 'indoor_nodes_infonodes.sql');
      before('indoor_nodes_infonodes.sql', 'entrance_links.sql');
      before('kiosk_sessions_tracking.sql', 'kiosk_management.sql');
      before('kiosk_sessions_tracking.sql', 'kiosk_events.sql');
      before('kiosk_sessions_tracking.sql', 'kiosk_survey.sql');
      before('kiosk_survey.sql', 'kiosk_offline_queue.sql');
      before('kiosk_settings_read.sql', 'kiosk_exit_pin.sql');
      before('user_roles.sql', 'user_access_backfill.sql');
      before('user_roles.sql', 'feedback_comments.sql');
      before('user_roles.sql', 'visitor_sessions.sql');
      before('navigation_evaluation.sql', 'visitor_sessions.sql');
      before('navigation_evaluation.sql', 'sus_once_per_person.sql');
      before('user_roles.sql', 'floor_plan_distances.sql');
    });

    test('entrance_links.sql keeps the index off, with a duplicate check', () {
      final lines = File('db/entrance_links.sql').readAsLinesSync();
      final index = lines.indexWhere((l) => l.contains('create unique index'));
      final check = lines.indexWhere((l) => l.contains('having count(*) > 1'));
      expect(lines[index], startsWith('--'), reason: 'stays commented');
      expect(lines[check], startsWith('--'));
      expect(check, lessThan(index), reason: 'the check comes first');
    });

    test('warns about the backfill and the copies', () {
      final readme = File('README.md').readAsStringSync();
      expect(readme, contains('**Run once only**'));
      expect(readme, contains('**Run one copy only**'));
    });

    test('only db/kiosk_settings.sql creates kiosk_settings', () {
      final create = RegExp(r'create\s+table[^;]*kiosk_settings',
          caseSensitive: false);
      final creators = [
        for (final f in Directory('db').listSync().whereType<File>())
          if (create.hasMatch(f.readAsStringSync())) f.uri.pathSegments.last,
      ];
      expect(creators, ['kiosk_settings.sql']);
      before('kiosk_settings.sql', 'kiosk_management.sql');
      before('kiosk_settings.sql', 'kiosk_settings_read.sql');
      before('kiosk_settings.sql', 'kiosk_exit_pin.sql');
    });

    test('lists kiosk_device_code.sql as a kiosk repo file', () {
      final row = File('README.md')
          .readAsLinesSync()
          .firstWhere((l) => l.contains('`kiosk_device_code.sql`'));
      expect(row, contains('| kiosk |'));
      expect(row, contains('Lives in the kiosk repo'));
      before('kiosk_events.sql', 'kiosk_device_code.sql');
      before('kiosk_survey.sql', 'kiosk_device_code.sql');
    });

    test('admin_lockdown.sql runs last', () {
      expect(sqlSteps().last.$3, 'admin_lockdown.sql');
      for (final f in const [
        'user_roles.sql',
        'kiosk_settings.sql',
        'facilities_management.sql',
        'outdoor_ar_v2.sql',
        'kiosk_management.sql',
        'kiosk_events.sql',
        'kiosk_survey.sql',
        'kiosk_settings_read.sql',
      ]) {
        before(f, 'admin_lockdown.sql');
      }
    });
  });

  group('unused code stays gone', () {
    test('graph_utils.dart and the old session model', () {
      expect(File('lib/core/utils/graph_utils.dart').existsSync(), isFalse);
      expect(File('lib/domain/models/navigation_session_model.dart').existsSync(),
          isFalse);
    });

    test('nothing reads kiosk_sus_responses', () {
      for (final f in dartFiles()) {
        expect(f.readAsStringSync(), isNot(contains('kiosk_sus_responses')),
            reason: f.path);
      }
    });

    test('UserRepository has no navigation history', () {
      expect(File('lib/data/repositories/user_repository.dart').readAsStringSync(),
          isNot(contains('getNavigationHistory')));
    });

    test('no building toggleActive or clearLabelPosition', () {
      expect(
          File('lib/data/repositories/building_repository.dart')
              .readAsStringSync(),
          isNot(contains('toggleActive')));
      expect(File('lib/domain/models/building_model.dart').readAsStringSync(),
          isNot(contains('clearLabelPosition')));
    });
  });

  group('stale comments stay fixed', () {
    void lacks(String path, String text) {
      expect(File(path).readAsStringSync(), isNot(contains(text)), reason: path);
    }

    test('are gone', () {
      lacks('lib/core/utils/sus_dedupe.dart', "doesn't write `device_code` yet");
      lacks('lib/domain/models/feedback_comment_model.dart', 'will write the table');
      lacks('db/feedback_comments.sql', 'so the user app has');
      lacks('db/kiosk_management.sql', 'buildings_viewed');
      lacks('db/kiosk_management.sql', 'insert(...).select()');
      lacks('db/kiosk_management.sql', 'has no end time');
      lacks('db/kiosk_management.sql', 'only stores COUNTS');
      lacks('db/kiosk_management.sql',
          'Only signed-in admins can change settings or read usage');
    });
  });
}
