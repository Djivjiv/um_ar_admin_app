import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/no_rooms_buildings.dart';
import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/building_repository.dart';
import '../../../data/repositories/floor_plan_repository.dart';
import '../../../data/repositories/paged_query.dart';
import '../../../domain/models/building_model.dart';
import '../../../domain/models/floor_plan_model.dart';
import '../../widgets/active_filter_dropdown.dart';
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
  Map<int, FloorGraphStats> _stats = {};

  /// Null when counts loaded fine; otherwise why they couldn't be loaded.
  String? _statsError;

  /// Which buildings' floor plans are listed.
  ActiveFilter _buildingStatus = ActiveFilter.active;
  bool _loading = true;
  bool _uploading = false;
  Object? _error;

  /// The node editor is a child route (`/floor-plans/:id/edit`), so this
  /// screen stays mounted underneath it and `initState` never runs again.
  /// Listening to the router lets us reload whenever the list becomes the
  /// visible page — via the back arrow, a pop, or the sidebar.
  GoRouterDelegate? _routerDelegate;
  bool _wasVisible = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final delegate = GoRouter.of(context).routerDelegate;
    if (!identical(delegate, _routerDelegate)) {
      _routerDelegate?.removeListener(_onRouteChanged);
      _routerDelegate = delegate..addListener(_onRouteChanged);
    }
  }

  @override
  void dispose() {
    _routerDelegate?.removeListener(_onRouteChanged);
    super.dispose();
  }

  void _onRouteChanged() {
    final path = _routerDelegate?.currentConfiguration.uri.path;
    final visible = path == '/floor-plans';
    if (visible && !_wasVisible) {
      // The router notifies mid-navigation; reload after this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(silent: true);
      });
    }
    _wasVisible = visible;
  }

  /// [silent] keeps the current cards on screen while reloading (used when
  /// returning from the editor and for pull-to-refresh) instead of swapping
  /// the list for a spinner.
  Future<void> _load({bool silent = false}) async {
    if (!silent || _error != null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _repo.getAll(),
        // Every building, for names; pickers narrow it to the active ones.
        _buildingRepo.getAll(status: ActiveFilter.all),
      ]);
      // Counts are extra info — a failure here must not hide the floor plans.
      Map<int, FloorGraphStats> stats = {};
      String? statsError;
      try {
        stats = await _repo.getGraphStats();
      } catch (e) {
        statsError = e.toString();
      }
      if (!mounted) return;
      setState(() {
        _plans = results[0] as List<FloorPlanModel>;
        _buildings = results[1] as List<BuildingModel>;
        _stats = stats;
        _statsError = statsError;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // A failed background refresh keeps the cards already shown.
      if (silent && !_loading) {
        context.showError(e, onRetry: () => _load(silent: true));
        return;
      }
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  String _buildingName(int? id) {
    final m = _buildings.where((b) => b.id == id);
    return m.isEmpty ? '#$id' : buildingOptionLabel(m.first);
  }

  /// Floor plans of buildings matching the Buildings filter. A plan whose
  /// building can't be found still shows, so it can be fixed or deleted.
  List<FloorPlanModel> get _visiblePlans {
    if (_buildingStatus == ActiveFilter.all) return _plans;
    final inactive = {
      for (final b in _buildings)
        if (!b.isActive) b.id,
    };
    return _plans
        .where((p) =>
            inactive.contains(p.buildingId) ==
            (_buildingStatus == ActiveFilter.inactive))
        .toList();
  }

  /// Buildings a floor plan can be attached to.
  List<BuildingModel> _pickableBuildings([int? keepId]) =>
      selectableBuildings(_buildings, keepId)
          .where((b) => buildingHasRooms(b.name))
          .toList();

  Future<void> _openForm([FloorPlanModel? plan]) async {
    final result = await SlidePanel.show<bool>(
      context,
      title: plan == null ? 'Upload Floor Plan' : 'Edit Floor Plan',
      body: _FloorPlanForm(
        plan: plan,
        buildings: _pickableBuildings(plan?.buildingId),
        repo: _repo,
      ),
    );
    if (result == true) _load();
  }

  /// New-upload flow: collect building/floor/scale, pick an image, upload it,
  /// create the floor plan, and open the node editor straight away.
  /// Georeferencing is not part of this flow (it stays optional per card).
  Future<void> _startNewUpload() async {
    final meta = await showDialog<_NewFloorMeta>(
      context: context,
      builder: (_) => _NewFloorPlanDialog(
        buildings: _pickableBuildings(),
      ),
    );
    if (meta == null || !mounted) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null) return; // cancelled
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) context.showError('Could not read the selected image file.');
      return;
    }

    setState(() => _uploading = true);
    try {
      final dot = file.name.lastIndexOf('.');
      final ext = dot == -1 ? '.png' : file.name.substring(dot).toLowerCase();
      final storagePath =
          '${meta.building.id}/floor_${meta.floorNumber}_'
          '${DateTime.now().millisecondsSinceEpoch}$ext';
      final imageUrl = await _repo.uploadImageAtPath(storagePath, bytes);
      var created = await _repo.create(
        FloorPlanModel(
          buildingId: meta.building.id,
          floorNumber: meta.floorNumber,
          floorName: meta.floorLabel,
          imageUrl: imageUrl,
          metersPerPixel: meta.metersPerPixel,
        ),
      );
      final scale = meta.metersPerPixel;
      if (scale != null) created = await _repo.saveScale(created.id!, scale);
      if (!mounted) return;
      context.showSuccess('Floor plan uploaded (scale: ${created.scaleLabel}) '
          '— tap the image to add nodes');
      context.go('/floor-plans/${created.id}/edit');
    } catch (e) {
      if (mounted) context.showError(e, onRetry: _startNewUpload);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _openGeoreference(FloorPlanModel plan) {
    final match = _buildings.where((b) => b.id == plan.buildingId);
    final building = match.isEmpty
        ? BuildingModel(
            id: plan.buildingId,
            name: _buildingName(plan.buildingId),
          )
        : match.first;
    context.go(
      '/floor-plans/georeference',
      extra: {
        'building': building,
        'floorNumber': plan.floorNumber ?? 1,
        'floorLabel': plan.floorName ?? 'Floor ${plan.floorNumber ?? 1}',
        'existingFloorPlan': plan,
      },
    );
  }

  Future<void> _delete(FloorPlanModel plan) async {
    final ok = await ConfirmDialog.show(
      context,
      itemName: plan.floorName ?? 'Floor ${plan.floorNumber}',
      message: 'Outdoor entrances linked to its nodes will lose their link '
          'and show as missing an indoor node. This action cannot be undone.',
    );
    if (!ok) return;
    try {
      await _repo.delete(plan.id!);
      if (mounted) context.showSuccess('Floor plan deleted');
      _load();
    } catch (e) {
      if (mounted) context.showError(e, onRetry: () => _delete(plan));
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

    final visiblePlans = _visiblePlans;
    final grouped = <int?, List<FloorPlanModel>>{};
    for (final p in visiblePlans) {
      grouped.putIfAbsent(p.buildingId, () => []).add(p);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'Floor Plans',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 16),
            ActiveFilterDropdown(
              label: 'Buildings',
              value: _buildingStatus,
              onChanged: (v) => setState(() => _buildingStatus = v),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh counts',
              onPressed: _loading ? null : () => _load(silent: true),
              icon: const Icon(Icons.refresh),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _buildings.isEmpty || _uploading
                  ? null
                  : _startNewUpload,
              icon: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.upload_file, size: 18),
              label: Text(_uploading ? 'Uploading…' : 'Upload Floor Plan'),
            ),
          ],
        ),
        if (_statsError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Node/edge counts unavailable: $_statsError',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.warningAmber,
              ),
            ),
          ),
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () => _load(silent: true),
                  // Desktop: let a mouse drag trigger pull-to-refresh too.
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                      },
                    ),
                    child: visiblePlans.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 120),
                              Center(
                                child: Text(_plans.isEmpty
                                    ? 'No floor plans yet'
                                    : 'No floor plans match the Buildings '
                                        'filter'),
                              ),
                            ],
                          )
                        : ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              for (final entry in grouped.entries) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    _buildingName(entry.key),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Wrap(
                                  spacing: 16,
                                  runSpacing: 16,
                                  children: [
                                    for (final plan in entry.value)
                                      _FloorPlanCard(
                                        plan: plan,
                                        stats: _statsError != null
                                            ? null
                                            : _stats[plan.id] ??
                                                  const FloorGraphStats(),
                                        onEditNodes: () => context.go(
                                          '/floor-plans/${plan.id}/edit',
                                        ),
                                        onGeoreference: () =>
                                            _openGeoreference(plan),
                                        onEdit: () => _openForm(plan),
                                        onDelete: () => _delete(plan),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _FloorPlanCard extends StatelessWidget {
  final FloorPlanModel plan;

  /// Null when counts couldn't be loaded.
  final FloorGraphStats? stats;
  final VoidCallback onEditNodes;
  final VoidCallback onGeoreference;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _FloorPlanCard({
    required this.plan,
    required this.stats,
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
              if (stats != null)
                Positioned(
                  top: 8,
                  left: 8,
                  child: _RoutingBadge(stats: stats!),
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
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Level ${plan.floorNumber ?? '—'}  ·  '
                  'Scale: ${plan.scaleLabel}',
                  style: TextStyle(
                    fontSize: 11,
                    color: plan.isScaleCalibrated
                        ? AppColors.textSecondary
                        : AppColors.errorRed,
                  ),
                ),
                const SizedBox(height: 6),
                if (stats != null)
                  Text(
                    '${stats!.nodeCount} nodes  ·  ${stats!.edgeCount} edges',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (stats != null &&
                    stats!.crossBuildingLinks + stats!.crossBuildingPending >
                        0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.swap_horiz,
                            size: 14, color: AppColors.crossBuildingOrange),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            [
                              if (stats!.crossBuildingLinks > 0)
                                '${stats!.crossBuildingLinks} cross-building '
                                    'link${stats!.crossBuildingLinks == 1 ? '' : 's'}',
                              if (stats!.crossBuildingPending > 0)
                                '${stats!.crossBuildingPending} pending',
                            ].join('  ·  '),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.crossBuildingOrange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onEditNodes,
                        icon: const Icon(Icons.account_tree, size: 14),
                        label: const Text(
                          'Edit Nodes',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit details & scale',
                      icon: const Icon(Icons.edit, size: 16),
                      onPressed: onEdit,
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: AppColors.errorRed,
                      ),
                      onPressed: onDelete,
                    ),
                    PopupMenuButton<void>(
                      tooltip: 'More',
                      icon: const Icon(Icons.more_vert, size: 16),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          onTap: onGeoreference,
                          child: Text(
                            plan.isGeoreferenced
                                ? 'Georeference (optional) ✓'
                                : 'Georeference (optional)',
                          ),
                        ),
                      ],
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

class _RoutingBadge extends StatelessWidget {
  final FloorGraphStats stats;

  const _RoutingBadge({required this.stats});

  @override
  Widget build(BuildContext context) {
    final (String text, Color color, String tip) = switch (stats.status) {
      RoutingStatus.ready => (
        '✓ Routing works',
        AppColors.successGreen,
        'All ${stats.navigableCount} navigation nodes are connected.',
      ),
      RoutingStatus.partial => (
        '⚠ ${stats.disconnectedCount} unconnected',
        AppColors.warningAmber,
        '${stats.disconnectedCount} of ${stats.navigableCount} navigation '
            'nodes cannot be reached. Add edges to connect them.',
      ),
      RoutingStatus.notRoutable => (
        '✕ No routing',
        AppColors.errorRed,
        'Needs at least 2 navigation nodes joined by an edge.',
      ),
      RoutingStatus.empty => (
        'No nodes yet',
        AppColors.textSecondary,
        'Open Edit Nodes and tap the image to place nodes.',
      ),
    };
    return Tooltip(
      message: tip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
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
        child: Icon(
          Icons.map_outlined,
          size: 36,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Building + floor metadata collected before picking an image for a brand
/// new floor plan upload.
class _NewFloorMeta {
  final BuildingModel building;
  final int floorNumber;
  final String floorLabel;

  /// Null = not calibrated yet.
  final double? metersPerPixel;

  const _NewFloorMeta({
    required this.building,
    required this.floorNumber,
    required this.floorLabel,
    this.metersPerPixel,
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
  final _metersPerPixel = TextEditingController();
  int? _buildingId;

  @override
  void dispose() {
    _floorNumber.dispose();
    _floorName.dispose();
    _metersPerPixel.dispose();
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
        metersPerPixel: parseOptionalMetersPerPixel(_metersPerPixel.text),
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
                    DropdownMenuItem(
                        value: b.id, child: Text(buildingOptionLabel(b))),
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
                  labelText: 'Floor name (optional)',
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _metersPerPixel,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Meters per pixel (optional)',
                  helperText: 'Leave empty until measured — the floor shows '
                      '"not calibrated"',
                ),
                validator: validateOptionalMetersPerPixel,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _continue,
          child: const Text('Choose Image & Upload'),
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
  late final TextEditingController _metersPerPixel;
  int? _buildingId;
  PickedImage? _picked;
  String? _imageUrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _floorNumber = TextEditingController(
      text: widget.plan?.floorNumber?.toString() ?? '',
    );
    _floorName = TextEditingController(text: widget.plan?.floorName ?? '');
    _metersPerPixel = TextEditingController(
      text: widget.plan?.metersPerPixel?.toString() ?? '',
    );
    _buildingId = widget.plan?.buildingId;
    _imageUrl = widget.plan?.imageUrl;
  }

  @override
  void dispose() {
    _floorNumber.dispose();
    _floorName.dispose();
    _metersPerPixel.dispose();
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
        imageUrl = await widget.repo.uploadImage(
          _picked!.fileName,
          _picked!.bytes,
        );
      }
      // Start from the existing row so editing details never wipes other
      // columns (georeferencing corners, is_active, …).
      final floorName = _floorName.text.trim().isEmpty
          ? null
          : _floorName.text.trim();
      final base = widget.plan ?? const FloorPlanModel();
      // An empty scale field leaves the stored scale as it is.
      final scale = parseOptionalMetersPerPixel(_metersPerPixel.text);
      final model = FloorPlanModel.fromJson({
        ...base.toJson(),
        'building_id': _buildingId,
        'floor_number': int.tryParse(_floorNumber.text.trim()),
        'floor_name': floorName,
        'image_url': imageUrl,
        'meters_per_pixel': ?scale,
      });
      var saved = widget.plan == null
          ? await widget.repo.create(model)
          : await widget.repo.update(model);
      if (scale != null) saved = await widget.repo.saveScale(saved.id!, scale);
      if (!mounted) return;
      context.showSuccess('Floor plan saved (scale: ${saved.scaleLabel})');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) context.showError(e, onRetry: _save);
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
          const Text(
            'Building',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            initialValue: widget.buildings.any((b) => b.id == _buildingId)
                ? _buildingId
                : null,
            items: [
              for (final b in widget.buildings)
                DropdownMenuItem(
                    value: b.id, child: Text(buildingOptionLabel(b))),
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
          TextFormField(
            controller: _metersPerPixel,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Meters per pixel (optional)',
              helperText: 'Turns pixel distances into meters. Empty = not '
                  'calibrated',
            ),
            validator: validateOptionalMetersPerPixel,
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
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save Floor Plan'),
          ),
        ],
      ),
    );
  }
}
