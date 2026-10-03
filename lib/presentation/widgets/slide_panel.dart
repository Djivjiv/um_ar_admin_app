import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// A 400px animated panel that slides in from the right edge of the screen.
///
/// Use [SlidePanel.show] to present it as an overlay route.
class SlidePanel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? footer;

  const SlidePanel({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    this.footer,
  });

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? subtitle,
    required Widget body,
    Widget? footer,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => Align(
        alignment: Alignment.centerRight,
        child: SlidePanel(
          title: title,
          subtitle: subtitle,
          body: body,
          footer: footer,
        ),
      ),
      transitionBuilder: (_, anim, _, child) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardWhite,
      child: SizedBox(
        width: 400,
        height: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 4, color: AppColors.accentGold),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitle!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: body,
              ),
            ),
            if (footer != null) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: footer!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
