import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/data/repositories/admin_session_guard.dart';
import 'package:um_ar_admin/data/repositories/auth_repository.dart';
import 'package:um_ar_admin/presentation/screens/auth/login_screen.dart';
import 'package:um_ar_admin/presentation/screens/users/users_screen.dart';

import 'support/fake_postgrest.dart';

void main() {
  group('adminAccessOf', () {
    test('an active admin is valid', () {
      expect(adminAccessOf({'role': 'admin', 'is_active': true}),
          AdminAccess.valid);
      expect(adminAccessOf({'role': 'ADMIN'}), AdminAccess.valid,
          reason: 'a null is_active counts as active, as in is_admin()');
    });

    test('a deactivated admin is deactivated', () {
      expect(adminAccessOf({'role': 'admin', 'is_active': false}),
          AdminAccess.deactivated);
    });

    test('any other role is demoted', () {
      expect(adminAccessOf({'role': 'student', 'is_active': true}),
          AdminAccess.demoted);
      expect(adminAccessOf({'role': null}), AdminAccess.demoted);
    });

    test('no row is no profile', () {
      expect(adminAccessOf(null), AdminAccess.noProfile);
    });

    test('each lost access has its own reason', () {
      expect(adminAccessLostMessage(AdminAccess.deactivated),
          contains('deactivated'));
      expect(adminAccessLostMessage(AdminAccess.demoted),
          contains('no longer an admin'));
      expect(adminAccessLostMessage(AdminAccess.noProfile),
          contains('could not be found'));
    });
  });

  group('AdminSessionGuard', () {
    AdminSessionGuard guardCounting(void Function() onCheck) =>
        AdminSessionGuard(check: () async => onCheck());

    testWidgets('checks every 10 minutes, not before', (tester) async {
      var checks = 0;
      final guard = guardCounting(() => checks++)..start();

      await tester.pump(const Duration(minutes: 9, seconds: 59));
      expect(checks, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(checks, 1);
      await tester.pump(const Duration(minutes: 10));
      expect(checks, 2);
      guard.stop();
    });

    testWidgets('checks when the app returns to the foreground',
        (tester) async {
      var checks = 0;
      final guard = guardCounting(() => checks++)..start();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(checks, 0, reason: 'leaving the foreground is not a return');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(checks, 1);
      guard.stop();
    });

    testWidgets('stop ends both', (tester) async {
      var checks = 0;
      final guard = guardCounting(() => checks++)..start();
      guard.stop();

      await tester.pump(const Duration(minutes: 30));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(checks, 0);
    });
  });

  // AuthRepository is one object for the whole test file, bound to the client
  // installed first, so these share a server.
  group('recheckAdmin', () {
    late FakePostgrest db;
    AuthRepository auth() => AuthRepository.instance;

    setUpAll(() {
      db = FakePostgrest()
        ..authUser = {'id': 'uid-1', 'email': 'admin@umindanao.edu.ph'}
        ..install();
    });
    tearDownAll(FakePostgrest.uninstall);

    void profile(String? role, {bool active = true}) {
      db.tables['user_profiles'] = [
        if (role != null) {'id': 'uid-1', 'role': role, 'is_active': active},
      ];
    }

    Future<void> signInAsAdmin() async {
      db.failing.clear();
      db.onRequest = null;
      profile('admin');
      await auth().signInAsAdmin(
          email: 'admin@umindanao.edu.ph', password: 'pw');
      expect(auth().canAccessAdmin, isTrue);
    }

    tearDown(() async {
      db.failing.clear();
      db.onRequest = null;
      auth().takeSignOutReason();
      if (auth().isLoggedIn) await auth().signOut();
    });

    test('a still-valid admin stays signed in', () async {
      await signInAsAdmin();
      expect(await auth().recheckAdmin(), AdminAccess.valid);
      expect(auth().canAccessAdmin, isTrue);
      expect(auth().takeSignOutReason(), isNull);
    });

    test('a deactivated admin is signed out and told why', () async {
      await signInAsAdmin();
      profile('admin', active: false);
      expect(await auth().recheckAdmin(), AdminAccess.deactivated);
      expect(auth().canAccessAdmin, isFalse);
      expect(auth().isLoggedIn, isFalse);
      expect(auth().takeSignOutReason(), contains('deactivated'));
    });

    test('a demoted admin is signed out and told why', () async {
      await signInAsAdmin();
      profile('student');
      expect(await auth().recheckAdmin(), AdminAccess.demoted);
      expect(auth().isLoggedIn, isFalse);
      expect(auth().takeSignOutReason(), contains('no longer an admin'));
    });

    test('a removed profile is signed out', () async {
      await signInAsAdmin();
      profile(null);
      expect(await auth().recheckAdmin(), AdminAccess.noProfile);
      expect(auth().isLoggedIn, isFalse);
    });

    test('a failed check signs nobody out', () async {
      await signInAsAdmin();
      db.failing.add('GET user_profiles');
      expect(await auth().recheckAdmin(), AdminAccess.unknown);
      expect(auth().canAccessAdmin, isTrue);
      expect(auth().takeSignOutReason(), isNull);
    });

    test('the router hears about the sign-out', () async {
      await signInAsAdmin();
      profile('student');
      var notified = 0;
      void listener() => notified++;
      auth().addListener(listener);
      addTearDown(() => auth().removeListener(listener));
      await auth().recheckAdmin();
      expect(notified, greaterThan(0));
    });

    test('the reason is only given once', () async {
      await signInAsAdmin();
      profile('student');
      await auth().recheckAdmin();
      expect(auth().takeSignOutReason(), isNotNull);
      expect(auth().takeSignOutReason(), isNull);
    });

    test('nothing is read while signed out', () async {
      db.requests.clear();
      expect(await auth().recheckAdmin(), AdminAccess.unknown);
      expect(db.requests, isEmpty);
    });

    test('nothing is read in the moment before login confirms', () async {
      profile('admin');
      Future<AdminAccess>? during;
      db.onRequest = (key) {
        if (key == 'GET user_profiles') during ??= auth().recheckAdmin();
      };
      db.requests.clear();
      await auth().signInAsAdmin(
          email: 'admin@umindanao.edu.ph', password: 'pw');
      expect(await during, AdminAccess.unknown);
      expect(db.requestCount('GET user_profiles'), 1);
      expect(auth().canAccessAdmin, isTrue);
    });

    test('checks at the same moment share one read', () async {
      await signInAsAdmin();
      db.requests.clear();
      await Future.wait([auth().recheckAdmin(), auth().recheckAdmin()]);
      expect(db.requestCount('GET user_profiles'), 1);
    });

    test('a profile keyed on email still checks out', () async {
      db.failing.clear();
      db.tables['user_profiles'] = [
        {
          'id': 'other-id',
          'email': 'admin@umindanao.edu.ph',
          'role': 'admin',
          'is_active': true,
        },
      ];
      await auth().signInAsAdmin(
          email: 'admin@umindanao.edu.ph', password: 'pw');
      expect(await auth().recheckAdmin(), AdminAccess.valid);
    });

    group('on screen', () {
      Future<void> settle(WidgetTester tester) async {
        for (var i = 0; i < 25; i++) {
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pump();
        }
      }

      Future<void> pumpUsers(WidgetTester tester) async {
        tester.view.physicalSize = const Size(1800, 2600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
            const MaterialApp(home: Scaffold(body: UsersScreen())));
        await settle(tester);
      }

      testWidgets('the login screen shows why', (tester) async {
        await tester.runAsync(signInAsAdmin);
        profile('admin', active: false);
        await tester.runAsync(auth().recheckAdmin);
        await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
        expect(find.textContaining('your account was deactivated'),
            findsOneWidget);
      });

      testWidgets('a normal login screen shows no message', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
        expect(find.textContaining('signed out'), findsNothing);
      });

      testWidgets('the Users button confirms a valid admin', (tester) async {
        await tester.runAsync(signInAsAdmin);
        await pumpUsers(tester);
        await tester.tap(find.text('Re-check admin status'));
        await settle(tester);
        expect(find.text('You are still an active admin'), findsOneWidget);
      });

      testWidgets('the Users button signs out a demoted admin', (tester) async {
        await tester.runAsync(signInAsAdmin);
        await pumpUsers(tester);
        profile('student');
        await tester.tap(find.text('Re-check admin status'));
        await settle(tester);
        expect(auth().isLoggedIn, isFalse);
        expect(auth().takeSignOutReason(), contains('no longer an admin'));
      });

      testWidgets('the Users button says when it could not check',
          (tester) async {
        await tester.runAsync(signInAsAdmin);
        await pumpUsers(tester);
        db.failing.add('GET user_profiles');
        await tester.tap(find.text('Re-check admin status'));
        await settle(tester);
        expect(find.textContaining('Could not check'), findsOneWidget);
        expect(auth().isLoggedIn, isTrue);
      });
    });
  });
}
