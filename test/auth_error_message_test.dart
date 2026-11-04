import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:um_ar_admin/data/repositories/auth_repository.dart';

void main() {
  group('authErrorMessage', () {
    test('wrong credentials stay "Invalid email or password"', () {
      expect(
        authErrorMessage(const AuthApiException('Invalid login credentials',
            statusCode: '400', code: 'invalid_credentials')),
        'Invalid email or password',
      );
    });

    test('unconfirmed email gets its own message', () {
      final msg = authErrorMessage(const AuthApiException(
          'Email not confirmed',
          statusCode: '400',
          code: 'email_not_confirmed'));
      expect(msg, contains('not been confirmed'));
    });

    test('rate limit by error code', () {
      final msg = authErrorMessage(const AuthApiException('Too many requests',
          statusCode: '429', code: 'over_request_rate_limit'));
      expect(msg, contains('Too many sign-in attempts'));
    });

    test('rate limit by HTTP 429 when no code is sent', () {
      final msg = authErrorMessage(
          const AuthException('Too many requests', statusCode: '429'));
      expect(msg, contains('Too many sign-in attempts'));
    });

    test('network failure is not reported as a wrong password', () {
      final msg = authErrorMessage(AuthRetryableFetchException());
      expect(msg, contains('Could not reach the server'));
    });

    test('a disabled account says so', () {
      final msg = authErrorMessage(const AuthApiException('User is banned',
          statusCode: '400', code: 'user_banned'));
      expect(msg, contains('disabled'));
    });
  });
}
