import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import 'repository_exception.dart';

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
    } on AuthException {
      throw RepositoryException('Invalid email or password');
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
    _isAdmin = true;
  }

  /// Looks the account up in `user_profiles` by id, then by email as a
  /// fallback (some deployments key the profile row on email, not the uid).
  Future<bool> _confirmAdmin(String uid, String? email) async {
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

    if (row == null) return false;
    final role = row['role']?.toString().toLowerCase();
    final active = row['is_active'] != false;
    return role == 'admin' && active;
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
