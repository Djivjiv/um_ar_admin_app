import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/building_repository.dart';
import '../../../data/repositories/facility_repository.dart';
import '../../../data/repositories/paged_query.dart';
import '../../../domain/models/access_level.dart';
import '../../../domain/models/building_model.dart';
import '../../../domain/models/facility_model.dart';
import '../../widgets/access_level_fields.dart';
import '../../widgets/active_filter_dropdown.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/data_table_card.dart';
import '../../widgets/form_input.dart';
import '../../widgets/slide_panel.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/tag_input.dart';

const _categories = <String>[
  'Office',
  'Laboratory',
  'Cashier',
  'Lecture Hall',
  'Comfort Room',
  'Chapel',
  'Clinic',
  'Library',
  'Canteen',
  'Sports',
  'Storage',
  'Other',
];

Color _categoryColor(String? category) {
  switch ((category ?? '').toLowerCase()) {
    case 'office':
      return AppColors.infoBlue;
    case 'laboratory':
      return const Color(0xFF7B2FBE); // purple
    case 'cashier':
      return AppColors.accentGold;
    case 'lecture hall':
      return const Color(0xFF00897B); // teal
    case 'comfort room':
      return const Color(0xFFD81B60); // pink
    case 'chapel':
      return AppColors.primaryMaroon;
    case 'clinic':
      return AppColors.errorRed;
    case 'library':
      return const Color(0xFF0D47A1); // dark blue
    case 'canteen':
      return const Color(0xFFEF6C00); // orange
    case 'sports':
      return const Color(0xFF2E7D32); // green
    case 'storage':
      return const Color(0xFF6D4C41); // brown
    default:
      return AppColors.textSecondary; // Other / unknown
  }
}

Widget _categoryPill(String? category) {
  if (category == null || category.isEmpty) {
    return const Text('—', style: TextStyle(color: AppColors.textSecondary));
  }
  final color = _categoryColor(category);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      category,
      style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700, color: color),
    ),
  );
}

class FacilitiesScreen extends StatefulWidget {
  const FacilitiesScreen({super.key});

  @override
  State<FacilitiesScreen> createState() => _FacilitiesScreenState();
}

class _FacilitiesScreenState extends State<FacilitiesScreen> {
  final _repo = FacilityRepository();
  final _buildingRepo = BuildingRepository();
  final _searchCtrl = TextEditingController();

  List<BuildingModel> _buildings = [];
  List<FacilityModel> _facilities = [];
  bool _loading = true;
  Object? _error;

  int? _filterBuildingId;
  String? _filterCategory;

  ActiveFilter _status = ActiveFilter.active;
  String? _filterAccess;
  String _search = '';
  int _page = 0;
  static const _perPage = 10;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Every building, for names; pickers narrow it to the active ones.
      final buildings = await _buildingRepo.getAll(status: ActiveFilter.all);
      final facilities = await _repo.getAll(
        buildingId: _filterBuildingId,
        category: _filterCategory,
        search: _search,
        status: _status,
        accessLevel: _filterAccess,
      );
      if (!mounted) return;
      setState(() {
        _buildings = buildings;
        _facilities = facilities;
        _loading = false;
        _page = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  String _buildingName(int? id) {
    if (id == null) return '—';
    final match = _buildings.where((b) => b.id == id);
    return match.isEmpty ? '#$id' : buildingOptionLabel(match.first);
  }

  Future<void> _openForm([FacilityModel? facility]) async {
    final saved = await SlidePanel.show<bool>(
      context,
      title: facility == null ? 'Add Facility' : 'Edit Facility',
      subtitle: facility?.roomname,
      body: _FacilityForm(
        facility: facility,
        buildings: selectableBuildings(_buildings, facility?.buildingId),
        repo: _repo,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _showDetail(FacilityModel facility) async {
    await SlidePanel.show<void>(
      context,
      title: 'Facility Details',
      body: _FacilityDetailView(
        facility: facility,
        buildingName: _buildingName(facility.buildingId),
      ),
    );
  }

  Future<void> _delete(FacilityModel facility) async {
    final name = facility.roomname ?? 'this facility';
    final ok = await ConfirmDialog.show(
      context,
      itemName: facility.roomname ?? 'facility',
      message: 'Delete $name? This will also delete all facility details, '
          'and floor plan nodes linked to it will be unlinked.',
    );
    if (!ok) return;
    try {
      await _repo.delete(facility.id!);
      if (mounted) context.showSuccess('Facility deleted');
      _load();
    } catch (e) {
      if (mounted) context.showError(e, onRetry: () => _delete(facility));
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _facilities.length;
    final pages = total == 0 ? 1 : ((total - 1) ~/ _perPage) + 1;
    final page = _page < 0 ? 0 : (_page >= pages ? pages - 1 : _page);
    final start = page * _perPage;
    final end = start + _perPage > total ? total : start + _perPage;
    final pageItems = _facilities.sublist(start, end);

    final filterBuildings = selectableBuildings(_buildings, _filterBuildingId);
    final buildingFilterValue =
        filterBuildings.any((b) => b.id == _filterBuildingId)
            ? _filterBuildingId
            : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Facilities',
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 2),
        const Text(
          'Manage campus facilities and their information',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<int?>(
                initialValue: buildingFilterValue,
                isExpanded: true,
                decoration: const InputDecoration(
                    isDense: true, labelText: 'Building'),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('All Buildings')),
                  for (final b in filterBuildings)
                    DropdownMenuItem<int?>(
                      value: b.id,
                      child: Text(buildingOptionLabel(b),
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) {
                  setState(() => _filterBuildingId = v);
                  _load();
                },
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String?>(
                initialValue: _filterCategory,
                isExpanded: true,
                decoration: const InputDecoration(
                    isDense: true, labelText: 'Category'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('All')),
                  for (final c in _categories)
                    DropdownMenuItem<String?>(value: c, child: Text(c)),
                ],
                onChanged: (v) {
                  setState(() => _filterCategory = v);
                  _load();
                },
              ),
            ),
            const SizedBox(width: 12),
            ActiveFilterDropdown(
              value: _status,
              onChanged: (v) {
                setState(() => _status = v);
                _load();
              },
            ),
            const SizedBox(width: 12),
            AccessLevelFilterDropdown(
              value: _filterAccess,
              onChanged: (v) {
                setState(() => _filterAccess = v);
                _load();
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search facilities…',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onChanged: (v) => setState(() => _search = v),
                onSubmitted: (_) => _load(),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryMaroon,
                foregroundColor: AppColors.accentGold,
              ),
              onPressed: _buildings.isEmpty ? null : () => _openForm(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Facility'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _error != null
              ? _ErrorView(error: _error!, onRetry: _load)
              : DataTableCard(
                  title: '$total ${total == 1 ? 'Facility' : 'Facilities'}',
                  isLoading: _loading,
                  minWidth: 1080,
                  emptyMessage: 'No facilities found',
                  columns: const [
                    DataColumn2(
                        label: Text('Facility Name'), size: ColumnSize.L),
                    DataColumn2(label: Text('Building'), size: ColumnSize.M),
                    DataColumn2(label: Text('Floor'), size: ColumnSize.S),
                    DataColumn2(label: Text('Category'), size: ColumnSize.M),
                    DataColumn2(
                        label: Text('Room Number'), size: ColumnSize.M),
                    DataColumn2(label: Text('Access'), size: ColumnSize.M),
                    DataColumn2(label: Text('Status'), size: ColumnSize.S),
                    DataColumn2(label: Text('Actions'), size: ColumnSize.S),
                  ],
                  rows: [
                    for (final f in pageItems)
                      DataRow2(
                        onTap: () => _showDetail(f),
                        cells: [
                          DataCell(Text(
                            f.roomname ?? '—',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary),
                          )),
                          DataCell(Text(
                            _buildingName(f.buildingId),
                            style: const TextStyle(
                                color: AppColors.textSecondary),
                          )),
                          DataCell(Text(
                            f.floor?.toString() ?? '—',
                            style: const TextStyle(
                                color: AppColors.textSecondary),
                          )),
                          DataCell(_categoryPill(f.facilityCategories)),
                          DataCell(Text(
                            f.roomNumber ?? '—',
                            style: const TextStyle(
                                color: AppColors.textSecondary),
                          )),
                          DataCell(Text(
                            accessLevelLabel(f.accessLevel),
                            style: const TextStyle(
                                color: AppColors.textSecondary),
                          )),
                          DataCell(StatusBadge.fromBool(f.isActive)),
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edit',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: () => _openForm(f),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: AppColors.errorRed),
                                onPressed: () => _delete(f),
                              ),
                            ],
                          )),
                        ],
                      ),
                  ],
                ),
        ),
        if (!_loading && _error == null && total > _perPage) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'Page ${page + 1} of $pages',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed:
                    page > 0 ? () => setState(() => _page = page - 1) : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: page < pages - 1
                    ? () => setState(() => _page = page + 1)
                    : null,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 40, color: AppColors.textSecondary),
          const SizedBox(height: 10),
          Text(error.toString(), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add / edit form (slide panel body)
// ---------------------------------------------------------------------------

class _FacilityForm extends StatefulWidget {
  final FacilityModel? facility;
  final List<BuildingModel> buildings;
  final FacilityRepository repo;

  const _FacilityForm({
    this.facility,
    required this.buildings,
    required this.repo,
  });

  @override
  State<_FacilityForm> createState() => _FacilityFormState();
}

class _FacilityFormState extends State<_FacilityForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _roomNumber;
  late final TextEditingController _floor;
  late final TextEditingController _location;
  late final TextEditingController _officeHours;
  late final TextEditingController _contact;

  int? _buildingId;
  String? _category;
  late String _accessLevel;
  late List<String> _description;
  late List<String> _services;
  late List<String> _payment;
  late List<String> _instructions;
  late bool _isActive;
  bool _saving = false;

  bool get _isEdit => widget.facility != null;

  @override
  void initState() {
    super.initState();
    final f = widget.facility;
    _name = TextEditingController(text: f?.roomname ?? '');
    _roomNumber = TextEditingController(text: f?.roomNumber ?? '');
    _floor = TextEditingController(text: f?.floor?.toString() ?? '');
    _location = TextEditingController(text: f?.location ?? '');
    _officeHours = TextEditingController(text: f?.officeHours ?? '');
    _contact = TextEditingController(text: f?.contactNumber ?? '');
    _buildingId = f?.buildingId;
    _category = _categories.contains(f?.facilityCategories)
        ? f?.facilityCategories
        : null;
    _description = List.of(f?.description ?? const []);
    _services = List.of(f?.services ?? const []);
    _payment = List.of(f?.paymentMethod ?? const []);
    _instructions = List.of(f?.instructions ?? const []);
    _isActive = f?.isActive ?? true;
    _accessLevel = selectedAccessLevel(f?.accessLevel);
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _roomNumber,
      _floor,
      _location,
      _officeHours,
      _contact,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_buildingId == null) {
      context.showError('Select a building');
      return;
    }
    setState(() => _saving = true);
    try {
      final existing = widget.facility;
      if (existing != null && existing.isActive && !_isActive) {
        final linked = await widget.repo.linkedNodeCount(existing.id!);
        if (!mounted) return;
        final ok = await ConfirmDialog.showDeactivate(
          context,
          itemName: _name.text.trim(),
          linkedNodes: linked,
        );
        if (!ok) return;
      }
      String? nn(String s) => s.trim().isEmpty ? null : s.trim();
      final model = FacilityModel(
        id: widget.facility?.id,
        roomname: _name.text.trim(),
        roomNumber: nn(_roomNumber.text),
        buildingId: _buildingId,
        floor: int.tryParse(_floor.text.trim()),
        location: nn(_location.text),
        facilityCategories: _category,
        accessLevel:
            accessLevelToSave(_accessLevel, widget.facility?.accessLevel),
        description: _description,
        isActive: _isActive,
        officeHours: nn(_officeHours.text),
        contactNumber: nn(_contact.text),
        services: _services,
        paymentMethod: _payment,
        instructions: _instructions,
      );
      if (_isEdit) {
        await widget.repo.update(widget.facility!.id!, model);
      } else {
        await widget.repo.create(model);
      }
      if (!mounted) return;
      context.showSuccess(_isEdit ? 'Facility updated' : 'Facility created');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) context.showError(e, onRetry: _save);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final buildings = [...widget.buildings]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel('Basic Information'),
          FormInput(
            label: 'Facility Name',
            controller: _name,
            required: true,
            hint: 'e.g. Computer Laboratory 1',
          ),
          const SizedBox(height: 14),
          FormInput(
            label: 'Room Number',
            controller: _roomNumber,
            hint: 'e.g. BE-101, CR-GF-1',
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Building', required: true),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            initialValue:
                buildings.any((b) => b.id == _buildingId) ? _buildingId : null,
            isExpanded: true,
            items: [
              for (final b in buildings)
                DropdownMenuItem(
                  value: b.id,
                  child: Text(buildingOptionLabel(b),
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _buildingId = v),
            validator: (v) => v == null ? 'Select a building' : null,
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FormInput(
                  label: 'Floor',
                  controller: _floor,
                  keyboardType: TextInputType.number,
                  hint: 'e.g. 1',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FieldLabel('Facility Category'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      isExpanded: true,
                      hint: const Text('Select'),
                      items: [
                        for (final c in _categories)
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) => setState(() => _category = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AccessLevelField(
            value: _accessLevel,
            stored: widget.facility?.accessLevel,
            onChanged: (v) => setState(() => _accessLevel = v),
          ),
          const SizedBox(height: 14),
          FormInput(
            label: 'Location',
            controller: _location,
            hint: 'e.g. Ground Floor, Left Wing',
          ),
          const SizedBox(height: 14),
          TagInput(
            label: 'Description',
            initialTags: _description,
            hint: 'Add a description line and press Enter',
            onChanged: (v) => _description = v,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active'),
            value: _isActive,
            onChanged: (v) => setState(() => _isActive = v),
          ),
          const SizedBox(height: 20),
          _sectionLabel('Facility Details'),
          FormInput(
            label: 'Office Hours',
            controller: _officeHours,
            hint: 'e.g. Mon-Fri 8:00 AM - 5:00 PM',
          ),
          const SizedBox(height: 14),
          FormInput(
            label: 'Contact Number',
            controller: _contact,
            hint: 'e.g. (082) XXX-XXXX local XXX',
          ),
          const SizedBox(height: 14),
          TagInput(
            label: 'Services',
            initialTags: _services,
            hint: 'Type service and press Enter',
            onChanged: (v) => _services = v,
          ),
          const SizedBox(height: 14),
          TagInput(
            label: 'Payment Methods',
            initialTags: _payment,
            hint: 'e.g. Cash, GCash, Maya',
            onChanged: (v) => _payment = v,
          ),
          const SizedBox(height: 14),
          TagInput(
            label: 'Instructions',
            initialTags: _instructions,
            hint: 'Type instruction and press Enter',
            onChanged: (v) => _instructions = v,
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryMaroon,
                    foregroundColor: AppColors.accentGold,
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.accentGold),
                        )
                      : Text(_isEdit ? 'Save Changes' : 'Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          text,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
      );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final bool required;
  const _FieldLabel(this.text, {this.required = false});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        children: [
          if (required)
            const TextSpan(
                text: ' *', style: TextStyle(color: AppColors.errorRed)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Read-only detail view (slide panel body)
// ---------------------------------------------------------------------------

class _FacilityDetailView extends StatelessWidget {
  final FacilityModel facility;
  final String buildingName;

  const _FacilityDetailView({
    required this.facility,
    required this.buildingName,
  });

  @override
  Widget build(BuildContext context) {
    final f = facility;
    final subtitleParts = <String>[
      buildingName,
      if (f.floor != null) 'Floor ${f.floor}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          f.roomname ?? 'Facility',
          style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if ((f.roomNumber ?? '').isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentGold.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  f.roomNumber!,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accentGold),
                ),
              ),
            if ((f.facilityCategories ?? '').isNotEmpty)
              _categoryPill(f.facilityCategories),
            StatusBadge.fromBool(f.isActive),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          subtitleParts.join('  ·  '),
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        if ((f.location ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            f.location!,
            style:
                const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
        if (f.description.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final d in f.description)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('•  $d', style: const TextStyle(fontSize: 13)),
            ),
        ],
        const SizedBox(height: 4),
        Text(
          'Access: ${accessLevelLabel(f.accessLevel)}',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const Divider(height: 26),
        if ((f.officeHours ?? '').isNotEmpty)
          _IconLine(icon: Icons.schedule, text: f.officeHours!),
        if ((f.contactNumber ?? '').isNotEmpty)
          _IconLine(icon: Icons.phone, text: f.contactNumber!),
        if (f.services.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('Services',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          for (final s in f.services)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ',
                      style: TextStyle(
                          color: AppColors.primaryMaroon,
                          fontWeight: FontWeight.bold)),
                  Expanded(
                      child: Text(s, style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
        ],
        if (f.paymentMethod.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('Payment Methods',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in f.paymentMethod)
                Chip(
                  label: Text(p, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        ],
        if (f.instructions.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('Instructions',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          for (var i = 0; i < f.instructions.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('${i + 1}.  ${f.instructions[i]}',
                  style: const TextStyle(fontSize: 13)),
            ),
        ],
      ],
    );
  }
}

class _IconLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _IconLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
