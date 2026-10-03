import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

enum BadgeStatus { active, inactive, verified, restricted, pending, emergency }

class StatusBadge extends StatelessWidget {
  final BadgeStatus status;
  final String? label;

  const StatusBadge({super.key, required this.status, this.label});

  factory StatusBadge.fromBool(
    bool value, {
    String activeLabel = 'Active',
    String inactiveLabel = 'Inactive',
  }) {
    return StatusBadge(
      status: value ? BadgeStatus.active : BadgeStatus.inactive,
      label: value ? activeLabel : inactiveLabel,
    );
  }

  ({Color fg, Color bg, String text}) get _style {
    switch (status) {
      case BadgeStatus.active:
        return (fg: AppColors.successGreen, bg: AppColors.successGreen, text: 'Active');
      case BadgeStatus.verified:
        return (fg: AppColors.infoBlue, bg: AppColors.infoBlue, text: 'Verified');
      case BadgeStatus.pending:
        return (fg: AppColors.warningAmber, bg: AppColors.warningAmber, text: 'Pending');
      case BadgeStatus.restricted:
        return (fg: AppColors.errorRed, bg: AppColors.errorRed, text: 'Restricted');
      case BadgeStatus.emergency:
        return (fg: AppColors.errorRed, bg: AppColors.errorRed, text: 'Emergency');
      case BadgeStatus.inactive:
        return (fg: AppColors.textSecondary, bg: AppColors.textSecondary, text: 'Inactive');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _style;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: s.bg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: s.fg.withValues(alpha: 0.4)),
      ),
      child: Text(
        label ?? s.text,
        style: TextStyle(
          color: s.fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
