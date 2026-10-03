import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import 'admin_header.dart';
import 'admin_sidebar.dart';

class AdminShell extends StatelessWidget {
  final Widget child;

  const AdminShell({super.key, required this.child});

  String _titleFor(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    for (final dest in kNavDestinations) {
      if (location.startsWith(dest.route)) return dest.label;
    }
    return 'UM-AR Nav Admin';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundGray,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AdminSidebar(),
          Expanded(
            child: Column(
              children: [
                AdminHeader(title: _titleFor(context)),
                const Divider(height: 1),
                Expanded(
                  child: Container(
                    color: AppColors.backgroundGray,
                    padding: const EdgeInsets.all(24),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
