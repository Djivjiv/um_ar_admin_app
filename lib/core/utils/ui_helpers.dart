import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

extension SnackbarX on BuildContext {
  void showSuccess(String message) {
    ScaffoldMessenger.of(this)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.successGreen,
        ),
      );
  }

  /// Shows [error]. With [onRetry] the message stays up with a Retry button,
  /// so a failed save can't be missed.
  void showError(Object error, {VoidCallback? onRetry}) {
    ScaffoldMessenger.of(this)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: AppColors.errorRed,
          action: onRetry == null
              ? null
              : SnackBarAction(
                  label: 'Retry',
                  textColor: Colors.white,
                  onPressed: onRetry,
                ),
        ),
      );
  }

  /// Non-blocking heads-up (the action still went through).
  void showWarning(String message) {
    ScaffoldMessenger.of(this)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.warningAmber,
        ),
      );
  }

  void showInfo(String message) {
    ScaffoldMessenger.of(this)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
