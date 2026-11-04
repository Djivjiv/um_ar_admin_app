import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:um_ar_admin/core/config/supabase_config.dart';

/// An in-memory PostgREST behind the real Supabase client, so tests run the
/// repositories' actual queries. Like Supabase it caps every response at
/// [maxRows], whatever the request asked for.
class FakePostgrest {
  FakePostgrest({this.maxRows = 1000});

  final int maxRows;
  final Map<String, List<Map<String, dynamic>>> tables = {};

  /// "METHOD table", in order, for every request.
  final List<String> requests = [];

  /// Tables whose writes match no rows, as Row Level Security does.
  final Set<String> rlsBlockedWrites = {};

  /// Tables that fill in `id` on insert, as a column default does.
  final Set<String> generatedIds = {};

  /// "METHOD table" keys that fail with [failureMessage] while listed.
  final Set<String> failing = {};
  String failureMessage = 'server exploded';
  String failureCode = 'XX000';

  /// The account the auth endpoints sign in, when a test needs one.
  Map<String, dynamic>? authUser;

  /// Runs before each request is handled; lets a test change state mid-flow.
  void Function(String key)? onRequest;

  late final SupabaseClient client = SupabaseClient(
    'http://fake.supabase.test',
    'test-key',
    httpClient: MockClient(_handle),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  /// Makes every repository created from now on use this server.
  void install() => SupabaseConfig.testClient = client;

  static void uninstall() => SupabaseConfig.testClient = null;

  int requestCount(String key) => requests.where((r) => r == key).length;

  http.Response _auth(http.Request request) {
    if (request.url.path.endsWith('/logout')) {
      return http.Response('', 204, request: request);
    }
    return _json({
      'access_token': 'test-access-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'refresh_token': 'test-refresh-token',
      'user': {
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        ...?authUser,
      },
    }, 200, request);
  }

  Future<http.Response> _handle(http.Request request) async {
    if (request.url.path.contains('/auth/v1/')) return _auth(request);
    final table = request.url.pathSegments.last;
    final key = '${request.method} $table';
    requests.add(key);
    onRequest?.call(key);
    if (failing.contains(key)) {
      // A real HEAD answer has no body, so only the status gets through.
      if (request.method == 'HEAD') {
        return http.Response(
            '', failureCode == 'PGRST205' ? 404 : 500, request: request);
      }
      return _json(
          {'message': failureMessage, 'code': failureCode}, 500, request);
    }

    final rows = tables[table] ??= [];
    final matched = rows.where((r) => _matches(r, request.url)).toList();
    final wantsRows =
        request.headers['Prefer']?.contains('return=representation') ?? false;
    final blocked = rlsBlockedWrites.contains(table);

    switch (request.method) {
      case 'HEAD':
        return http.Response('', 200,
            request: request,
            headers: {'content-range': '*/${matched.length}'});
      case 'GET':
        _sort(matched, request.url.queryParameters['order']);
        final offset =
            int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0;
        final limit =
            int.tryParse(request.url.queryParameters['limit'] ?? '') ?? maxRows;
        final page = matched
            .skip(offset)
            .take(limit < maxRows ? limit : maxRows)
            .toList();
        return _rowsResponse(page, request);
      case 'PATCH':
        if (blocked) return _rowsResponse(const [], request);
        final values = jsonDecode(request.body) as Map<String, dynamic>;
        for (final r in matched) {
          r.addAll(values);
        }
        return wantsRows
            ? _rowsResponse(matched, request)
            : http.Response('', 204, request: request);
      case 'POST':
        rows.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (generatedIds.contains(table)) {
          rows.last['id'] ??= 'generated-${rows.length}';
        }
        return wantsRows
            ? _rowsResponse([rows.last], request)
            : http.Response('', 201, request: request);
      case 'DELETE':
        if (blocked) return _rowsResponse(const [], request);
        rows.removeWhere(matched.contains);
        return wantsRows
            ? _rowsResponse(matched, request)
            : http.Response('', 204, request: request);
    }
    return _json(
        {'message': 'unsupported ${request.method}'}, 501, request);
  }

  http.Response _rowsResponse(
      List<Map<String, dynamic>> rows, http.Request request) {
    final accept = request.headers['Accept'] ?? '';
    if (accept.contains('vnd.pgrst.object')) {
      if (rows.length != 1) {
        return _json({
          'message': 'JSON object requested, multiple (or no) rows returned',
          'code': 'PGRST116',
        }, 406, request);
      }
      return _json(rows.single, 200, request);
    }
    return _json(rows, 200, request);
  }

  http.Response _json(Object body, int status, http.Request request) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        request: request,
        headers: {'content-type': 'application/json'},
      );

  bool _matches(Map<String, dynamic> row, Uri url) {
    for (final entry in url.queryParametersAll.entries) {
      if (const {'select', 'order', 'limit', 'offset'}.contains(entry.key)) {
        continue;
      }
      for (final value in entry.value) {
        if (entry.key == 'or') {
          final inner = value.substring(1, value.length - 1);
          final anyMatch = inner.split(',').any((part) {
            final dot = part.indexOf('.');
            return _test(row[part.substring(0, dot)], part.substring(dot + 1));
          });
          if (!anyMatch) return false;
        } else if (!_test(row[entry.key], value)) {
          return false;
        }
      }
    }
    return true;
  }

  /// Evaluates a PostgREST filter such as `eq.5`, `not.is.false`, `in.(a,b)`.
  bool _test(Object? cell, String filter) {
    if (filter.startsWith('not.')) return !_test(cell, filter.substring(4));
    final dot = filter.indexOf('.');
    final op = filter.substring(0, dot);
    final arg = filter.substring(dot + 1);
    switch (op) {
      case 'eq':
        return '$cell' == arg;
      case 'neq':
        return cell != null && '$cell' != arg;
      case 'is':
        return arg == 'null' ? cell == null : '$cell' == arg;
      case 'in':
        final list = arg.substring(1, arg.length - 1).split(',');
        return list.map((s) => s.replaceAll('"', '')).contains('$cell');
      case 'gt':
        return '$cell'.compareTo(arg) > 0;
      case 'gte':
        return '$cell'.compareTo(arg) >= 0;
      case 'lt':
        return '$cell'.compareTo(arg) < 0;
      case 'lte':
        return '$cell'.compareTo(arg) <= 0;
      case 'ilike':
        return '$cell'
            .toLowerCase()
            .contains(arg.replaceAll('%', '').toLowerCase());
    }
    throw UnsupportedError('filter $filter');
  }

  void _sort(List<Map<String, dynamic>> rows, String? order) {
    if (order == null) return;
    final keys = order.split(',').map((o) => o.split('.')).toList();
    rows.sort((a, b) {
      for (final key in keys) {
        final descending = key.length > 1 && key[1] == 'desc';
        final x = a[key[0]];
        final y = b[key[0]];
        final byValue = x is num && y is num
            ? x.compareTo(y)
            : '$x'.compareTo('$y');
        if (byValue != 0) return descending ? -byValue : byValue;
      }
      return 0;
    });
  }
}
