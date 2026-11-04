import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/announcement_repository.dart';
import '../../../domain/models/announcement_model.dart';
import '../../widgets/form_input.dart';

const kAnnouncementTypes = ['general', 'event', 'maintenance', 'emergency'];

class AnnouncementForm extends StatefulWidget {
  final AnnouncementModel? announcement;

  const AnnouncementForm({super.key, this.announcement});

  @override
  State<AnnouncementForm> createState() => _AnnouncementFormState();
}

class _AnnouncementFormState extends State<AnnouncementForm> {
  final _repo = AnnouncementRepository();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _title;
  late final TextEditingController _body;
  late String _type;
  late bool _isActive;
  DateTime? _expiresAt;
  bool _saving = false;

  bool get _isEdit => widget.announcement != null;

  /// The dropdown options, keeping an unknown type already stored in the row.
  List<String> get _types => [
        ...kAnnouncementTypes,
        if (!kAnnouncementTypes.contains(_type)) _type,
      ];

  @override
  void initState() {
    super.initState();
    final a = widget.announcement;
    _title = TextEditingController(text: a?.title ?? '');
    _body = TextEditingController(text: a?.body ?? '');
    final type = a?.type?.trim() ?? '';
    _type = type.isEmpty ? kAnnouncementTypes.first : type;
    _isActive = a?.isActive ?? true;
    _expiresAt = a?.expiresAt?.toLocal();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final initial = _expiresAt ?? now.add(const Duration(days: 7));
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
          _expiresAt ?? DateTime(now.year, now.month, now.day, 23, 59)),
    );
    if (time == null) return;
    setState(() => _expiresAt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final a = widget.announcement;
      final model = AnnouncementModel(
        id: a?.id,
        title: _title.text.trim(),
        body: _body.text.trim().isEmpty ? null : _body.text.trim(),
        type: _type,
        isActive: _isActive,
        expiresAt: _expiresAt,
        createdAt: a?.createdAt,
        updatedAt: a?.updatedAt,
      );
      if (_isEdit) {
        await _repo.update(model);
      } else {
        await _repo.create(model);
      }
      if (!mounted) return;
      context.showSuccess(
          _isEdit ? 'Announcement updated' : 'Announcement created');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) context.showError(e, onRetry: _save);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expired = _expiresAt != null && _expiresAt!.isBefore(DateTime.now());
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormInput(label: 'Title', controller: _title, required: true),
          const SizedBox(height: 14),
          const Text('Type',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _type,
            items: [
              for (final t in _types)
                DropdownMenuItem(value: t, child: Text(t)),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 14),
          FormInput(label: 'Message', controller: _body, maxLines: 5),
          const SizedBox(height: 14),
          const Text('Expires',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _pickExpiry,
                  icon: const Icon(Icons.event, size: 16),
                  label: Text(_expiresAt == null
                      ? 'Never'
                      : DateFormat('MMM d, y h:mm a').format(_expiresAt!)),
                ),
              ),
              if (_expiresAt != null)
                IconButton(
                  tooltip: 'Remove expiry date',
                  onPressed:
                      _saving ? null : () => setState(() => _expiresAt = null),
                  icon: const Icon(Icons.clear, size: 18),
                ),
            ],
          ),
          if (expired)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('This date has passed, so the announcement is expired.',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.warningAmber)),
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
