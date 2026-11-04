import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import 'repository_exception.dart';

/// The login-screen message for a failed `signInWithPassword`.
String authErrorMessage(AuthException e) {
  if (e is AuthRetryableFetchException) {
    return 'Could not reach the server. Check your connection and try again.';
  }
  switch (e.code) {
    case 'email_not_confirmed':
      return 'This email address has not been confirmed yet. '
          'Open the confirmation link sent to your inbox, then sign in.';
    case 'over_request_rate_limit':
    case 'over_email_send_rate_limit':
      return 'Too many sign-in attempts. Wait a few minutes and try again.';
    case 'user_banned':
      return 'This account has been disabled.';
  }
  if (e.statusCode == '429') {
    return 'Too many sign-in attempts. Wait a few minutes and try again.';
  }
  return 'Invalid email or password';
}

/// What `user_profiles` says about a signed-in account's admin access.
enum AdminAccess {
  valid,
  deactivated,
  demoted,
  noProfile,

  /// Couldn't be checked; nothing is known either way.
  unknown,
}

/// [row] is the account's `user_profiles` row, or null with none. A null
/// `is_active` counts as active, as in the database's `is_admin()`.
AdminAccess adminAccessOf(Map<String, dynamic>? row) {
  if (row == null) return AdminAccess.noProfile;
  if (row['is_active'] == false) return AdminAccess.deactivated;
  return row['role']?.toString().toLowerCase() == 'admin'
      ? AdminAccess.valid
      : AdminAccess.demoted;
}

/// The login screen's message after [access] ended a session.
String adminAccessLostMessage(AdminAccess access) => switch (access) {
      AdminAccess.deactivated =>
        'You were signed out because your account was deactivated. Ask '
            'another admin to reactivate it.',
      AdminAccess.demoted =>
        'You were signed out because your account is no longer an admin.',
      _ => 'You were signed out because your account profile could not be '
          'found.',
    };

/// Wraps Supabase Auth and exposes a [Listenable] that go_router refreshes on.
///
/// Crucially, [notifyListeners] fires **only when the signed-in identity
/// actually changes** (sign in / sign out), never on token refreshes or
/// unrelated rebuilds — so the router redirect does not thrash.
class AuthRepository extends ChangeNotifier {
  AuthRepository._() {
    _lastUserId = _client.auth.currentSession?.user.id;
    _sub = _client.auth.onAuthStateChange.listen(_handleAuthChange);
  }

  static final AuthRepository instance = AuthRepository._();

  final SupabaseClient _client = SupabaseConfig.client;
  late final StreamSubscription<AuthState> _sub;

  String? _lastUserId;
  bool _isAdmin = false;
  String? _signOutReason;
  Future<AdminAccess>? _recheck;

  Session? get session => _client.auth.currentSession;
  User? get user => _client.auth.currentUser;

  /// True when there is a live Supabase session.
  bool get isLoggedIn => session != null;

  /// True when the current session belongs to a verified admin account.
  bool get isAdmin => _isAdmin;

  /// Passes the router guard only for an authenticated admin.
  bool get canAccessAdmin => isLoggedIn && _isAdmin;

  void _handleAuthChange(AuthState state) {
    final event = state.event;
    final newUserId = state.session?.user.id;
    final identityChanged = newUserId != _lastUserId;

    // Token refresh / silent user updates keep the same identity — the router
    // has nothing to do, so don't notify and don't re-run redirect.
    if (!identityChanged &&
        event != AuthChangeEvent.signedIn &&
        event != AuthChangeEvent.signedOut) {
      return;
    }

    if (event == AuthChangeEvent.signedOut || newUserId == null) {
      _isAdmin = false;
    }

    _lastUserId = newUserId;
    notifyListeners();
  }

  /// Signs in with email + password and confirms the account is an active
  /// admin in `user_profiles`. Non-admins are signed straight back out.
  ///
  /// Throws [RepositoryException] with a user-facing message on any failure.
  Future<void> signInAsAdmin({
    required String email,
    required String password,
  }) async {
    late final AuthResponse response;
    try {
      response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on AuthException catch (e) {
      throw RepositoryException(authErrorMessage(e), e);
    } catch (e) {
      throw RepositoryException('Unable to sign in right now', e);
    }

    final authUser = response.user;
    if (authUser == null || response.session == null) {
      throw RepositoryException('Invalid email or password');
    }

    final bool isAdmin;
    try {
      isAdmin = await _confirmAdmin(authUser.id, authUser.email);
    } catch (e) {
      await _client.auth.signOut();
      throw RepositoryException('Could not verify admin access', e);
    }

    if (!isAdmin) {
      await _client.auth.signOut();
      throw RepositoryException('You do not have admin access');
    }
    // The signedIn event already notified while _isAdmin was still false, so
    // the router stayed on /login. Notify again now that admin is confirmed;
    // the redirect then moves to /dashboard with no polling or delay.
    _isAdmin = true;
    notifyListeners();
  }

  Future<bool> _confirmAdmin(String uid, String? email) async =>
      adminAccessOf(await _profileRow(uid, email)) == AdminAccess.valid;

  /// Checks the signed-in admin again. Admin status is otherwise only read at
  /// login, so a deactivated or demoted admin would keep the app open. If
  /// access is gone they are signed out, and [takeSignOutReason] says why. A
  /// failed read changes nothing: a dropped connection isn't a lost role.
  Future<AdminAccess> recheckAdmin() => _recheck ??= _runRecheck().whenComplete(
        () => _recheck = null,
      );

  Future<AdminAccess> _runRecheck() async {
    final account = user;
    if (!canAccessAdmin || account == null) return AdminAccess.unknown;

    final AdminAccess access;
    try {
      access = adminAccessOf(await _profileRow(account.id, account.email));
    } catch (e) {
      debugPrint('admin status check failed: $e');
      return AdminAccess.unknown;
    }
    // Signed out, or someone else signed in, while the read was running.
    if (access == AdminAccess.valid || user?.id != account.id) return access;

    _signOutReason = adminAccessLostMessage(access);
    _isAdmin = false;
    try {
      await _client.auth.signOut();
    } catch (e) {
      debugPrint('sign-out after losing admin access failed: $e');
    }
    notifyListeners();
    return access;
  }

  /// Why the app signed this admin out, once, for the login screen to show.
  String? takeSignOutReason() {
    final reason = _signOutReason;
    _signOutReason = null;
    return reason;
  }

  /// Looks the account up in `user_profiles` by id, then by email as a
  /// fallback (some deployments key the profile row on email, not the uid).
  Future<Map<String, dynamic>?> _profileRow(String uid, String? email) async {
    Map<String, dynamic>? row = await _client
        .from('user_profiles')
        .select('role, is_active')
        .eq('id', uid)
        .maybeSingle();

    if (row == null && email != null && email.isNotEmpty) {
      row = await _client
          .from('user_profiles')
          .select('role, is_active')
          .eq('email', email)
          .maybeSingle();
    }
    return row;
  }

  Future<void> signOut() async {
    try {
      _isAdmin = false;
      await _client.auth.signOut();
    } catch (e) {
      throw RepositoryException('Failed to sign out', e);
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
