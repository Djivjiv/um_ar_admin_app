import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/no_rooms_buildings.dart';
import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/building_repository.dart';
import '../../../data/repositories/paged_query.dart';
import '../../../domain/models/building_model.dart';
import '../../widgets/active_filter_dropdown.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/slide_panel.dart';
import '../../widgets/status_badge.dart';
import 'building_form.dart';

class BuildingsScreen extends StatefulWidget {
  const BuildingsScreen({super.key});

  @override
  State<BuildingsScreen> createState() => _BuildingsScreenState();
}

class _BuildingsScreenState extends State<BuildingsScreen> {
  final _repo = BuildingRepository();
  late Future<List<BuildingModel>> _future;
  ActiveFilter _status = ActiveFilter.active;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _future = _repo.getAll(status: _status);
  }

  void _reload() {
    setState(() {
      _future = _repo.getAll(status: _status);
    });
  }

  Future<void> _openForm([BuildingModel? building]) async {
    final result = await SlidePanel.show<bool>(
      context,
      title: building == null ? 'Add Building' : 'Edit Building',
      subtitle: building?.name,
      body: BuildingForm(building: building),
    );
    if (result == true) _reload();
  }

  Future<void> _delete(BuildingModel b) async {
    final ok = await ConfirmDialog.show(
      context,
      itemName: b.name,
      message: 'Floor plan nodes linked to its rooms and facilities will be '
          'unlinked. This action cannot be undone.',
    );
    if (!ok) return;
    try {
      await _repo.delete(b.id!);
      if (mounted) context.showSuccess('Building deleted');
      _reload();
    } catch (e) {
      if (mounted) context.showError(e, onRetry: () => _delete(b));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search buildings…',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onChanged: (v) => setState(() => _search = v.toLowerCase()),
              ),
            ),
            const SizedBox(width: 12),
            ActiveFilterDropdown(
              value: _status,
              onChanged: (v) {
                _status = v;
                _reload();
              },
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Building'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: FutureBuilder<List<BuildingModel>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _RetryBox(error: snapshot.error!, onRetry: _reload);
              }
              final all = List<BuildingModel>.from(snapshot.data ?? []);
              // Alphabetical order by name (case-insensitive).
              all.sort((a, b) =>
                  a.name.toLowerCase().compareTo(b.name.toLowerCase()));
              final items = all
                  .where((b) =>
                      b.name.toLowerCase().contains(_search) ||
                      (b.shortName ?? '').toLowerCase().contains(_search))
                  .toList();
              if (items.isEmpty) {
                return Center(
                  child: Text(_status == ActiveFilter.inactive
                      ? 'No inactive buildings found'
                      : 'No buildings found'),
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final cols = constraints.maxWidth > 1200
                      ? 3
                      : constraints.maxWidth > 760
                          ? 2
                          : 1;
                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      mainAxisExtent: 320,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _BuildingCard(
                      building: items[i],
                      onEdit: () => _openForm(items[i]),
                      onDelete: () => _delete(items[i]),
                      onViewRooms: () =>
                          context.go('/rooms?building=${items[i].id}'),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BuildingCard extends StatelessWidget {
  final BuildingModel building;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onViewRooms;

  const _BuildingCard({
    required this.building,
    required this.onEdit,
    required this.onDelete,
    required this.onViewRooms,
  });

  @override
  Widget build(BuildContext context) {
    final showRooms = buildingHasRooms(building.name);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 130,
            child: building.imageUrl != null && building.imageUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: building.imageUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const _ImgFallback(),
                  )
                : const _ImgFallback(),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        building.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!building.isActive) StatusBadge.fromBool(false),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  building.shortName ?? '—',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.layers,
                        size: 13, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text('${building.floorCount ?? '?'} floors',
                        style: const TextStyle(fontSize: 11)),
                    const SizedBox(width: 12),
                    if (building.isAccessible)
                      const Icon(Icons.accessible,
                          size: 14, color: AppColors.infoBlue),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  children: [
                    for (final d in building.departments.take(3))
                      Chip(
                        label: Text(d, style: const TextStyle(fontSize: 10)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (showRooms)
                      TextButton.icon(
                        onPressed: onViewRooms,
                        icon: const Icon(Icons.meeting_room, size: 15),
                        label: const Text('View Rooms'),
                        style: TextButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6)),
                      ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Edit',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit, size: 18),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: AppColors.errorRed),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImgFallback extends StatelessWidget {
  const _ImgFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.backgroundGray,
      child: const Center(
        child: Icon(Icons.apartment, size: 40, color: AppColors.textSecondary),
      ),
    );
  }
}

class _RetryBox extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _RetryBox({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(error.toString()),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
