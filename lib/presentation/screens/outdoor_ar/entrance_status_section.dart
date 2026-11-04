import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/entrance_links.dart';
import '../../widgets/error_banner.dart';

/// "Buildings with unlinked entrances" on the AR network check. Entrances
/// are campus map nodes (`outdoor_nodes`), not AR nodes, so this has its own
/// load and error state: a failure here says nothing about the AR network.
class EntranceStatusSection extends StatelessWidget {
  /// Null until loaded.
  final List<EntranceStatusRow>? rows;
  final Object? error;
  final VoidCallback onRetry;

  /// The display name of a building id.
  final String Function(int? buildingId) buildingName;

  const EntranceStatusSection({
    super.key,
    required this.rows,
    required this.error,
    required this.onRetry,
    required this.buildingName,
  });

  static const _title = TextStyle(fontSize: 13, fontWeight: FontWeight.bold);
  static const _small = TextStyle(fontSize: 11, color: AppColors.textSecondary);

  Widget _entrance(EntranceStatusRow r) {
    final name = r.entrance.entranceLabel ?? r.entrance.name ?? r.entrance.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            r.isLinked ? Icons.link : Icons.link_off,
            size: 15,
            color: r.isLinked ? AppColors.successGreen : AppColors.errorRed,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$name (${r.entrance.id})',
                    style: const TextStyle(fontSize: 12)),
                Text(r.detail ?? r.status.label, style: _small),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _grouped(Map<int?, List<EntranceStatusRow>> groups) {
    final ids = groups.keys.toList()
      ..sort((a, b) => buildingName(a)
          .toLowerCase()
          .compareTo(buildingName(b).toLowerCase()));
    return [
      for (final id in ids) ...[
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Text(buildingName(id),
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        for (final r in groups[id]!) _entrance(r),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final failure = error;
    if (failure != null) {
      return ErrorBanner(
        message: 'Could not check building entrances: $failure',
        onRetry: onRetry,
      );
    }
    final all = rows;
    if (all == null) return const LinearProgressIndicator();

    final unlinked = unlinkedByBuilding(all);
    final byBuilding = <int?, List<EntranceStatusRow>>{};
    for (final r in all) {
      (byBuilding[r.buildingId] ??= []).add(r);
    }
    final linked = all.where((r) => r.isLinked).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Buildings with unlinked entrances (${unlinked.length})',
            style: _title),
        const SizedBox(height: 4),
        Text(
          all.isEmpty
              ? 'No building entrances are marked on the campus map.'
              : '$linked of ${all.length} entrances are linked to their '
                  'indoor node. Fix the others in the Campus Map editor.',
          style: _small,
        ),
        ..._grouped(unlinked),
        if (all.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              title: Text('All entrances (${all.length})', style: _title),
              children: _grouped(byBuilding),
            ),
          ),
      ],
    );
  }
}
