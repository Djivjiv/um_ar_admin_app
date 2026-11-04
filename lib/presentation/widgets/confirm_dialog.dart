import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

class ConfirmDialog extends StatelessWidget {
  final String title;
  final String itemName;
  final String message;
  final String confirmLabel;

  /// Fills "Are you sure you want to [verb] …?".
  final String verb;

  const ConfirmDialog({
    super.key,
    this.title = 'Confirm deletion',
    required this.itemName,
    this.message = 'This action cannot be undone.',
    this.confirmLabel = 'Delete',
    this.verb = 'delete',
  });

  static Future<bool> show(
    BuildContext context, {
    String title = 'Confirm deletion',
    required String itemName,
    String message = 'This action cannot be undone.',
    String confirmLabel = 'Delete',
    String verb = 'delete',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmDialog(
        title: title,
        itemName: itemName,
        message: message,
        confirmLabel: confirmLabel,
        verb: verb,
      ),
    );
    return result ?? false;
  }

  /// Asks before making [itemName] inactive when [linkedNodes] indoor nodes
  /// point at it. With no linked nodes there is nothing to warn about.
  static Future<bool> showDeactivate(
    BuildContext context, {
    required String itemName,
    required int linkedNodes,
  }) async {
    if (linkedNodes == 0) return true;
    return show(
      context,
      title: 'Linked floor plan nodes',
      verb: 'deactivate',
      itemName: itemName,
      message: '$linkedNodes floor plan '
          '${linkedNodes == 1 ? 'node points' : 'nodes point'} at this. '
          'Navigation would dead-end there, so '
          '${linkedNodes == 1 ? 'it' : 'they'} will be unlinked. '
          'Reactivating later does not restore the links.',
      confirmLabel: 'Unlink and deactivate',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              children: [
                TextSpan(text: 'Are you sure you want to $verb '),
                TextSpan(
                  text: '"$itemName"',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: '?'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorRed),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
