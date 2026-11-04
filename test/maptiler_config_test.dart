import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/core/config/maptiler_config.dart';
import 'package:um_ar_admin/data/repositories/dashboard_repository.dart';
import 'package:um_ar_admin/presentation/widgets/maptiler_key_notice.dart';

import 'support/fake_postgrest.dart';

void main() {
  // Tests run without --dart-define, so this is the missing-key path.
  test('the key comes only from MAPTILER_KEY', () {
    expect(MapTilerConfig.apiKey, isEmpty);
    expect(MapTilerConfig.isConfigured, isFalse);
  });

  test('the message says how to fix it', () {
    expect(MapTilerConfig.missingKeyMessage,
        contains('--dart-define=MAPTILER_KEY'));
  });

  test('no key is left in the source', () {
    final literalKey = RegExp(r'''key=[A-Za-z0-9]{10,}|apiKey\s*=\s*['"]\w''');
    final mapTilerConst = RegExp(r'''(_mapTilerKey|_mtKey)\s*=\s*['"]''');
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final text = file.readAsStringSync();
      expect(text, isNot(matches(literalKey)), reason: file.path);
      expect(text, isNot(matches(mapTilerConst)), reason: file.path);
    }
  });

  testWidgets('the notice shows the message on a map', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: MapTilerKeyNotice()),
    ));
    expect(find.text(MapTilerConfig.missingKeyMessage), findsOneWidget);
  });

  test('the dashboard reports the missing key, without a network call',
      () async {
    FakePostgrest().install();
    addTearDown(FakePostgrest.uninstall);
    final status = await DashboardRepository().getSystemStatus();
    expect(status.mapTilerOk, isFalse);
    expect(status.errors, contains(MapTilerConfig.missingKeyMessage));
  });
}
