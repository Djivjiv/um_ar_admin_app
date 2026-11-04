import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:um_ar_admin/core/config/auth_redirect.dart';
import 'package:um_ar_admin/data/repositories/auth_repository.dart';
import 'package:um_ar_admin/data/repositories/repository_exception.dart';

import 'support/fake_postgrest.dart';

void main() {
  group('adminRedirect', () {
    test('not logged in goes to login', () {
      expect(
        adminRedirect(hasSession: false, isAdmin: false, atLogin: false),
        '/login',
      );
    });

    test('not logged in may stay on login', () {
      expect(
        adminRedirect(hasSession: false, isAdmin: false, atLogin: true),
        isNull,
      );
    });

    test('a logged-in non-admin is refused', () {
      expect(
        adminRedirect(hasSession: true, isAdmin: false, atLogin: false),
        '/login',
      );
    });

    test('a logged-in non-admin stays on login, not in a loop', () {
      expect(
        adminRedirect(hasSession: true, isAdmin: false, atLogin: true),
        isNull,
      );
    });

    test('a stale admin flag with no session is refused', () {
      expect(
        adminRedirect(hasSession: false, isAdmin: true, atLogin: false),
        '/login',
      );
    });

    test('an admin at login moves to the dashboard', () {
      expect(
        adminRedirect(hasSession: true, isAdmin: true, atLogin: true),
        '/dashboard',
      );
    });

    test('an admin stays where they are', () {
      expect(
        adminRedirect(hasSession: true, isAdmin: true, atLogin: false),
        isNull,
      );
    });
  });

  group('a real router', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool hasSession,
      required bool isAdmin,
    }) async {
      final router = GoRouter(
        initialLocation: '/users',
        redirect: (context, state) => adminRedirect(
          hasSession: hasSession,
          isAdmin: isAdmin,
          atLogin: state.matchedLocation == '/login',
        ),
        routes: [
          for (final page in ['/login', '/dashboard', '/users'])
            GoRoute(path: page, builder: (_, _) => Text('page $page')),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
    }

    testWidgets('a deep link while logged out lands on login', (tester) async {
      await pump(tester, hasSession: false, isAdmin: false);
      expect(find.text('page /login'), findsOneWidget);
    });

    testWidgets('a deep link as a non-admin lands on login', (tester) async {
      await pump(tester, hasSession: true, isAdmin: false);
      expect(find.text('page /login'), findsOneWidget);
    });

    testWidgets('a deep link as an admin stays', (tester) async {
      await pump(tester, hasSession: true, isAdmin: true);
      expect(find.text('page /users'), findsOneWidget);
    });
  });

  // AuthRepository is one object for the whole test file, bound to the client
  // installed first, so these share a server.
  group('signing in', () {
    late FakePostgrest db;

    setUpAll(() {
      db = FakePostgrest()
        ..authUser = {'id': 'uid-1', 'email': 'someone@umindanao.edu.ph'}
        ..install();
    });
    tearDownAll(FakePostgrest.uninstall);

    Future<void> signIn() => AuthRepository.instance
        .signInAsAdmin(email: 'someone@umindanao.edu.ph', password: 'pw');

    void profile(String? role, {bool active = true}) {
      db.tables['user_profiles'] = [
        if (role != null)
          {'id': 'uid-1', 'role': role, 'is_active': active},
      ];
    }

    Matcher refused(String text) => throwsA(isA<RepositoryException>()
        .having((e) => e.message, 'message', contains(text)));

    test('a non-admin is refused and signed straight out', () async {
      profile('student');
      await expectLater(signIn(), refused('do not have admin access'));
      expect(AuthRepository.instance.isAdmin, isFalse);
      expect(AuthRepository.instance.isLoggedIn, isFalse);
    });

    test('a deactivated admin is refused', () async {
      profile('admin', active: false);
      await expectLater(signIn(), refused('do not have admin access'));
      expect(AuthRepository.instance.canAccessAdmin, isFalse);
    });

    test('an account with no profile is refused', () async {
      profile(null);
      await expectLater(signIn(), refused('do not have admin access'));
    });

    test('an active admin gets in', () async {
      profile('admin');
      await signIn();
      expect(AuthRepository.instance.canAccessAdmin, isTrue);
      await AuthRepository.instance.signOut();
      expect(AuthRepository.instance.isAdmin, isFalse);
    });
  });
}
