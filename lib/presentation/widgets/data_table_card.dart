import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// A white card wrapper around [DataTable2] with an optional title and actions.
class DataTableCard extends StatelessWidget {
  final String? title;
  final List<Widget> actions;
  final List<DataColumn2> columns;
  final List<DataRow2> rows;
  final bool isLoading;
  final String emptyMessage;
  final double minWidth;

  const DataTableCard({
    super.key,
    this.title,
    this.actions = const [],
    required this.columns,
    required this.rows,
    this.isLoading = false,
    this.emptyMessage = 'No records found',
    this.minWidth = 900,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (title != null || actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  if (title != null)
                    Flexible(
                      child: Text(
                        title!,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  const Spacer(),
                  ...actions,
                ],
              ),
            ),
          Expanded(
            child: Builder(
              builder: (context) {
                if (isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (rows.isEmpty) {
                  return Center(
                    child: Text(
                      emptyMessage,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  );
                }
                return DataTable2(
                  columnSpacing: 16,
                  horizontalMargin: 16,
                  minWidth: minWidth,
                  headingRowColor: WidgetStatePropertyAll(
                    AppColors.backgroundGray.withValues(alpha: 0.6),
                  ),
                  columns: columns,
                  rows: rows,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
