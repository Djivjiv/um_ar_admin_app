import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

class AdminHeader extends StatelessWidget {
  final String title;
  final ValueChanged<String>? onSearch;

  const AdminHeader({super.key, required this.title, this.onSearch});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      width: double.infinity,
      color: AppColors.cardWhite,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 280,
            height: 40,
            child: TextField(
              onChanged: onSearch,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Search…',
                prefixIcon: Icon(Icons.search, size: 18),
                contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 12),
              ),
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none),
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          const CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primaryMaroon,
            child: Icon(Icons.person, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }
}
