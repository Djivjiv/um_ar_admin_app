import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/ui_helpers.dart';
import '../../data/repositories/auth_repository.dart';

class NavDestination {
  final String label;
  final IconData icon;
  final String route;
  const NavDestination(this.label, this.icon, this.route);
}

const kNavDestinations = <NavDestination>[
  NavDestination('Dashboard', Icons.dashboard_outlined, '/dashboard'),
  NavDestination('Buildings', Icons.apartment_outlined, '/buildings'),
  NavDestination('Rooms', Icons.meeting_room_outlined, '/rooms'),
  NavDestination('Facilities', Icons.room_preferences_outlined, '/facilities'),
  NavDestination('Campus Map', Icons.map_outlined, '/campus-map'),
  NavDestination('Floor Plans', Icons.layers_outlined, '/floor-plans'),
  NavDestination('Context Content', Icons.article_outlined, '/context-content'),
  NavDestination('About UM', Icons.info_outline, '/about-um'),
  NavDestination('Users', Icons.people_outline, '/users'),
  NavDestination(
      'Visitor Sessions', Icons.travel_explore_outlined, '/visitor-sessions'),
  NavDestination('Analytics', Icons.bar_chart_outlined, '/analytics'),
  NavDestination('SUS Responses', Icons.assignment_turned_in_outlined,
      '/sus-responses'),
];

class AdminSidebar extends StatelessWidget {
  const AdminSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final location =
        GoRouterState.of(context).uri.toString();

    return Container(
      width: 240,
      color: AppColors.sidebarBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SidebarHeader(),
          const Divider(color: Colors.white24, height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final dest in kNavDestinations)
                  _SidebarItem(
                    destination: dest,
                    active: location.startsWith(dest.route),
                  ),
              ],
            ),
          ),
          const Divider(color: Colors.white24, height: 1),
          const _SidebarFooter(),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentGold,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.navigation, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'UM Nav',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Matina Campus Admin',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final NavDestination destination;
  final bool active;

  const _SidebarItem({required this.destination, required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accentGold : Colors.white70;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.go(destination.route),
        child: Container(
          decoration: BoxDecoration(
            color: active ? AppColors.sidebarActiveBg : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: active ? AppColors.accentGold : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
          child: Row(
            children: [
              Icon(destination.icon, size: 20, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  destination.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13.5,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter();

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Log out'),
        content: const Text('Are you sure you want to end your session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AuthRepository.instance.signOut();
      if (context.mounted) context.go('/login');
    } catch (e) {
      if (context.mounted) context.showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = AuthRepository.instance.user?.email ?? 'admin@umindanao.edu.ph';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.accentGold,
                child: Icon(Icons.person, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  email,
                  style: const TextStyle(color: Colors.white, fontSize: 11.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: () => _logout(context),
              icon: const Icon(Icons.logout, size: 16),
              label: const Text('Logout'),
            ),
          ),
        ],
      ),
    );
  }
}
