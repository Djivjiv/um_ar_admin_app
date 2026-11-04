import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:um_ar_admin/data/repositories/paged_query.dart';

/// A fake table of [total] rows served like PostgREST `.range(from, to)`.
class _FakeTable {
  final int total;
  final ranges = <(int, int)>[];

  _FakeTable(this.total);

  Future<List<Map<String, dynamic>>> page(int from, int to) async {
    ranges.add((from, to));
    final end = to + 1 < total ? to + 1 : total;
    return [
      for (var i = from; i < end; i++) {'id': i},
    ];
  }
}

void main() {
  group('fetchAllPages', () {
    test('returns an empty list for an empty table in one request', () async {
      final table = _FakeTable(0);
      final rows = await fetchAllPages(table.page, pageSize: 10);
      expect(rows, isEmpty);
      expect(table.ranges, [(0, 9)]);
    });

    test('stops after a short first page', () async {
      final table = _FakeTable(7);
      final rows = await fetchAllPages(table.page, pageSize: 10);
      expect(rows.length, 7);
      expect(table.ranges, [(0, 9)]);
    });

    test('fetches past the 1000-row cap with the default page size', () async {
      final table = _FakeTable(2500);
      final rows = await fetchAllPages(table.page);
      expect(rows.length, 2500);
      expect(table.ranges, [(0, 999), (1000, 1999), (2000, 2999)]);
    });

    test('keeps every row once, in order, across pages', () async {
      final table = _FakeTable(23);
      final rows = await fetchAllPages(table.page, pageSize: 5);
      expect([for (final r in rows) r['id']], List.generate(23, (i) => i));
    });

    test('an exact multiple of the page size needs one extra empty request',
        () async {
      final table = _FakeTable(20);
      final rows = await fetchAllPages(table.page, pageSize: 10);
      expect(rows.length, 20);
      expect(table.ranges, [(0, 9), (10, 19), (20, 29)]);
    });

    test('propagates a failing page instead of returning partial rows',
        () async {
      var calls = 0;
      Future<List<Map<String, dynamic>>> page(int from, int to) async {
        calls++;
        if (calls == 2) throw const PostgrestException(message: 'boom');
        return [for (var i = from; i <= to; i++) {'id': i}];
      }

      await expectLater(fetchAllPages(page, pageSize: 3),
          throwsA(isA<PostgrestException>()));
    });

    test('rejects a non-positive page size', () {
      expect(() => fetchAllPages(_FakeTable(1).page, pageSize: 0),
          throwsArgumentError);
    });
  });

  group('isMissingTable', () {
    test('matches the Postgres and PostgREST missing-table codes', () {
      expect(
          isMissingTable(const PostgrestException(message: 'x', code: '42P01')),
          isTrue);
      expect(
          isMissingTable(
              const PostgrestException(message: 'x', code: 'PGRST205')),
          isTrue);
    });

    test('does not hide other errors', () {
      expect(
          isMissingTable(const PostgrestException(message: 'x', code: '42501')),
          isFalse);
      expect(isMissingTable(Exception('network down')), isFalse);
    });
  });
}
