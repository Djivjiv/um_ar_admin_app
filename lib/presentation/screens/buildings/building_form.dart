import 'package:flutter/material.dart';

import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/building_repository.dart';
import '../../../domain/models/building_model.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_input.dart';
import '../../widgets/image_upload.dart';
import '../../widgets/tag_input.dart';

/// Form body for creating or editing a [BuildingModel]. Pops `true` on success.
class BuildingForm extends StatefulWidget {
  final BuildingModel? building;

  const BuildingForm({super.key, this.building});

  @override
  State<BuildingForm> createState() => _BuildingFormState();
}

class _BuildingFormState extends State<BuildingForm> {
  final _repo = BuildingRepository();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _shortName;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  late final TextEditingController _floorCount;
  late final TextEditingController _openingHours;
  late final TextEditingController _contact;

  late List<String> _description;
  late List<String> _departments;
  late List<String> _facilities;
  late bool _isAccessible;
  late bool _isActive;
  PickedImage? _pickedImage;
  String? _imageUrl;
  bool _saving = false;

  bool get _isEdit => widget.building != null;

  @override
  void initState() {
    super.initState();
    final b = widget.building;
    _name = TextEditingController(text: b?.name ?? '');
    _shortName = TextEditingController(text: b?.shortName ?? '');
    _lat = TextEditingController(text: b?.lat?.toString() ?? '');
    _lng = TextEditingController(text: b?.lng?.toString() ?? '');
    _floorCount = TextEditingController(text: b?.floorCount?.toString() ?? '');
    _openingHours = TextEditingController(text: b?.openingHours ?? '');
    _contact = TextEditingController(text: b?.contact ?? '');
    _description = List.of(b?.description ?? const []);
    _departments = List.of(b?.departments ?? const []);
    _facilities = List.of(b?.facilitiesList ?? const []);
    _isAccessible = b?.isAccessible ?? false;
    _isActive = b?.isActive ?? true;
    _imageUrl = b?.imageUrl;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _shortName,
      _lat,
      _lng,
      _floorCount,
      _openingHours,
      _contact,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final existing = widget.building;
      if (existing != null && existing.isActive && !_isActive) {
        final linked = await _repo.linkedNodeCount(existing.id!);
        if (!mounted) return;
        final ok = await ConfirmDialog.showDeactivate(
          context,
          itemName: _name.text.trim(),
          linkedNodes: linked,
        );
        if (!ok) return;
      }
      var imageUrl = _imageUrl;
      if (_pickedImage != null) {
        imageUrl =
            await _repo.uploadImage(_pickedImage!.fileName, _pickedImage!.bytes);
      }
      final model = BuildingModel(
        id: widget.building?.id,
        name: _name.text.trim(),
        shortName: _shortName.text.trim().isEmpty ? null : _shortName.text.trim(),
        lat: double.tryParse(_lat.text.trim()),
        lng: double.tryParse(_lng.text.trim()),
        floorCount: int.tryParse(_floorCount.text.trim()),
        openingHours:
            _openingHours.text.trim().isEmpty ? null : _openingHours.text.trim(),
        contact: _contact.text.trim().isEmpty ? null : _contact.text.trim(),
        description: _description,
        departments: _departments,
        facilitiesList: _facilities,
        isAccessible: _isAccessible,
        isActive: _isActive,
        imageUrl: imageUrl,
        // Edited on the Campus Map, not here. toJson writes them, so leaving
        // them out would clear them on every save.
        labelLat: existing?.labelLat,
        labelLng: existing?.labelLng,
        displayName: existing?.displayName,
      );
      if (_isEdit) {
        await _repo.update(model);
      } else {
        await _repo.create(model);
      }
      if (!mounted) return;
      context.showSuccess(_isEdit ? 'Building updated' : 'Building created');
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
          ImageUpload(
            label: 'Building Photo',
            currentUrl: _imageUrl,
            onPicked: (p) => setState(() => _pickedImage = p),
            onCleared: () => setState(() {
              _pickedImage = null;
              _imageUrl = null;
            }),
          ),
          const SizedBox(height: 14),
          FormInput(label: 'Name', controller: _name, required: true),
          const SizedBox(height: 14),
          FormInput(label: 'Short Name', controller: _shortName),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FormInput(
                  label: 'Latitude',
                  controller: _lat,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FormInput(
                  label: 'Longitude',
                  controller: _lng,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FormInput(
            label: 'Floor Count',
            controller: _floorCount,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 14),
          FormInput(label: 'Opening Hours', controller: _openingHours),
          const SizedBox(height: 14),
          FormInput(label: 'Contact', controller: _contact),
          const SizedBox(height: 14),
          TagInput(
            label: 'Description',
            initialTags: _description,
            onChanged: (v) => _description = v,
          ),
          const SizedBox(height: 14),
          TagInput(
            label: 'Departments',
            initialTags: _departments,
            onChanged: (v) => _departments = v,
          ),
          const SizedBox(height: 14),
          TagInput(
            label: 'Facilities',
            initialTags: _facilities,
            onChanged: (v) => _facilities = v,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Wheelchair accessible'),
            value: _isAccessible,
            onChanged: (v) => setState(() => _isAccessible = v),
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
                      : Text(_isEdit ? 'Save Changes' : 'Create Building'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
