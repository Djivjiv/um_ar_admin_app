import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/data/repositories/repository_exception.dart';
import 'package:um_ar_admin/data/repositories/user_repository.dart';
import 'package:um_ar_admin/domain/models/user_profile_model.dart';

import 'support/fake_postgrest.dart';

UserProfileModel _user(String id, String role,
        {String? email, bool active = true}) =>
    UserProfileModel(
        id: id, role: role, email: email ?? '$id@um.edu.ph', isActive: active);

void main() {
  final me = _user('me', 'admin', email: 'Me@UM.edu.ph');
  final other = _user('other', 'admin');
  final student = _user('s1', 'student');

  String? check(UserProfileModel target, String role,
          List<UserProfileModel> all,
          {String? id = 'me', String? email = 'me@um.edu.ph'}) =>
      roleChangeBlocker(
        target: target,
        newRole: role,
        allUsers: all,
        currentUserId: id,
        currentUserEmail: email,
      );

  group('roleChangeBlocker', () {
    test('lists the assignable roles, with the mobile app\'s employee', () {
      expect(kUserRoles,
          ['student', 'employee', 'faculty', 'admin', 'visitor']);
    });

    test('allows promoting and changing non-admins', () {
      final all = [me, student];
      expect(check(student, 'faculty', all), isNull);
      expect(check(student, 'employee', all), isNull);
      expect(check(student, 'visitor', all), isNull);
      expect(check(student, 'admin', all), isNull);
    });

    test('rejects unknown roles and no-op changes', () {
      expect(check(student, 'superuser', [me, student]), isNotNull);
      expect(check(student, 'student', [me, student]), isNotNull);
    });

    test('an admin cannot demote themselves (matched by id)', () {
      expect(check(me, 'faculty', [me, other]), contains('your own'));
    });

    test('self is also matched by email, case-insensitively', () {
      expect(
          check(me, 'faculty', [me, other], id: 'auth-uid-differs'),
          contains('your own'));
    });

    test('can demote another admin while an active admin remains', () {
      expect(check(other, 'faculty', [me, other]), isNull);
    });

    test('the last active admin cannot be demoted', () {
      final inactiveAdmin = _user('old', 'admin', active: false);
      // Signed in as someone else (e.g. a row keyed differently).
      expect(
          check(other, 'student', [other, inactiveAdmin, student],
              id: 'x', email: 'x@um.edu.ph'),
          contains('last active admin'));
    });

    test('role comparison ignores case', () {
      final upper = _user('u', 'Admin');
      expect(check(upper, 'faculty', [me, upper]), isNull);
      expect(check(upper, 'admin', [me, upper]), isNotNull); // no change
    });

    test('the only admin cannot demote themselves', () {
      expect(check(me, 'student', [me, student]), isNotNull);
    });
  });

  group('deactivateBlocker', () {
    String? check(UserProfileModel target, List<UserProfileModel> all) =>
        deactivateBlocker(
          target: target,
          allUsers: all,
          currentUserId: 'me',
          currentUserEmail: 'me@um.edu.ph',
        );

    test('non-admins can be deactivated', () {
      expect(check(student, [me, student]), isNull);
    });

    test('an admin cannot deactivate themselves', () {
      expect(check(me, [me, other]), contains('your own'));
    });

    test('another admin can go while one active admin remains', () {
      expect(check(other, [me, other]), isNull);
    });

    test('the last active admin cannot be deactivated', () {
      final inactive = _user('old', 'admin', active: false);
      expect(
        deactivateBlocker(
            target: other,
            allUsers: [other, inactive],
            currentUserId: 'x',
            currentUserEmail: 'x@um.edu.ph'),
        contains('last active admin'),
      );
    });

    test('an already inactive admin can stay inactive', () {
      final inactive = _user('old', 'admin', active: false);
      expect(check(inactive, [me, inactive]), isNull);
    });
  });

  group('isPendingApproval', () {
    UserProfileModel user(String? role,
            {bool verified = false,
            bool active = true,
            String email = 'a.cruz.123456@umindanao.edu.ph'}) =>
        UserProfileModel(
            id: 'u',
            role: role,
            email: email,
            isVerified: verified,
            isActive: active);

    test('a student with an email outside the student format is pending', () {
      const other = 'ana.cruz@umindanao.edu.ph';
      expect(user('student', email: other).isPendingApproval, isTrue);
      expect(user('Student', email: other).isPendingApproval, isTrue);
      expect(user('student', email: other, verified: true).isPendingApproval,
          isFalse);
    });

    test('unverified non-student UM accounts are pending', () {
      expect(user('faculty').isPendingApproval, isTrue);
      expect(user('employee').isPendingApproval, isTrue);
      expect(user('visitor').isPendingApproval, isTrue);
      expect(user(null).isPendingApproval, isTrue);
    });

    test('the email domain is matched case-insensitively', () {
      expect(
          user('faculty', email: 'A@UMindanao.EDU.PH').isPendingApproval,
          isTrue);
    });

    test('student-format students and admins never wait for approval', () {
      expect(user('student').isPendingApproval, isFalse);
      expect(user('Student').isPendingApproval, isFalse);
      expect(user('admin').isPendingApproval, isFalse);
    });

    test('verified, rejected and outside accounts are not pending', () {
      expect(user('faculty', verified: true).isPendingApproval, isFalse);
      expect(user('faculty', active: false).isPendingApproval, isFalse);
      expect(user('faculty', email: 'a@gmail.com').isPendingApproval, isFalse);
      expect(
        user('faculty', email: 'a@umindanao.edu.ph.evil.com')
            .isPendingApproval,
        isFalse,
      );
    });
  });

  group('UserRepository', () {
    late FakePostgrest db;
    Map<String, dynamic> row() => db.tables['user_profiles']!.single;

    setUp(() {
      db = FakePostgrest()..install();
      db.tables['user_profiles'] = [
        {
          'id': 'u1',
          'role': 'faculty',
          'email': 'a@umindanao.edu.ph',
          'is_verified': false,
          'is_active': true,
        },
      ];
    });
    tearDown(FakePostgrest.uninstall);

    test('approve verifies the account and clears it from pending', () async {
      final saved = await UserRepository().approveUser('u1');
      expect(row()['is_verified'], isTrue);
      expect(row()['is_active'], isTrue);
      expect(saved.isPendingApproval, isFalse);
    });

    test('reject leaves it unverified and inactive, out of pending', () async {
      final saved = await UserRepository().rejectUser('u1');
      expect(row()['is_verified'], isFalse);
      expect(row()['is_active'], isFalse);
      expect(saved.isPendingApproval, isFalse);
    });

    test('setRole saves any listed role, including visitor', () async {
      final saved = await UserRepository().setRole('u1', 'visitor');
      expect(saved.role, 'visitor');
      expect(row()['role'], 'visitor');
    });

    test('setRole rejects unknown roles without a request', () async {
      await expectLater(UserRepository().setRole('u1', 'superuser'),
          throwsA(isA<RepositoryException>()));
      expect(db.requests, isEmpty);
    });

    test('setRole passes on the database guard message', () async {
      db.failing.add('PATCH user_profiles');
      db.failureMessage = 'This is the last active admin';
      await expectLater(
        UserRepository().setRole('u1', 'student'),
        throwsA(isA<RepositoryException>().having((e) => e.message, 'message',
            contains('last active admin'))),
      );
    });
  });

  group('approving an account that has no role yet', () {
    String body(String function) {
      final sql = File('db/user_roles.sql').readAsStringSync();
      final start = sql.indexOf('function public.$function');
      expect(start, isNot(-1));
      return sql.substring(start, sql.indexOf(r'$$;', sql.indexOf(r'$$', start) + 2));
    }

    test('the role picker no longer resets is_verified', () {
      final guard = body('guard_user_profile_role');
      expect(guard, isNot(contains('new.is_verified := false')),
          reason: 'this line undid the admin\'s approval');
    });

    test('the role picker still sets a student-format account verified', () {
      expect(body('guard_user_profile_role'),
          contains('new.is_verified := true'));
    });

    test('the picker path still refuses any status change', () {
      expect(body('guard_user_profile_role'),
          contains('and not status_changed'));
    });

    test('a new account the app creates is still unverified', () {
      expect(body('guard_user_profile_insert'),
          contains('new.is_verified := false'));
    });

    test('once approved, the account leaves the pending list', () {
      const approved = UserProfileModel(
          id: 'u', email: 'a.b@umindanao.edu.ph', isVerified: true);
      expect(approved.isPendingApproval, isFalse);
    });
  });
}
