import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/presentation/screens/analytics/analytics_screen.dart';
import 'package:um_ar_admin/presentation/screens/buildings/buildings_screen.dart';
import 'package:um_ar_admin/presentation/screens/dashboard/dashboard_screen.dart';
import 'package:um_ar_admin/presentation/screens/kiosk/kiosk_management_screen.dart';
import 'package:um_ar_admin/presentation/screens/sus_responses/sus_responses_screen.dart';

import 'support/fake_postgrest.dart';

/// These run in debug mode, where `setState` throws if its callback returns a
/// Future. A reload written `setState(() => _future = load())` does that, so
/// tapping it fails the test. The fake's failure text proves the error showed
/// before the tap and is gone after it.
const _error = 'server exploded';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1600, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
  await settle(tester);
}

void main() {
  late FakePostgrest db;

  setUp(() => db = FakePostgrest()..install());
  tearDown(FakePostgrest.uninstall);

  Future<void> retryAndExpectRecovery(WidgetTester tester) async {
    db.failing.clear();
    await tester.tap(find.text('Retry').first);
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.textContaining(_error), findsNothing);
  }

  group('Dashboard', () {
    testWidgets('Daily Trips Retry', (tester) async {
      db.failing.add('GET kiosk_sessions');
      await pumpScreen(tester, const DashboardScreen());
      expect(find.textContaining(_error), findsWidgets);
      await retryAndExpectRecovery(tester);
    });

    testWidgets('survey summary Retry', (tester) async {
      db.failing.add('GET sus_responses');
      await pumpScreen(tester, const DashboardScreen());
      expect(find.textContaining(_error), findsWidgets);
      await retryAndExpectRecovery(tester);
    });

    testWidgets('comments Retry', (tester) async {
      db.failing.add('GET feedback_comments');
      await pumpScreen(tester, const DashboardScreen());
      expect(find.textContaining(_error), findsOneWidget);
      await retryAndExpectRecovery(tester);
    });

    testWidgets('Most Visited Retry', (tester) async {
      db.failing.add('GET navigation_sessions');
      await pumpScreen(tester, const DashboardScreen());
      final before = find.text('Retry').evaluate().length;
      db.failing.clear();
      // In page order: the two daily charts, Most Visited, then System Status
      // (the MapTiler key is always missing in tests).
      await tester.tap(find.text('Retry').at(before - 2));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Retry').evaluate().length, before - 1);
      expect(find.text('No navigation data yet'), findsOneWidget);
    });

    testWidgets('System Status Retry', (tester) async {
      db.failing.add('HEAD indoor_nodes');
      await pumpScreen(tester, const DashboardScreen());
      expect(find.textContaining('Could not load indoor nodes'), findsOneWidget);
      db.failing.clear();
      await tester.tap(find.text('Retry').first);
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Could not load indoor nodes'), findsNothing);
    });
  });

  group('Analytics', () {
    testWidgets('Retry', (tester) async {
      db.failing.add('GET navigation_sessions');
      await pumpScreen(tester, const AnalyticsScreen());
      expect(find.textContaining(_error), findsOneWidget);
      await retryAndExpectRecovery(tester);
      expect(find.text('Navigation Evaluation'), findsOneWidget);
    });

    testWidgets('changing the date range reloads', (tester) async {
      await pumpScreen(tester, const AnalyticsScreen());
      final before = db.requestCount('GET navigation_sessions');
      await tester.tap(find.byIcon(Icons.date_range));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(db.requestCount('GET navigation_sessions'), greaterThan(before));
      expect(find.text('Navigation Evaluation'), findsOneWidget);
    });
  });

  testWidgets('SUS screen Retry', (tester) async {
    db.failing.add('GET sus_responses');
    await pumpScreen(tester, const SusResponsesScreen());
    expect(find.textContaining('Failed to load SUS responses'), findsOneWidget);
    db.failing.clear();
    await tester.tap(find.text('Retry').first);
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Failed to load SUS'), findsNothing);
  });

  testWidgets('Buildings Retry', (tester) async {
    db.failing.add('GET buildings');
    await pumpScreen(tester, const BuildingsScreen());
    expect(find.text('Retry'), findsOneWidget);
    db.failing.clear();
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Retry'), findsNothing);
  });

  group('Kiosk Analytics', () {
    Future<void> openTab(WidgetTester tester) async {
      await pumpScreen(tester, const KioskManagementScreen());
      await tester.tap(find.text('Analytics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
    }

    testWidgets('Retry', (tester) async {
      db.failing.add('GET kiosk_events');
      await openTab(tester);
      expect(find.text('Retry'), findsOneWidget);
      db.failing.clear();
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('the Refresh button', (tester) async {
      await openTab(tester);
      final before = db.requestCount('GET kiosk_events');
      await tester.tap(find.byTooltip('Refresh'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(db.requestCount('GET kiosk_events'), greaterThan(before));
    });

    testWidgets('changing the date range reloads', (tester) async {
      await openTab(tester);
      final before = db.requestCount('GET kiosk_events');
      await tester.tap(find.byIcon(Icons.date_range).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Just today, tapped as start and end: the default range is 7 days, and
      // saving a range unchanged rightly reloads nothing.
      final today = find.text('${DateTime.now().day}').last;
      await tester.tap(today);
      await tester.pump();
      await tester.tap(today);
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(db.requestCount('GET kiosk_events'), greaterThan(before));
    });
  });
}
