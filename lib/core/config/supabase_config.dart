import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Holds Supabase credentials and the one-time initialization entrypoint.
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = 'https://yoqsjjnhmluqivkgiwoa.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
      'eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlvcXNqam5obWx1cWl2a2dpd29hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU0ODQzMTcsImV4cCI6MjEwMTA2MDMxN30.'
      'xnRaFoN2k1GfThYYLkGztzGSWmVzE8gVNgpgBpZDmC8';

  /// Replaces [client] in tests, so repositories can run against a fake
  /// server without [initialize].
  @visibleForTesting
  static SupabaseClient? testClient;

  /// The shared Supabase client. Only valid after [initialize] completes.
  static SupabaseClient get client => testClient ?? Supabase.instance.client;

  /// Must be called once in `main()` before `runApp`.
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: url,
      // Legacy JWT anon key. supabase_flutter accepts it via publishableKey.
      publishableKey: anonKey,
      debug: false,
    );
  }
}
