import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/domain/models/kiosk_settings_model.dart';

/// [path] with every `--` comment removed: only what the SQL editor runs.
String runnableSql(String path) => [
      for (final line in File(path).readAsLinesSync())
        line.contains('--') ? line.substring(0, line.indexOf('--')) : line,
    ].join('\n');

/// One `create policy` statement of [sql].
class Policy {
  final String name;
  final String table;
  final String command;
  final String roles;
  final String body;

  Policy(this.name, this.table, this.command, this.roles, this.body);

  bool get adminOnly =>
      body.contains('using (public.is_admin())') &&
      (command == 'select' ||
          command == 'delete' ||
          body.contains('with check (public.is_admin())'));
}

List<Policy> policies(String sql) {
  final create = RegExp(
    r'create policy "([^"]+)"\s+on public\.(\w+)\s+for (\w+)\s+'
    r'to ([\w, ]+?)\s+(using|with check)([^;]*);',
    multiLine: true,
  );
  return [
    for (final m in create.allMatches(sql))
      Policy(m[1]!, m[2]!, m[3]!, m[4]!.trim(), '${m[5]}${m[6]}'
          .replaceAll(RegExp(r'\s+'), ' ')),
  ];
}

const _lockdown = 'db/admin_lockdown.sql';
const _lockedTables = [
  'kiosk_settings',
  'kiosk_survey_responses',
  'kiosk_events',
  'facilities',
  'facility_details',
  'outdoor_ar_nodes',
  'outdoor_ar_edges',
];
const _publicReadTables = [
  'facilities',
  'facility_details',
  'outdoor_ar_nodes',
  'outdoor_ar_edges',
];

void main() {
  group('admin_lockdown.sql', () {
    late String sql;
    late List<Policy> all;

    setUp(() {
      sql = runnableSql(_lockdown);
      all = policies(sql);
    });

    List<Policy> on(String table) => [
          for (final p in all)
            if (p.table == table) p,
        ];

    test('reads all 14 policies, so the checks below see them', () {
      expect(all, hasLength(14));
      expect(RegExp('create policy').allMatches(sql), hasLength(14));
    });

    test('runs in one transaction, and stops without is_admin()', () {
      expect(sql, contains('begin;'));
      expect(sql.indexOf('commit;'), greaterThan(sql.indexOf('begin;')));
      expect(sql, contains("to_regprocedure('public.is_admin()')"));
      expect(sql, contains('raise exception'));
    });

    test('drops every old policy on the tables it locks', () {
      expect(sql, contains('from pg_policies'));
      expect(sql, contains("execute format('drop policy %I on public.%I'"));
      for (final t in _lockedTables) {
        expect(sql, contains("'$t'"), reason: '$t is in the drop list');
        expect(sql, contains('alter table public.$t'),
            reason: 'RLS is turned on for $t');
      }
    });

    test('every write policy is admin only', () {
      for (final p in all) {
        if (p.command == 'insert' &&
            const ['kiosk_survey_responses', 'kiosk_events']
                .contains(p.table)) {
          continue; // the kiosk's own inserts, checked below
        }
        if (p.command == 'select') continue;
        expect(p.adminOnly, isTrue, reason: '"${p.name}" writes ${p.table}');
        expect(p.roles, 'authenticated', reason: p.name);
      }
    });

    test('kiosk answers and events: the kiosk inserts, admins read', () {
      for (final t in const ['kiosk_survey_responses', 'kiosk_events']) {
        final ps = on(t);
        expect(ps.map((p) => p.command).toSet(), {'insert', 'select'},
            reason: '$t has no update or delete policy');
        final insert = ps.singleWhere((p) => p.command == 'insert');
        expect(insert.roles, 'anon, authenticated');
        final read = ps.singleWhere((p) => p.command == 'select');
        expect(read.adminOnly, isTrue, reason: '$t is read by admins only');
      }
    });

    test('facilities and the AR network: public read, admin write', () {
      for (final t in _publicReadTables) {
        final ps = on(t);
        final read = ps.singleWhere((p) => p.command == 'select');
        expect(read.body, 'using (true)');
        final write = ps.singleWhere((p) => p.command == 'all');
        expect(write.adminOnly, isTrue);
      }
    });

    test('kiosk_settings: admins write; the public read is the step B one', () {
      final ps = on('kiosk_settings');
      expect(ps.singleWhere((p) => p.command == 'all').adminOnly, isTrue);
      final open = [
        for (final p in ps)
          if (!p.adminOnly) p,
      ];
      expect(open.single.name, 'kiosk_settings public read (until step B)');
      expect(open.single.command, 'select');
    });

    test('leaves kiosk_sessions alone, so the kiosk can update its row', () {
      expect(sql, isNot(contains('public.kiosk_sessions')));
    });

    test('the view leaves out exit_pin; the check returns only a boolean', () {
      final view = RegExp(
              r'create or replace view public\.kiosk_settings_public as([^;]*);')
          .firstMatch(sql)![1]!;
      expect(view, isNot(contains('exit_pin')));
      expect(view, isNot(contains('*')));
      expect(sql, contains('public.check_kiosk_exit_pin(p_pin text)\n'
          'returns boolean'));
      expect(sql, contains('security definer'));
    });

    test('step B and the unseen tables stay commented out', () {
      expect(sql, isNot(contains('drop policy if exists "kiosk_settings')));
      for (final t in const [
        'buildings',
        'rooms',
        'announcements',
        'indoor_nodes',
        'indoor_edges',
        'outdoor_nodes',
        'outdoor_edges',
        'building_floors',
      ]) {
        expect(sql, isNot(contains('public.$t ')), reason: t);
        expect(sql, isNot(contains('public.$t\n')), reason: t);
      }
      final text = File(_lockdown).readAsStringSync();
      expect(text, contains('RUN THE SCHEMA EXPORT QUERIES (section A) FIRST'));
      expect(text, contains('-- select tablename, policyname'));
    });

    test('the header says what the kiosk still needs and how to undo', () {
      final text = File(_lockdown).readAsStringSync();
      expect(text, contains('What the kiosk still needs after this file'));
      expect(text, contains('What each step changes, and how to undo it'));
    });
  });

  group('kiosk_settings.sql', () {
    late String sql;

    setUp(() => sql = runnableSql('db/kiosk_settings.sql'));

    test('creates every column the admin app writes, and exit_pin', () {
      final columns = {
        ...const KioskSettingsModel().toJson().keys,
        // Read by the kiosk app's KioskSettings.fromRow.
        'exit_pin',
      };
      expect(sql, contains('create table if not exists public.kiosk_settings'));
      for (final c in columns) {
        expect(sql, contains('add column if not exists $c '), reason: c);
      }
    });

    test('uses the kiosk app\'s PIN rule and holds no PIN', () {
      expect(sql, contains('kiosk_settings_exit_pin_format'));
      expect(sql, contains(r"exit_pin ~ '^[0-9]{4,12}$'"));
      expect(sql, isNot(contains(RegExp(r"'[0-9]{4,}'"))),
          reason: 'no PIN value in the file');
      expect(sql, isNot(contains('insert into')));
    });
  });
}
