import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// A red inline notice for data that failed to load, with an optional
/// Retry button. Use it instead of silently showing empty data or zeros.
class ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  /// The button text, for actions other than retrying.
  final String retryLabel;
  final EdgeInsetsGeometry margin;

  const ErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.margin = const EdgeInsets.only(bottom: 8),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.errorRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppColors.errorRed),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style:
                    const TextStyle(color: AppColors.errorRed, fontSize: 12)),
          ),
          if (onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 15),
              label: Text(retryLabel),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.errorRed,
                  visualDensity: VisualDensity.compact),
            ),
        ],
      ),
    );
  }
}
