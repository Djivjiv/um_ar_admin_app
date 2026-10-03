import 'package:flutter/material.dart';

import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/room_repository.dart';
import '../../../domain/models/building_model.dart';
import '../../../domain/models/room_model.dart';
import '../../widgets/form_input.dart';
import '../../widgets/tag_input.dart';

const _paymentOptions = ['Cash', 'GCash', 'Maya', 'Card', 'Bank Transfer'];

class RoomForm extends StatefulWidget {
  final RoomModel? room;
  final List<BuildingModel> buildings;
  final int? defaultBuildingId;

  const RoomForm({
    super.key,
    this.room,
    required this.buildings,
    this.defaultBuildingId,
  });

  @override
  State<RoomForm> createState() => _RoomFormState();
}

class _RoomFormState extends State<RoomForm> {
  final _repo = RoomRepository();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _roomname;
  late final TextEditingController _shortName;
  late final TextEditingController _floor;
  late final TextEditingController _type;
  late final TextEditingController _accessLevel;
  late final TextEditingController _openingHours;
  late final TextEditingController _contact;
  late final TextEditingController _description;

  int? _buildingId;
  late List<String> _services;
  late Set<String> _paymentMethods;
  late bool _isActive;
  bool _saving = false;

  bool get _isEdit => widget.room != null;

  @override
  void initState() {
    super.initState();
    final r = widget.room;
    _roomname = TextEditingController(text: r?.roomname ?? '');
    _shortName = TextEditingController(text: r?.shortName ?? '');
    _floor = TextEditingController(text: r?.floor ?? '');
    _type = TextEditingController(text: r?.type ?? '');
    _accessLevel = TextEditingController(text: r?.accessLevel ?? '');
    _openingHours = TextEditingController(text: r?.openingHours ?? '');
    _contact = TextEditingController(text: r?.contact ?? '');
    _description = TextEditingController(text: r?.description ?? '');
    _buildingId = r?.buildingId ?? widget.defaultBuildingId;
    _services = List.of(r?.services ?? const []);
    _paymentMethods = {...(r?.paymentMethods ?? const [])};
    _isActive = r?.isActive ?? true;
  }

  @override
  void dispose() {
    for (final c in [
      _roomname,
      _shortName,
      _floor,
      _type,
      _accessLevel,
      _openingHours,
      _contact,
      _description,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final model = RoomModel(
        id: widget.room?.id,
        buildingId: _buildingId,
        roomname: _roomname.text.trim(),
        shortName: _shortName.text.trim().isEmpty ? null : _shortName.text.trim(),
        floor: _floor.text.trim().isEmpty ? null : _floor.text.trim(),
        type: _type.text.trim().isEmpty ? null : _type.text.trim(),
        accessLevel:
            _accessLevel.text.trim().isEmpty ? null : _accessLevel.text.trim(),
        openingHours:
            _openingHours.text.trim().isEmpty ? null : _openingHours.text.trim(),
        contact: _contact.text.trim().isEmpty ? null : _contact.text.trim(),
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        services: _services,
        paymentMethods: _paymentMethods.toList(),
        imageUrl: widget.room?.imageUrl ?? const [],
        isActive: _isActive,
      );
      if (_isEdit) {
        await _repo.update(model);
      } else {
        await _repo.create(model);
      }
      if (!mounted) return;
      context.showSuccess(_isEdit ? 'Room updated' : 'Room created');
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
          FormInput(label: 'Room Name', controller: _roomname, required: true),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                  child: FormInput(label: 'Short Name', controller: _shortName)),
              const SizedBox(width: 12),
              Expanded(child: FormInput(label: 'Floor', controller: _floor)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: FormInput(label: 'Type', controller: _type)),
              const SizedBox(width: 12),
              Expanded(
                  child: FormInput(
                      label: 'Access Level', controller: _accessLevel)),
            ],
          ),
          const SizedBox(height: 14),
          FormInput(label: 'Opening Hours', controller: _openingHours),
          const SizedBox(height: 14),
          FormInput(label: 'Contact', controller: _contact),
          const SizedBox(height: 14),
          FormInput(
              label: 'Description', controller: _description, maxLines: 3),
          const SizedBox(height: 14),
          TagInput(
            label: 'Services',
            initialTags: _services,
            onChanged: (v) => _services = v,
          ),
          const SizedBox(height: 14),
          const Text('Payment Methods',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          for (final option in _paymentOptions)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(option),
              value: _paymentMethods.contains(option),
              onChanged: (checked) => setState(() {
                if (checked == true) {
                  _paymentMethods.add(option);
                } else {
                  _paymentMethods.remove(option);
                }
              }),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active'),
            value: _isActive,
            onChanged: (v) => setState(() => _isActive = v),
          ),
          const SizedBox(height: 16),
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
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_isEdit ? 'Save Changes' : 'Create Room'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
