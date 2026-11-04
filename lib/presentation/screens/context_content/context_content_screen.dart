import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/building_repository.dart';
import '../../../data/repositories/content_repository.dart';
import '../../../data/repositories/paged_query.dart';
import '../../../domain/models/building_model.dart';
import '../../../domain/models/facility_content_model.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/slide_panel.dart';
import '../../widgets/status_badge.dart';
import 'content_form.dart';

class ContextContentScreen extends StatefulWidget {
  const ContextContentScreen({super.key});

  @override
  State<ContextContentScreen> createState() => _ContextContentScreenState();
}

class _ContextContentScreenState extends State<ContextContentScreen> {
  final _repo = ContentRepository();
  final _buildingRepo = BuildingRepository();

  List<FacilityContentModel> _items = [];
  List<BuildingModel> _buildings = [];
  bool _loading = true;
  Object? _error;
  int? _filterBuilding;
  String? _filterType;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.getAll(),
        // Every building, for names; pickers narrow it to the active ones.
        _buildingRepo.getAll(status: ActiveFilter.all),
      ]);
      setState(() {
        _items = results[0] as List<FacilityContentModel>;
        _buildings = results[1] as List<BuildingModel>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  List<FacilityContentModel> get _filtered => _items.where((c) {
        if (_filterBuilding != null && c.buildingId != _filterBuilding) {
          return false;
        }
        if (_filterType != null && c.type != _filterType) return false;
        return true;
      }).toList();

  String _buildingName(int? id) {
    final m = _buildings.where((b) => b.id == id);
    return m.isEmpty ? '—' : buildingOptionLabel(m.first);
  }

  Future<void> _openForm([FacilityContentModel? content]) async {
    final result = await SlidePanel.show<bool>(
      context,
      title: content == null ? 'Add Content' : 'Edit Content',
      subtitle: content?.title,
      body: ContentForm(
        content: content,
        buildings: selectableBuildings(_buildings, content?.buildingId),
      ),
    );
    if (result == true) _load();
  }

  Future<void> _toggle(FacilityContentModel c) async {
    try {
      await _repo.toggleActive(c.id!, !c.isActive);
      if (mounted) context.showSuccess('Status updated');
      _load();
    } catch (e) {
      if (mounted) context.showError(e, onRetry: () => _toggle(c));
    }
  }

  Future<void> _delete(FacilityContentModel c) async {
    final ok = await ConfirmDialog.show(context, itemName: c.title);
    if (!ok) return;
    try {
      await _repo.delete(c.id!);
      if (mounted) context.showSuccess('Deleted');
      _load();
    } catch (e) {
      if (mounted) context.showError(e, onRetry: () => _delete(c));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error.toString()),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<int?>(
                initialValue: _filterBuilding,
                decoration: const InputDecoration(
                    isDense: true, labelText: 'Building'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  for (final b
                      in selectableBuildings(_buildings, _filterBuilding))
                    DropdownMenuItem(
                        value: b.id, child: Text(buildingOptionLabel(b))),
                ],
                onChanged: (v) => setState(() => _filterBuilding = v),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String?>(
                initialValue: _filterType,
                decoration:
                    const InputDecoration(isDense: true, labelText: 'Type'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All types')),
                  for (final t in kContentTypes)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => setState(() => _filterType = v),
              ),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Content'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
                  ? const Center(child: Text('No content found'))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final cols = constraints.maxWidth > 900 ? 2 : 1;
                        return GridView.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            mainAxisExtent: 180,
                          ),
                          itemCount: _filtered.length,
                          itemBuilder: (context, i) {
                            final c = _filtered[i];
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.cardWhite,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(c.title,
                                            style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold),
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                      StatusBadge.fromBool(c.isActive),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${c.type ?? '—'} · ${_buildingName(c.buildingId)}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary),
                                  ),
                                  const SizedBox(height: 6),
                                  Expanded(
                                    child: Text(
                                      c.content ?? '',
                                      style: const TextStyle(fontSize: 12),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      const Spacer(),
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 18),
                                        onPressed: () => _openForm(c),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          c.isActive
                                              ? Icons.toggle_on
                                              : Icons.toggle_off,
                                          size: 20,
                                          color: c.isActive
                                              ? AppColors.successGreen
                                              : AppColors.textSecondary,
                                        ),
                                        onPressed: () => _toggle(c),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline,
                                            size: 18, color: AppColors.errorRed),
                                        onPressed: () => _delete(c),
                                      ),
                                    ],
                                  ),
                                ],
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
