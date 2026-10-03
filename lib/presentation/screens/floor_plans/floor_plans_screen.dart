import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/no_rooms_buildings.dart';
import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/building_repository.dart';
import '../../../data/repositories/floor_plan_repository.dart';
import '../../../domain/models/building_model.dart';
import '../../../domain/models/floor_plan_model.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/image_upload.dart';
import '../../widgets/slide_panel.dart';

class FloorPlansScreen extends StatefulWidget {
  const FloorPlansScreen({super.key});

  @override
  State<FloorPlansScreen> createState() => _FloorPlansScreenState();
}

class _FloorPlansScreenState extends State<FloorPlansScreen> {
  final _repo = FloorPlanRepository();
  final _buildingRepo = BuildingRepository();

  List<FloorPlanModel> _plans = [];
  List<BuildingModel> _buildings = [];
  bool _loading = true;
  Object? _error;

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
        _buildingRepo.getAll(),
      ]);
      setState(() {
        _plans = results[0] as List<FloorPlanModel>;
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

  String _buildingName(int? id) {
    final m = _buildings.where((b) => b.id == id);
    return m.isEmpty ? '#$id' : m.first.name;
  }

  Future<void> _openForm([FloorPlanModel? plan]) async {
    final result = await SlidePanel.show<bool>(
      context,
      title: plan == null ? 'Upload Floor Plan' : 'Edit Floor Plan',
      body: _FloorPlanForm(
        plan: plan,
        buildings:
            _buildings.where((b) => buildingHasRooms(b.name)).toList(),
        repo: _repo,
      ),
    );
    if (result == true) _load();
  }

  /// New-upload flow: collect building/floor metadata, pick a local image
  /// file, then hand off to the georeferencing screen — the image isn't
  /// uploaded to Supabase Storage until the admin saves there.
  Future<void> _startNewUpload() async {
    final meta = await showDialog<_NewFloorMeta>(
      context: context,
      builder: (_) => _NewFloorPlanDialog(
        buildings: _buildings.where((b) => buildingHasRooms(b.name)).toList(),
      ),
    );
    if (meta == null || !mounted) return;

    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.first.path;
    if (path == null) {
      if (mounted) {
        context.showError('Could not read the selected image file.');
      }
      return;
    }
    if (!mounted) return;
    context.go('/floor-plans/georeference', extra: {
      'building': meta.building,
      'floorNumber': meta.floorNumber,
      'floorLabel': meta.floorLabel,
      'imageFile': File(path),
      'existingFloorPlan': null,
    });
  }

  void _openGeoreference(FloorPlanModel plan) {
    final match = _buildings.where((b) => b.id == plan.buildingId);
    final building = match.isEmpty
        ? BuildingModel(id: plan.buildingId, name: _buildingName(plan.buildingId))
        : match.first;
    context.go('/floor-plans/georeference', extra: {
      'building': building,
      'floorNumber': plan.floorNumber ?? 1,
      'floorLabel': plan.floorName ?? 'Floor ${plan.floorNumber ?? 1}',
      'imageFile': null,
      'existingFloorPlan': plan,
    });
  }

  Future<void> _delete(FloorPlanModel plan) async {
    final ok = await ConfirmDialog.show(context,
        itemName: plan.floorName ?? 'Floor ${plan.floorNumber}');
    if (!ok) return;
    try {
      await _repo.delete(plan.id!);
      if (mounted) context.showSuccess('Floor plan deleted');
      _load();
    } catch (e) {
      if (mounted) context.showError(e);
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

    final grouped = <int?, List<FloorPlanModel>>{};
    for (final p in _plans) {
      grouped.putIfAbsent(p.buildingId, () => []).add(p);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('Floor Plans',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _buildings.isEmpty ? null : _startNewUpload,
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Upload Floor Plan'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _plans.isEmpty
                  ? const Center(child: Text('No floor plans yet'))
                  : ListView(
                      children: [
                        for (final entry in grouped.entries) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              _buildingName(entry.key),
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              for (final plan in entry.value)
                                _FloorPlanCard(
                                  plan: plan,
                                  onEditNodes: () => context.go(
                                      '/floor-plans/${plan.id}/edit'),
                                  onGeoreference: () => _openGeoreference(plan),
                                  onEdit: () => _openForm(plan),
                                  onDelete: () => _delete(plan),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
        ),
      ],
    );
  }
}

class _FloorPlanCard extends StatelessWidget {
  final FloorPlanModel plan;
  final VoidCallback onEditNodes;
  final VoidCallback onGeoreference;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _FloorPlanCard({
    required this.plan,
    required this.onEditNodes,
    required this.onGeoreference,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              SizedBox(
                height: 140,
                width: double.infinity,
                child: plan.imageUrl != null && plan.imageUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: plan.imageUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => const _PlanFallback(),
                      )
                    : const _PlanFallback(),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (plan.isGeoreferenced
                            ? AppColors.successGreen
                            : AppColors.warningAmber)
                        .withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    plan.isGeoreferenced
                        ? '✓ Georeferenced'
                        : '⚠ Not Georeferenced',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.floorName ?? 'Floor ${plan.floorNumber ?? '?'}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold),
                ),
                Text('Level ${plan.floorNumber ?? '—'}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                if (!plan.isGeoreferenced)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onGeoreference,
                        icon: const Icon(Icons.place_outlined, size: 14),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.warningAmber,
                          side:
                              const BorderSide(color: AppColors.warningAmber),
                        ),
                        label: const Text('Georeference',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onEditNodes,
                        icon: const Icon(Icons.account_tree, size: 14),
                        label: const Text('Edit Nodes',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 16),
                      onPressed: onEdit,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 16, color: AppColors.errorRed),
                      onPressed: onDelete,
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

class _PlanFallback extends StatelessWidget {
  const _PlanFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.backgroundGray,
      child: const Center(
        child: Icon(Icons.map_outlined, size: 36, color: AppColors.textSecondary),
      ),
    );
  }
}

/// Building + floor metadata collected before picking an image for a brand
/// new floor plan upload, ahead of the georeferencing screen.
class _NewFloorMeta {
  final BuildingModel building;
  final int floorNumber;
  final String floorLabel;

  const _NewFloorMeta({
    required this.building,
    required this.floorNumber,
    required this.floorLabel,
  });
}

class _NewFloorPlanDialog extends StatefulWidget {
  final List<BuildingModel> buildings;

  const _NewFloorPlanDialog({required this.buildings});

  @override
  State<_NewFloorPlanDialog> createState() => _NewFloorPlanDialogState();
}

class _NewFloorPlanDialogState extends State<_NewFloorPlanDialog> {
  final _formKey = GlobalKey<FormState>();
  final _floorNumber = TextEditingController(text: '1');
  final _floorName = TextEditingController();
  int? _buildingId;

  @override
  void dispose() {
    _floorNumber.dispose();
    _floorName.dispose();
    super.dispose();
  }

  void _continue() {
    if (!_formKey.currentState!.validate()) return;
    final building = widget.buildings.firstWhere((b) => b.id == _buildingId);
    Navigator.pop(
      context,
      _NewFloorMeta(
        building: building,
        floorNumber: int.parse(_floorNumber.text.trim()),
        floorLabel: _floorName.text.trim().isEmpty
            ? 'Floor ${_floorNumber.text.trim()}'
            : _floorName.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Upload Floor Plan'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                initialValue: widget.buildings.any((b) => b.id == _buildingId)
                    ? _buildingId
                    : null,
                decoration: const InputDecoration(labelText: 'Building'),
                items: [
                  for (final b in widget.buildings)
                    DropdownMenuItem(value: b.id, child: Text(b.name)),
                ],
                onChanged: (v) => setState(() => _buildingId = v),
                validator: (v) => v == null ? 'Select a building' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _floorNumber,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Floor number'),
                validator: (v) =>
                    int.tryParse(v ?? '') == null ? 'Enter a number' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _floorName,
                decoration: const InputDecoration(
                    labelText: 'Floor name (optional)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _continue,
          child: const Text('Choose Image & Continue'),
        ),
      ],
    );
  }
}

class _FloorPlanForm extends StatefulWidget {
  final FloorPlanModel? plan;
  final List<BuildingModel> buildings;
  final FloorPlanRepository repo;

  const _FloorPlanForm({
    required this.plan,
    required this.buildings,
    required this.repo,
  });

  @override
  State<_FloorPlanForm> createState() => _FloorPlanFormState();
}

class _FloorPlanFormState extends State<_FloorPlanForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _floorNumber;
  late final TextEditingController _floorName;
  int? _buildingId;
  PickedImage? _picked;
  String? _imageUrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _floorNumber =
        TextEditingController(text: widget.plan?.floorNumber?.toString() ?? '');
    _floorName = TextEditingController(text: widget.plan?.floorName ?? '');
    _buildingId = widget.plan?.buildingId;
    _imageUrl = widget.plan?.imageUrl;
  }

  @override
  void dispose() {
    _floorNumber.dispose();
    _floorName.dispose();
    super.dispose();
  }

  Future<void> _pickManually() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.first;
    if (file?.bytes == null) return;
    setState(() => _picked = PickedImage(file!.name, file.bytes!));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      var imageUrl = _imageUrl;
      if (_picked != null) {
        imageUrl = await widget.repo.uploadImage(_picked!.fileName, _picked!.bytes);
      }
      final model = FloorPlanModel(
        id: widget.plan?.id,
        buildingId: _buildingId,
        floorNumber: int.tryParse(_floorNumber.text.trim()),
        floorName: _floorName.text.trim().isEmpty ? null : _floorName.text.trim(),
        imageUrl: imageUrl,
      );
      if (widget.plan == null) {
        await widget.repo.create(model);
      } else {
        await widget.repo.update(model);
      }
      if (!mounted) return;
      context.showSuccess('Floor plan saved');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Building',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            initialValue: widget.buildings.any((b) => b.id == _buildingId)
                ? _buildingId
                : null,
            items: [
              for (final b in widget.buildings)
                DropdownMenuItem(value: b.id, child: Text(b.name)),
            ],
            onChanged: (v) => setState(() => _buildingId = v),
            validator: (v) => v == null ? 'Select a building' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _floorNumber,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Floor number'),
            validator: (v) =>
                int.tryParse(v ?? '') == null ? 'Enter a number' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _floorName,
            decoration: const InputDecoration(labelText: 'Floor name'),
          ),
          const SizedBox(height: 14),
          ImageUpload(
            label: 'Floor plan image',
            currentUrl: _imageUrl,
            onPicked: (p) => setState(() => _picked = p),
            onCleared: () => setState(() {
              _picked = null;
              _imageUrl = null;
            }),
          ),
          TextButton.icon(
            onPressed: _pickManually,
            icon: const Icon(Icons.folder_open, size: 16),
            label: const Text('Choose file…'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Save Floor Plan'),
          ),
        ],
      ),
    );
  }
}
