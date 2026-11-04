import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/auth_redirect.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/admin_theme.dart';
import 'data/repositories/admin_session_guard.dart';
import 'data/repositories/auth_repository.dart';
import 'domain/models/building_model.dart';
import 'domain/models/floor_plan_model.dart';
import 'presentation/layout/admin_shell.dart';
import 'presentation/screens/about_um/about_um_screen.dart';
import 'presentation/screens/announcements/announcements_screen.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/analytics/analytics_screen.dart';
import 'presentation/screens/buildings/buildings_screen.dart';
import 'presentation/screens/campus_map/campus_map_editor_screen.dart';
import 'presentation/screens/context_content/context_content_screen.dart';
import 'presentation/screens/dashboard/dashboard_screen.dart';
import 'presentation/screens/facilities/facilities_screen.dart';
import 'presentation/screens/floor_plans/floor_plan_editor_screen.dart';
import 'presentation/screens/floor_plans/floor_plans_screen.dart';
import 'presentation/screens/floor_plans/georeferencing_screen.dart';
import 'presentation/screens/feedback/feedback_comments_screen.dart';
import 'presentation/screens/kiosk/kiosk_management_screen.dart';
import 'presentation/screens/outdoor_ar/outdoor_ar_screen.dart';
import 'presentation/screens/rooms/rooms_screen.dart';
import 'presentation/screens/sus_responses/sus_responses_screen.dart';
import 'presentation/screens/users/users_screen.dart';
import 'presentation/screens/visitor_sessions/visitor_sessions_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  // Force a fresh start on every launch: Supabase restores a session from disk
  // during initialize(), so clear it here — the app must always begin at the
  // login screen and never resume a previous session.
  try {
    await SupabaseConfig.client.auth.signOut(scope: SignOutScope.local);
  } catch (_) {
    // No session to clear / offline — that's fine, we start logged out anyway.
  }
  runApp(const UmArAdminApp());
}

class UmArAdminApp extends StatefulWidget {
  const UmArAdminApp({super.key});

  @override
  State<UmArAdminApp> createState() => _UmArAdminAppState();
}

class _UmArAdminAppState extends State<UmArAdminApp> {
  StreamSubscription<AuthState>? _authSub;
  final _adminGuard =
      AdminSessionGuard(check: AuthRepository.instance.recheckAdmin);

  @override
  void initState() {
    super.initState();
    _authSub =
        SupabaseConfig.client.auth.onAuthStateChange.listen(_onAuthStateChange);
    _adminGuard.start();
  }

  void _onAuthStateChange(AuthState state) {
    final event = state.event;
    // A token refresh must not move the user off the page they are on.
    if (event == AuthChangeEvent.tokenRefreshed ||
        event == AuthChangeEvent.userUpdated) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final location =
          appRouter.routerDelegate.currentConfiguration.uri.toString();
      final atLogin = location.startsWith('/login');
      if (event == AuthChangeEvent.signedIn && atLogin) {
        appRouter.go('/dashboard');
      } else if (event == AuthChangeEvent.signedOut && !atLogin) {
        appRouter.go('/login');
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _adminGuard.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'UM-AR Nav Admin',
      debugShowCheckedModeBanner: false,
      theme: AdminTheme.light,
      routerConfig: appRouter,
    );
  }
}

final GoRouter appRouter = GoRouter(
  initialLocation: '/login',
  refreshListenable: AuthRepository.instance,
  redirect: (context, state) {
    // Read the live session directly. There is never a restored session at
    // launch (main() signs out), so this always sends a fresh launch to /login.
    return adminRedirect(
      hasSession: SupabaseConfig.client.auth.currentSession != null,
      isAdmin: AuthRepository.instance.isAdmin,
      atLogin: state.matchedLocation == '/login',
    );
  },
  routes: [
    GoRoute(
      path: '/login',
      pageBuilder: (context, state) =>
          const NoTransitionPage(child: LoginScreen()),
    ),
    // Full-screen (no sidebar/header) — the georeferencing map needs the
    // whole window, and draws its own back arrow / top bar.
    GoRoute(
      path: '/floor-plans/georeference',
      pageBuilder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? const {};
        return NoTransitionPage(
          child: GeoreferencingScreen(
            building: extra['building'] as BuildingModel,
            floorNumber: extra['floorNumber'] as int,
            floorLabel: extra['floorLabel'] as String,
            existingFloorPlan: extra['existingFloorPlan'] as FloorPlanModel?,
          ),
        );
      },
    ),
    ShellRoute(
      builder: (context, state, child) => AdminShell(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: DashboardScreen()),
        ),
        GoRoute(
          path: '/buildings',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: BuildingsScreen()),
        ),
        GoRoute(
          path: '/rooms',
          pageBuilder: (context, state) {
            final buildingId =
                int.tryParse(state.uri.queryParameters['building'] ?? '');
            return NoTransitionPage(
              child: RoomsScreen(initialBuildingId: buildingId),
            );
          },
        ),
        GoRoute(
          path: '/facilities',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: FacilitiesScreen()),
        ),
        GoRoute(
          path: '/campus-map',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: CampusMapEditorScreen()),
        ),
        GoRoute(
          path: '/outdoor-ar',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: OutdoorArScreen()),
        ),
        GoRoute(
          path: '/floor-plans',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: FloorPlansScreen()),
          routes: [
            GoRoute(
              path: ':id/edit',
              pageBuilder: (context, state) {
                final id =
                    int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
                return NoTransitionPage(
                  child: FloorPlanEditorScreen(floorPlanId: id),
                );
              },
            ),
          ],
        ),
        GoRoute(
          path: '/context-content',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ContextContentScreen()),
        ),
        GoRoute(
          path: '/announcements',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: AnnouncementsScreen()),
        ),
        GoRoute(
          path: '/about-um',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: AboutUmScreen()),
        ),
        GoRoute(
          path: '/users',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: UsersScreen()),
        ),
        GoRoute(
          path: '/visitor-sessions',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: VisitorSessionsScreen()),
        ),
        GoRoute(
          path: '/kiosk',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: KioskManagementScreen()),
        ),
        GoRoute(
          path: '/analytics',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: AnalyticsScreen()),
        ),
        GoRoute(
          path: '/sus-responses',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: SusResponsesScreen()),
        ),
        GoRoute(
          path: '/feedback-comments',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: FeedbackCommentsScreen()),
        ),
      ],
    ),
  ],
);
