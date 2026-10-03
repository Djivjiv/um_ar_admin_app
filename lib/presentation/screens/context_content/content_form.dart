import 'package:flutter/material.dart';

import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/content_repository.dart';
import '../../../domain/models/building_model.dart';
import '../../../domain/models/facility_content_model.dart';
import '../../widgets/form_input.dart';

const kContentTypes = ['info', 'tip', 'warning', 'procedure', 'faq'];

class ContentForm extends StatefulWidget {
  final FacilityContentModel? content;
  final List<BuildingModel> buildings;

  const ContentForm({super.key, this.content, required this.buildings});

  @override
  State<ContentForm> createState() => _ContentFormState();
}

class _ContentFormState extends State<ContentForm> {
  final _repo = ContentRepository();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _title;
  late final TextEditingController _content;
  late final TextEditingController _icon;
  late final TextEditingController _roomId;
  int? _buildingId;
  late String _type;
  late bool _isActive;
  bool _saving = false;

  bool get _isEdit => widget.content != null;

  @override
  void initState() {
    super.initState();
    final c = widget.content;
    _title = TextEditingController(text: c?.title ?? '');
    _content = TextEditingController(text: c?.content ?? '');
    _icon = TextEditingController(text: c?.icon ?? '');
    _roomId = TextEditingController(text: c?.roomId?.toString() ?? '');
    _buildingId = c?.buildingId;
    _type = kContentTypes.contains(c?.type) ? c!.type! : kContentTypes.first;
    _isActive = c?.isActive ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _icon.dispose();
    _roomId.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final model = FacilityContentModel(
        id: widget.content?.id,
        buildingId: _buildingId,
        roomId: int.tryParse(_roomId.text.trim()),
        title: _title.text.trim(),
        content: _content.text.trim().isEmpty ? null : _content.text.trim(),
        type: _type,
        icon: _icon.text.trim().isEmpty ? null : _icon.text.trim(),
        isActive: _isActive,
      );
      if (_isEdit) {
        await _repo.update(model);
      } else {
        await _repo.create(model);
      }
      if (!mounted) return;
      context.showSuccess(_isEdit ? 'Content updated' : 'Content created');
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
          DropdownButtonFormField<int?>(
            initialValue: _buildingId,
            items: [
              const DropdownMenuItem(value: null, child: Text('None')),
              for (final b in widget.buildings)
                DropdownMenuItem(value: b.id, child: Text(b.name)),
            ],
            onChanged: (v) => setState(() => _buildingId = v),
          ),
          const SizedBox(height: 14),
          FormInput(label: 'Room ID (optional)', controller: _roomId),
          const SizedBox(height: 14),
          FormInput(label: 'Title', controller: _title, required: true),
          const SizedBox(height: 14),
          const Text('Type',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _type,
            items: [
              for (final t in kContentTypes)
                DropdownMenuItem(value: t, child: Text(t)),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 14),
          FormInput(label: 'Icon name', controller: _icon),
          const SizedBox(height: 14),
          FormInput(label: 'Content', controller: _content, maxLines: 5),
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
                              strokeWidth: 2, color: Colors.white))
                      : Text(_isEdit ? 'Save Changes' : 'Create'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
